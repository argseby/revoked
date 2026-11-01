package services

import (
	"slices"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// IsSealed reports whether a record's value is end-to-end encrypted, and so
// cannot be read, copied or served by this server.
func IsSealed(rec *core.Record) bool {
	return rec != nil && rec.GetBool(util.Fields.Record.Sealed)
}

// IsSealedThroughAlias reports whether a record, or the entry an alias reads
// through, is sealed.
func IsSealedThroughAlias(app core.App, rec *core.Record) bool {
	if IsSealed(rec) {
		return true
	}
	if rec == nil {
		return false
	}
	parentID := rec.GetString(util.Fields.Record.AliasOf)
	if parentID == "" {
		return false
	}
	parent, err := app.FindRecordById(util.Coll.Records, parentID)
	return err == nil && IsSealed(parent)
}

// CurrentKeyEpoch returns a workspace's newest key epoch, or nil if nobody has
// turned sealing on there.
func CurrentKeyEpoch(app core.App, workspaceID string) *core.Record {
	e := util.Fields.WorkspaceKeyEpoch
	rows, err := app.FindRecordsByFilter(util.Coll.WorkspaceKeyEpochs,
		e.Workspace+" = {:w}", "-"+e.Epoch, 1, 0, dbx.Params{"w": workspaceID})
	if err != nil || len(rows) == 0 {
		return nil
	}
	return rows[0]
}

// HoldsWorkspaceKey reports whether any of the user's devices was handed the
// key of this epoch.
func HoldsWorkspaceKey(app core.App, workspaceID, userID string, epoch int) bool {
	w := util.Fields.WorkspaceKeyWrap
	row, _ := app.FindFirstRecordByFilter(util.Coll.WorkspaceKeyWraps,
		w.Workspace+" = {:w} && "+w.User+" = {:u} && "+w.Epoch+" = {:e}",
		dbx.Params{"w": workspaceID, "u": userID, "e": epoch})
	return row != nil
}

// MarkKeyRotationDue flags that someone who held a workspace's key no longer
// should. Sealed writes are refused until a key holder starts a new epoch, so
// nothing new is written under a key the departed party still has.
func MarkKeyRotationDue(app core.App, workspaceID string) error {
	current := CurrentKeyEpoch(app, workspaceID)
	if current == nil {
		return nil
	}
	current.Set(util.Fields.WorkspaceKeyEpoch.RotationDue, true)
	return app.Save(current)
}

// RevokeSealedAccess withdraws a departing member's copies of a workspace's
// key, inside the removal's own transaction. They may have kept the key itself,
// which is why this also makes a new epoch due.
func RevokeSealedAccess(app core.App, userID, workspaceID string) error {
	w := util.Fields.WorkspaceKeyWrap
	rows, err := app.FindRecordsByFilter(util.Coll.WorkspaceKeyWraps,
		w.Workspace+" = {:w} && "+w.User+" = {:u}", "", 0, 0,
		dbx.Params{"w": workspaceID, "u": userID})
	if err != nil || len(rows) == 0 {
		return err
	}
	for _, row := range rows {
		if err := app.Delete(row); err != nil {
			return err
		}
	}
	return MarkKeyRotationDue(app, workspaceID)
}

// DetachSealedRecord takes a newly sealed record off every link that names it,
// directly or through an alias. Reads would drop it anyway, but leaving the id
// behind means unsealing it later would quietly share it on links its owner
// had given up on. A link reading a whole section still shows it again if it is
// ever unsealed, because that link shares the section as it stands.
func DetachSealedRecord(app core.App, recordID string) error {
	f := util.Fields.Link
	ids := []string{recordID}
	aliases, err := app.FindRecordsByFilter(util.Coll.Records,
		util.Fields.Record.AliasOf+" = {:r}", "", 0, 0, dbx.Params{"r": recordID})
	if err != nil {
		return err
	}
	for _, a := range aliases {
		ids = append(ids, a.Id)
	}
	for _, id := range ids {
		links, err := app.FindRecordsByFilter(util.Coll.Links,
			f.Records+" ~ {:id}", "", 0, 0, dbx.Params{"id": id})
		if err != nil {
			return err
		}
		for _, link := range links {
			link.Set(f.Records, slices.DeleteFunc(link.GetStringSlice(f.Records),
				func(r string) bool { return r == id }))
			// An answer also holds a snapshot of what it granted. Once the grant
			// is gone, reads fall through to the snapshot and serve it, so the
			// plaintext has to go with the grant.
			data := map[string]any{}
			_ = link.UnmarshalJSONField(f.Data, &data)
			grants := LinkGrantMap(link)
			for key, granted := range grants {
				if granted == id {
					delete(grants, key)
					delete(data, key)
				}
			}
			link.Set(f.Grants, grants)
			if len(data) > 0 {
				link.Set(f.Data, data)
			} else {
				link.Set(f.Data, nil)
			}
			if err := app.Save(link); err != nil {
				return err
			}
		}
	}
	return nil
}

// NotifySealingReset tells someone their encrypted records were deleted. Anyone
// holding their session can ask for this, so they must at least find out.
func NotifySealingReset(app core.App, userID, workspaceID string) {
	EmitNotification(app, userID, workspaceID, util.NotificationSealingReset,
		"Your encrypted records were reset",
		"Someone signed in as you started over with encryption. If that wasn't you, sign out everywhere and change how you sign in.",
		util.Coll.DeviceKeys, userID)
}

// LiveLinksReading counts the active or paused links that would stop showing a
// record once it is sealed, directly, through a section or through an alias.
func LiveLinksReading(app core.App, recordID string) int {
	f := util.Fields.Link
	ids := []string{recordID}
	aliases, _ := app.FindRecordsByFilter(util.Coll.Records,
		util.Fields.Record.AliasOf+" = {:r}", "", 0, 0, dbx.Params{"r": recordID})
	for _, a := range aliases {
		ids = append(ids, a.Id)
	}

	counted := map[string]bool{}
	count := func(field, id string) {
		links, _ := app.FindRecordsByFilter(util.Coll.Links,
			field+" ~ {:id} && ("+f.Status+" = {:a} || "+f.Status+" = {:p})", "", 0, 0,
			dbx.Params{"id": id, "a": util.StatusActive, "p": util.StatusPaused})
		for _, l := range links {
			counted[l.Id] = true
		}
	}
	for _, id := range ids {
		count(f.Records, id)
		sections, _ := app.FindRecordsByFilter(util.Coll.Sections,
			util.Fields.Section.Records+" ~ {:id}", "", 0, 0, dbx.Params{"id": id})
		for _, s := range sections {
			count(f.Sections, s.Id)
		}
	}
	return len(counted)
}
