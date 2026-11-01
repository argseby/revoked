package services

import (
	"strings"

	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// ContactAccountHere resolves the account a contact's email address names on
// this server, or nil when that address has none.
//
// The address is the only route a client may write. A contact carries a `user`
// relation, but this server publishes no user directory, so a client that
// could set it would be naming an account it had no way to discover — aiming
// a delivery at a stranger it picked by id. The server resolves the address
// instead and keeps the answer only as a cache.
func ContactAccountHere(app core.App, contact *core.Record) *core.Record {
	email := strings.TrimSpace(contact.GetString(util.Fields.Contact.Email))
	if email == "" {
		return nil
	}
	user, err := app.FindAuthRecordByEmail(util.Coll.Users, email)
	if err != nil || user == nil {
		return nil
	}
	return user
}

// MarkContactUsed records that a grant went out to this contact, and caches
// which account it reached. An address that no longer resolves clears the
// cache rather than leaving a name pointing at an account it stopped naming.
func MarkContactUsed(app core.App, contact *core.Record, recipient *core.Record) {
	contact.Set(util.Fields.Contact.LastUsedAt, types.NowDateTime())
	if recipient == nil {
		contact.Set(util.Fields.Contact.User, "")
	} else {
		contact.Set(util.Fields.Contact.User, recipient.Id)
	}
	if err := app.Save(contact); err != nil {
		app.Logger().Error("Failed to stamp contact use", "error", err, "contact", contact.Id)
	}
}

// DeliverToContact puts a freshly minted grant in the recipient's own tray and
// tells them it arrived.
//
// It writes a bookmark — a pointer the recipient can remove — and never into
// their vault: opening it goes through the same public view as the slug
// itself, with every gate and view cap still applying. This is the one path
// that writes into another person's account, which is why it reaches only
// accounts on this server: a cross-server push would accept deliveries from
// anywhere, with nobody's consent anywhere in it.
func DeliverToContact(app core.App, recipient *core.Record, kind, slug, label, from string) error {
	col, err := app.FindCollectionByNameOrId(util.Coll.Bookmarks)
	if err != nil {
		return err
	}
	bookmark := core.NewRecord(col)
	bookmark.Set(util.Fields.Bookmark.User, recipient.Id)
	// Empty origin means the server the account lives on, which is this one.
	bookmark.Set(util.Fields.Bookmark.Origin, "")
	bookmark.Set(util.Fields.Bookmark.Slug, slug)
	bookmark.Set(util.Fields.Bookmark.Kind, kind)
	bookmark.Set(util.Fields.Bookmark.Label, label)
	if err := app.Save(bookmark); err != nil {
		return err
	}

	title, message := contactDeliveryCopy(kind, label, from)
	EmitNotification(app, recipient.Id,
		recipient.GetString(util.Fields.User.ActiveWorkspace),
		contactNotificationType(kind),
		title, message,
		util.Coll.Bookmarks, bookmark.Id)
	return nil
}

func contactNotificationType(kind string) string {
	if kind == util.BookmarkKindRequest {
		return util.NotificationContactAsk
	}
	return util.NotificationContactShare
}

func contactDeliveryCopy(kind, label, from string) (title, message string) {
	who := from
	if who == "" {
		who = "Someone on this server"
	}
	if kind == util.BookmarkKindRequest {
		return "Someone needs something from you", who + " asked you for " + quoted(label) + "."
	}
	return "Something was shared with you", who + " shared " + quoted(label) + " with you."
}

func quoted(text string) string {
	return "“" + text + "”"
}

// ContactSenderName names who a grant came from, for the person receiving it.
// The identity is preferred because it is anchored in DNS; the workspace name
// is only what its own members typed.
func ContactSenderName(app core.App, workspaceId, identityId string) string {
	if identityId != "" {
		if id, err := app.FindRecordById(util.Coll.Identities, identityId); err == nil && id != nil {
			name := id.GetString(util.Fields.Identity.Name)
			if domain := id.GetString(util.Fields.Identity.DomainAtIssue); name != "" && domain != "" {
				return name + " (" + domain + ")"
			}
			if name != "" {
				return name
			}
		}
	}
	if workspaceId != "" {
		if ws, err := app.FindRecordById(util.Coll.Workspaces, workspaceId); err == nil && ws != nil {
			return ws.GetString(util.Fields.Workspace.Name)
		}
	}
	return ""
}
