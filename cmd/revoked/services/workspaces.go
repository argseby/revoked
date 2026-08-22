package services

import (
	"fmt"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// workspaceTeardown lists the collections emptied when a workspace is deleted,
// children before the workspace itself.
//
// Most of these hold a *required* workspace relation that does not cascade, so
// PocketBase answers a delete with "record is part of a required relation
// reference" until they are gone — an empty workspace could be deleted and a
// used one never could.
//
// auditLogs is in the list deliberately: secrets are redacted from the
// snapshots (invariant #10), but every row still pins a member's IP and user
// agent to what they did, which does not outlive the workspace it describes.
//
// requestResponses is write-dead but not row-dead: historical rows still hold a
// required workspace relation, and one left behind refuses the delete.
var workspaceTeardown = []string{
	util.Coll.Handshakes,
	util.Coll.Links,
	util.Coll.RequestResponses,
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

// TearDownWorkspace deletes everything belonging to one workspace, leaving the
// workspace row itself for the caller.
//
// Records go one at a time through app.Delete rather than in a single
// statement, because their delete hooks are the point: an identity must leave a
// revocation tombstone behind, or every certificate this workspace issued goes
// on proving membership of it with nothing left to contradict them.
func TearDownWorkspace(app core.App, workspaceId string) error {
	if workspaceId == "" {
		return nil
	}
	for _, collection := range workspaceTeardown {
		records, err := app.FindAllRecords(collection, dbx.HashExp{util.FieldWorkspace: workspaceId})
		if err != nil {
			return fmt.Errorf("load %s: %w", collection, err)
		}
		for _, record := range records {
			if err := app.Delete(record); err != nil {
				return fmt.Errorf("delete %s: %w", collection, err)
			}
		}
	}
	return nil
}
