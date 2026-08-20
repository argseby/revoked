package services

import (
	"errors"
	"fmt"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// ErrAccountLastAdmin reports that the account still administers a workspace
// other people belong to, so closing it would leave them with nobody able to
// manage membership.
var ErrAccountLastAdmin = errors.New("last admin of a shared workspace")

// workspaceTeardown lists the collections emptied when a workspace the account
// alone belongs to is torn down, children before the workspace itself.
//
// auditLogs is in the list deliberately: secrets are redacted from the
// snapshots (invariant #10), but every row still pins the account's IP and
// user agent to what it did — exactly the trail deleting an account promises
// to remove.
var workspaceTeardown = []string{
	util.Coll.Handshakes,
	util.Coll.Links,
	util.Coll.Requests,
	util.Coll.Notifications,
	util.Coll.Invites,
	util.Coll.Templates,
	util.Coll.Identities,
	util.Coll.ApiKeys,
	util.Coll.Sections,
	util.Coll.Records,
	util.Coll.AuditLogs,
	util.Coll.WorkspaceMembers,
}

// accountOwned lists what dies with the account wherever it is found, including
// in workspaces it merely shared: everything that still reaches data or acts as
// the user.
//
// auditLogs is here for the same reason it is in workspaceTeardown, and can
// outlive every workspace besides: a write made before one existed is logged
// without one.
var accountOwned = []string{
	util.Coll.Links,
	util.Coll.Requests,
	util.Coll.Identities,
	util.Coll.ApiKeys,
	util.Coll.Notifications,
	util.Coll.AuditLogs,
}

// workspaceContent lists what stays behind in a workspace the account shared,
// as it does when a member merely leaves. Both hold a *required* user relation,
// so each row has to be handed to somebody who remains — left dangling, it
// refuses the account's own deletion.
var workspaceContent = []string{
	util.Coll.Sections,
	util.Coll.Records,
}

// PurgeAccount deletes everything the account can still be reached through and
// then the account itself, in one transaction.
//
// Deleting the users row on its own is not enough and is worse than doing
// nothing: no relation to it cascades, so the workspaces, records and links
// would outlive their owner with every `/s/{slug}` still resolving and nobody
// left who could revoke them.
func PurgeAccount(app core.App, userId string) error {
	memberships, err := app.FindAllRecords(util.Coll.WorkspaceMembers,
		dbx.HashExp{util.Fields.WorkspaceMember.User: userId})
	if err != nil {
		return err
	}

	var sole, shared []string
	for _, member := range memberships {
		workspaceId := member.GetString(util.Fields.WorkspaceMember.Workspace)

		peers, err := app.FindAllRecords(util.Coll.WorkspaceMembers,
			dbx.HashExp{util.Fields.WorkspaceMember.Workspace: workspaceId})
		if err != nil {
			return err
		}
		if len(peers) <= 1 {
			sole = append(sole, workspaceId)
			continue
		}
		if MemberCanAdminister(member) && WorkspaceAdminCount(app, workspaceId, member.Id) == 0 {
			return ErrAccountLastAdmin
		}
		shared = append(shared, workspaceId)
	}

	return app.RunInTransaction(func(txApp core.App) error {
		for _, workspaceId := range sole {
			for _, collection := range workspaceTeardown {
				if err := deleteWhere(txApp, collection, dbx.HashExp{util.FieldWorkspace: workspaceId}); err != nil {
					return err
				}
			}
			workspace, err := txApp.FindRecordById(util.Coll.Workspaces, workspaceId)
			if err != nil {
				return err
			}
			if err := txApp.Delete(workspace); err != nil {
				return err
			}
		}

		for _, workspaceId := range shared {
			successor, err := successorIn(txApp, workspaceId, userId)
			if err != nil {
				return err
			}
			for _, collection := range workspaceContent {
				if err := reassign(txApp, collection, workspaceId, userId, successor); err != nil {
					return err
				}
			}
		}

		for _, collection := range accountOwned {
			if err := deleteWhere(txApp, collection, dbx.HashExp{util.FieldUser: userId}); err != nil {
				return err
			}
		}

		// The signup row is written before the account can authenticate, so it
		// carries no user to match on — only the id of the row it created, and
		// the submitted email in its payload.
		if err := deleteWhere(txApp, util.Coll.AuditLogs,
			dbx.HashExp{util.Fields.AuditLog.RecordId: userId}); err != nil {
			return err
		}

		user, err := txApp.FindRecordById(util.Coll.Users, userId)
		if err != nil {
			return err
		}
		// Memberships of workspaces the account shared go with it: that
		// relation is the one thing pointing at users that does cascade.
		return txApp.Delete(user)
	})
}

// successorIn picks who inherits the leaving account's content in a shared
// workspace, preferring someone who can already administer it.
func successorIn(app core.App, workspaceId, leavingUserId string) (string, error) {
	members, err := app.FindAllRecords(util.Coll.WorkspaceMembers,
		dbx.HashExp{util.Fields.WorkspaceMember.Workspace: workspaceId})
	if err != nil {
		return "", err
	}

	fallback := ""
	for _, member := range members {
		candidate := member.GetString(util.Fields.WorkspaceMember.User)
		if candidate == leavingUserId {
			continue
		}
		if MemberCanAdminister(member) {
			return candidate, nil
		}
		if fallback == "" {
			fallback = candidate
		}
	}
	if fallback == "" {
		return "", fmt.Errorf("workspace %s has nobody to inherit its content", workspaceId)
	}
	return fallback, nil
}

// reassign hands the leaving account's rows in one collection to successor.
// Saved directly, so it bypasses the request hooks and the audit log: this is a
// server-side custody change, not something the account did.
func reassign(app core.App, collection, workspaceId, fromUserId, toUserId string) error {
	records, err := app.FindAllRecords(collection, dbx.HashExp{
		util.FieldWorkspace: workspaceId,
		util.FieldUser:      fromUserId,
	})
	if err != nil {
		return fmt.Errorf("load %s: %w", collection, err)
	}
	for _, record := range records {
		record.Set(util.FieldUser, toUserId)
		if err := app.Save(record); err != nil {
			return fmt.Errorf("reassign %s: %w", collection, err)
		}
	}
	return nil
}

func deleteWhere(app core.App, collection string, where dbx.Expression) error {
	records, err := app.FindAllRecords(collection, where)
	if err != nil {
		return fmt.Errorf("load %s: %w", collection, err)
	}
	for _, record := range records {
		if err := app.Delete(record); err != nil {
			return fmt.Errorf("delete %s: %w", collection, err)
		}
	}
	return nil
}
