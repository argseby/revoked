package util

import (
	"slices"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// AccessKind is the shape of an authorization requirement.
type AccessKind int

const (
	// AccessUserSelf — the owning user only, no API keys.
	AccessUserSelf AccessKind = iota
	// AccessWorkspaceMember — any member of the record's workspace.
	AccessWorkspaceMember
	// AccessWorkspaceSelf — a member of the workspace who also owns the record.
	AccessWorkspaceSelf
	// AccessWorkspaceAdmin — an admin of the target workspace.
	AccessWorkspaceAdmin
	// AccessWorkspaceAdminSelf — the record owner, admin in their active workspace.
	AccessWorkspaceAdminSelf
	// AccessWorkspaceSplitOrigin — like AccessWorkspaceSelf, but vault entries
	// and request-collected data are governed by different scopes.
	AccessWorkspaceSplitOrigin
)

// AccessSpec declares who may perform an action on a collection.
//
// [AccessSpec.Rule] and [AccessSpec.Diagnose] must never disagree: PocketBase
// evaluates the rule before any hook runs and discards the reason, so the
// explanation has to be derived from this same declaration.
type AccessSpec struct {
	Kind AccessKind
	// Scope is the API-key scope accepted here; empty means API keys are not
	// accepted at all.
	Scope string
	// WorkspaceField is the column holding the workspace id; empty defaults to
	// "workspace".
	WorkspaceField string
	// Extra is an additional clause ANDed onto the whole rule. Rule()
	// parenthesizes the kind's expression first: AND binds tighter than OR, so
	// without the parens the clause would attach to the last branch only.
	Extra string
	// ResponseScope governs rows created by answering a request, where Scope
	// governs the rest. Only meaningful for AccessWorkspaceSplitOrigin.
	ResponseScope string
}

func (s AccessSpec) workspaceField() string {
	if s.WorkspaceField == "" {
		return FieldWorkspace
	}
	return s.WorkspaceField
}

// Rule renders the PocketBase filter string enforcing this spec.
func (s AccessSpec) Rule() string {
	var base string
	switch s.Kind {
	case AccessUserSelf:
		base = UserSelfOnly()
	case AccessWorkspaceMember:
		base = WorkspaceAnyMember(s.Scope)
	case AccessWorkspaceSelf:
		base = WorkspaceSelfOnly(s.Scope)
	case AccessWorkspaceAdmin:
		base = WorkspaceAnyAdmin(s.Scope, s.workspaceField())
	case AccessWorkspaceAdminSelf:
		base = WorkspaceAdminSelfOnly(s.Scope, s.workspaceField())
	case AccessWorkspaceSplitOrigin:
		base = WorkspaceSplitOrigin(s.Scope, s.ResponseScope)
	}
	if s.Extra != "" {
		return "(" + base + ") && " + s.Extra
	}
	return base
}

// AccessSubject is the caller plus the record they are acting on. On create the
// record does not exist yet: RecordUser is empty and RecordWorkspace is whatever
// the payload asked for.
type AccessSubject struct {
	Auth            *core.Record
	IsSuperuser     bool
	RecordWorkspace string
	RecordUser      string
	// RecordIsResponse marks a row that exists because someone answered a
	// request, selecting ResponseScope over Scope on a split-origin spec.
	RecordIsResponse bool
}

// requiredScope is the scope this spec demands for the subject's record.
func (s AccessSpec) requiredScope(subj AccessSubject) string {
	if s.Kind == AccessWorkspaceSplitOrigin && subj.RecordIsResponse {
		return s.ResponseScope
	}
	return s.Scope
}

// Diagnose returns every reason the subject fails this spec, keyed by the field
// responsible; an empty result means the spec is satisfied.
//
// Messages must never name server-held values (the workspace a key is bound to,
// another record's owner) — errors end up in logs and bug reports read by people
// who never held the credential. Caller-supplied input and fixed API-contract
// values such as the required scope name are fine.
func (s AccessSpec) Diagnose(app core.App, subj AccessSubject) validation.Errors {
	errs := validation.Errors{}

	if subj.IsSuperuser {
		return errs
	}
	if subj.Auth == nil {
		errs["auth"] = AsValidationError(Errors.NotAuthenticated)
		return errs
	}

	switch subj.Auth.Collection().Name {
	case Coll.ApiKeys:
		s.diagnoseApiKey(subj, errs)
	case Coll.Users:
		s.diagnoseUser(app, subj, errs)
	}
	return errs
}

func (s AccessSpec) diagnoseApiKey(subj AccessSubject, errs validation.Errors) {
	if s.Kind == AccessUserSelf || s.Scope == "" {
		errs["auth"] = AsValidationError(Errors.ApiKeyNotPermitted)
		return
	}

	if want := s.requiredScope(subj); !hasScopeValue(subj.Auth.GetStringSlice(Fields.ApiKey.Scopes), want) {
		errs[Fields.ApiKey.Scopes] = validation.NewError(
			Errors.InvalidScope.ErrorCode,
			"This API key is missing the required scope: "+want+".",
		)
	}

	keyWorkspace := subj.Auth.GetString(Fields.ApiKey.Workspace)
	if subj.RecordWorkspace != "" && subj.RecordWorkspace != keyWorkspace {
		errs[FieldWorkspace] = validation.NewError(
			Errors.ActiveWorkspaceMismatch.ErrorCode,
			"The workspace in this request is not the one this API key is bound to.",
		)
	}
}

func (s AccessSpec) diagnoseUser(app core.App, subj AccessSubject, errs validation.Errors) {
	activeWorkspace := subj.Auth.GetString(Fields.User.ActiveWorkspace)

	if s.Kind == AccessUserSelf {
		if subj.RecordUser != "" && subj.RecordUser != subj.Auth.Id {
			errs[FieldUser] = AsValidationError(Errors.NotRecordOwner)
		}
		return
	}

	target := subj.RecordWorkspace
	if target == "" {
		target = activeWorkspace
	}

	needsActiveContext := s.Kind == AccessWorkspaceMember ||
		s.Kind == AccessWorkspaceSelf ||
		s.Kind == AccessWorkspaceSplitOrigin ||
		s.Kind == AccessWorkspaceAdminSelf

	if needsActiveContext {
		if activeWorkspace == "" {
			errs[FieldWorkspace] = AsValidationError(Errors.MissingActiveWorkspace)
		} else if subj.RecordWorkspace != "" && subj.RecordWorkspace != activeWorkspace {
			errs[FieldWorkspace] = validation.NewError(
				Errors.ActiveWorkspaceMismatch.ErrorCode,
				"The workspace in this request is not your active workspace.",
			)
		}
	}

	if s.Kind == AccessWorkspaceAdminSelf {
		if subj.Auth.GetString(Fields.User.ActiveRole) != RoleAdmin {
			errs["role"] = AsValidationError(Errors.NotWorkspaceAdmin)
		}
		if subj.RecordUser != "" && subj.RecordUser != subj.Auth.Id {
			errs[FieldUser] = AsValidationError(Errors.NotRecordOwner)
		}
		return
	}

	if target == "" {
		return
	}
	member, found := WorkspaceMemberOf(app, target, subj.Auth.Id)
	if !found {
		errs["membership"] = AsValidationError(Errors.NotWorkspaceMember)
		return
	}
	permissions := member.GetStringSlice(Fields.WorkspaceMember.Permissions)

	// The collection rule can only gate on membership and the role
	// denormalization, so the precise permission is checked here. A row with no
	// permissions predates them: fall back to the role it was created with.
	legacy := len(permissions) == 0
	isAdminRole := member.GetString(Fields.WorkspaceMember.Role) == RoleAdmin

	switch s.Kind {
	case AccessWorkspaceAdmin:
		if legacy {
			if !isAdminRole {
				errs["role"] = AsValidationError(Errors.NotWorkspaceAdmin)
			}
		} else if !hasScopeValue(permissions, s.Scope) {
			errs[Fields.WorkspaceMember.Permissions] = validation.NewError(
				Errors.MissingPermission.ErrorCode,
				"Your access to this workspace does not include: "+s.Scope+".",
			)
		}
	case AccessWorkspaceSelf, AccessWorkspaceSplitOrigin:
		// Owning the row is always enough; otherwise the grant decides.
		owned := subj.RecordUser != "" && subj.RecordUser == subj.Auth.Id
		if owned || legacy {
			return
		}
		if want := s.requiredScope(subj); !hasScopeValue(permissions, want) {
			errs[Fields.WorkspaceMember.Permissions] = validation.NewError(
				Errors.MissingPermission.ErrorCode,
				"Your access to this workspace does not include: "+want+".",
			)
		}
	}
}

// WorkspaceMemberOf returns the caller's membership row in a workspace.
func WorkspaceMemberOf(app core.App, workspaceId, userId string) (*core.Record, bool) {
	member, err := app.FindFirstRecordByFilter(
		Coll.WorkspaceMembers,
		"workspace = {:w} && user = {:u}",
		dbx.Params{"w": workspaceId, "u": userId},
	)
	if err != nil || member == nil {
		return nil, false
	}
	return member, true
}

func hasScopeValue(scopes []string, want string) bool {
	return slices.Contains(scopes, want)
}
