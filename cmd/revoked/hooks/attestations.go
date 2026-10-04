package hooks

import (
	"net/http"
	"slices"
	"strings"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/pocketbase/pocketbase/tools/types"
)

// The token alone lets its bearer read what an offer states and, with an
// identity of their own, accept it: a share slug's entropy budget.
const attestationTokenBytes = 24

// attestationFixedFields are what an attestation states and whom it is for.
// A credential may already carry them, so none can change on the row.
var attestationFixedFields = []string{
	util.Fields.Attestation.User,
	util.Fields.Attestation.Workspace,
	util.Fields.Attestation.Type,
	util.Fields.Attestation.Claims,
	util.Fields.Attestation.ExpiresAt,
	util.Fields.Attestation.OfferTokenHash,
	util.Fields.Attestation.OfferExpiresAt,
	util.Fields.Attestation.SubjectFingerprint,
	util.Fields.Attestation.SubjectDomain,
	util.Fields.Attestation.SubjectName,
	util.Fields.Attestation.IssuedAt,
	util.Fields.Attestation.RevokedAt,
}

// BindAttestationHooks turns a created attestation into an offer with a
// one-time token, keeps what it states fixed afterwards, lets its status only
// move towards revoked, and carries every revocation — and every deletion —
// into the published status list.
func BindAttestationHooks(app core.App) {
	f := util.Fields.Attestation

	app.OnRecordCreateRequest(util.Coll.Attestations).BindFunc(func(e *core.RecordRequestEvent) error {
		// The operator decides whether this server speaks for its domain. A
		// superuser is the operator.
		if !util.AttestationsAllowed() && !e.RequestEvent.HasSuperuserAuth() {
			reason := util.Errors.AttestationsDisabled
			return router.NewApiError(http.StatusForbidden, reason.ErrorText, validation.Errors{
				"attestations": validation.NewError(reason.ErrorCode, reason.ErrorText),
			})
		}
		if err := validateAttestation(e.Record); err != nil {
			return err
		}

		// What the server decides is never taken from the request.
		e.Record.Set(f.Status, util.StatusOffered)
		e.Record.Set(f.SubjectDomain, "")
		e.Record.Set(f.SubjectName, "")
		e.Record.Set(f.IssuedAt, nil)
		e.Record.Set(f.RevokedAt, nil)
		e.Record.Set(f.RevokedReason, "")
		if e.Record.GetDateTime(f.OfferExpiresAt).IsZero() {
			until, _ := types.ParseDateTime(time.Now().Add(util.AttestationOfferTTL))
			e.Record.Set(f.OfferExpiresAt, until)
		}

		token, err := util.GenerateToken(attestationTokenBytes)
		if err != nil {
			return e.RequestEvent.InternalServerError("Failed to generate an offer token", nil)
		}
		e.Record.Set(f.OfferTokenHash, util.HashToken(token))

		// The plaintext exists only in this response; only its hash is stored.
		e.RequestEvent.Response.Header().Set("X-Attestation-Token", token)
		e.RequestEvent.Response.Header().Set("Access-Control-Expose-Headers", "X-Attestation-Token")
		return e.Next()
	})

	app.OnRecordUpdateRequest(util.Coll.Attestations).BindFunc(func(e *core.RecordRequestEvent) error {
		if e.RequestEvent.HasSuperuserAuth() {
			return e.Next()
		}
		if info, err := e.RequestInfo(); err == nil {
			errs := validation.Errors{}
			for _, field := range attestationFixedFields {
				if _, sent := info.Body[field]; sent {
					errs[field] = util.AsValidationError(util.Errors.AttestationImmutable)
				}
			}
			if len(errs) > 0 {
				return errs
			}
		}
		applyAttestationTransition(e.Record)
		return e.Next()
	})

	// Model-level rather than request-level, and inside the save's own
	// transaction: however an attestation comes to be revoked, its bit is set
	// with it or not at all.
	app.OnRecordUpdate(util.Coll.Attestations).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		if e.Record.GetString(f.Status) == util.StatusRevoked {
			return services.RevokeAttestationStatus(e.App, e.Record.Id)
		}
		return nil
	})

	// A deleted attestation is a revoked one. The row can go — with its
	// workspace, or because its issuer removed it — but the credential it
	// issued is still out there, and nothing else would ever contradict it.
	app.OnRecordDelete(util.Coll.Attestations).BindFunc(func(e *core.RecordEvent) error {
		id := e.Record.Id
		if err := e.Next(); err != nil {
			return err
		}
		return services.RevokeAttestationStatus(e.App, id)
	})

	// Reading is narrowed to the permission here: a collection rule can say
	// "a member of this workspace", not "a member who may see attestations",
	// and a row states things about a person.
	app.OnRecordsListRequest(util.Coll.Attestations).BindFunc(func(e *core.RecordsListRequestEvent) error {
		if err := requireAttestationRead(e.App, e.RequestEvent, ""); err != nil {
			return err
		}
		return e.Next()
	})
	app.OnRecordViewRequest(util.Coll.Attestations).BindFunc(func(e *core.RecordRequestEvent) error {
		if err := requireAttestationRead(e.App, e.RequestEvent, e.Record.GetString(f.Workspace)); err != nil {
			return err
		}
		return e.Next()
	})
}

// validateAttestation checks what an offer states before it exists.
func validateAttestation(rec *core.Record) error {
	f := util.Fields.Attestation
	errs := validation.Errors{}

	if !util.ValidAttestationType(rec.GetString(f.Type)) {
		errs[f.Type] = util.AsValidationError(util.Errors.AttestationTypeInvalid)
	}

	claims := map[string]any{}
	if raw := rec.GetString(f.Claims); raw != "" && raw != "null" {
		if err := rec.UnmarshalJSONField(f.Claims, &claims); err != nil {
			errs[f.Claims] = util.AsValidationError(util.Errors.AttestationClaimsInvalid)
		}
	}
	if len(claims) > util.MaxAttestationClaims {
		errs[f.Claims] = util.AsValidationError(util.Errors.AttestationClaimsInvalid)
	}
	for name, value := range claims {
		ok, reserved := util.ValidAttestationClaimName(name)
		switch {
		case reserved:
			errs[f.Claims] = util.AsValidationError(util.Errors.AttestationClaimReserved)
		case !ok || !util.ValidAttestationClaimValue(value):
			errs[f.Claims] = util.AsValidationError(util.Errors.AttestationClaimsInvalid)
		}
	}
	// An empty object rather than nothing, so the row always reads the same.
	rec.Set(f.Claims, claims)

	if fingerprint := strings.ToLower(strings.TrimSpace(rec.GetString(f.SubjectFingerprint))); fingerprint != "" {
		if !server.ValidIdentityFingerprint(fingerprint) {
			errs[f.SubjectFingerprint] = util.AsValidationError(util.Errors.AttestationSubjectInvalid)
		}
		rec.Set(f.SubjectFingerprint, fingerprint)
	}

	now := time.Now()
	for _, field := range []string{f.ExpiresAt, f.OfferExpiresAt} {
		if at := rec.GetDateTime(field); !at.IsZero() && !at.Time().After(now) {
			errs[field] = util.AsValidationError(util.Errors.AttestationExpiryInvalid)
		}
	}

	if len(errs) > 0 {
		return errs
	}
	return nil
}

// applyAttestationTransition keeps the status moving in one direction. An
// offer or an issued attestation may be revoked; nothing comes back from
// revoked, and only accepting an offer makes it active.
func applyAttestationTransition(rec *core.Record) {
	f := util.Fields.Attestation
	original := rec.Original()
	was, now := original.GetString(f.Status), rec.GetString(f.Status)

	switch {
	case was == util.StatusRevoked:
		rec.Set(f.Status, util.StatusRevoked)
		rec.Set(f.RevokedAt, original.GetDateTime(f.RevokedAt))
		rec.Set(f.RevokedReason, original.GetString(f.RevokedReason))
	case now == util.StatusRevoked:
		rec.Set(f.RevokedAt, types.NowDateTime())
		if !slices.Contains(util.RevocationReasons, rec.GetString(f.RevokedReason)) {
			rec.Set(f.RevokedReason, util.RevocationManual)
		}
	default:
		rec.Set(f.Status, was)
		rec.Set(f.RevokedReason, "")
	}
}

// requireAttestationRead refuses a signed-in member who lacks the permission.
// API keys are held to their scope by the collection rule and the tenancy
// hook; a superuser is not held to anything.
func requireAttestationRead(app core.App, re *core.RequestEvent, workspaceId string) error {
	if re.HasSuperuserAuth() || re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
		return nil
	}
	if workspaceId == "" {
		workspaceId = re.Auth.GetString(util.Fields.User.ActiveWorkspace)
	}
	if workspaceId == "" {
		return nil
	}
	member, found := util.WorkspaceMemberOf(app, workspaceId, re.Auth.Id)
	if !found {
		return nil
	}
	permissions := member.GetStringSlice(util.Fields.WorkspaceMember.Permissions)
	// A row with no permissions predates them: its role stands in.
	allowed := slices.Contains(permissions, util.ScopeAttestationRead)
	if len(permissions) == 0 {
		allowed = member.GetString(util.Fields.WorkspaceMember.Role) == util.RoleAdmin
	}
	if allowed {
		return nil
	}
	return router.NewApiError(http.StatusForbidden, "Not permitted to read attestations.", validation.Errors{
		util.Fields.WorkspaceMember.Permissions: validation.NewError(
			util.Errors.MissingPermission.ErrorCode,
			"Your access to this workspace does not include: "+util.ScopeAttestationRead+".",
		),
	})
}
