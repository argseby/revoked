package services

import (
	"strings"
	"time"

	"revoked/util"

	"github.com/pocketbase/dbx"
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
// which account it reached — but only where [ContactStanding] holds.
//
// The cache is what the app reads to say "delivered to their app", so writing
// it for an address nothing connects us to would leave the answer sitting on
// the contact row: type an address, send once, and the row says whether it
// names an account here. An address that no longer resolves clears the cache
// rather than leaving a name pointing at an account it stopped naming.
func MarkContactUsed(app core.App, contact *core.Record, recipient *core.Record, standing bool) {
	contact.Set(util.Fields.Contact.LastUsedAt, types.NowDateTime())
	if recipient == nil || !standing {
		contact.Set(util.Fields.Contact.User, "")
	} else {
		contact.Set(util.Fields.Contact.User, recipient.Id)
	}
	if err := app.Save(contact); err != nil {
		app.Logger().Error("Failed to stamp contact use", "error", err, "contact", contact.Id)
	}
}

// ContactStanding reports whether anything connects the sender to the account
// their contact names, which is what decides how much the answer may say.
//
// Three things count, and a typed-in address is none of them: the contact was
// proven by the peer check, the two share a workspace, or a grant already came
// the other way. Anybody else is a stranger, however well they know the
// address — knowing it is exactly what the guess provides.
func ContactStanding(app core.App, contact *core.Record, senderId string, recipient *core.Record) bool {
	if recipient == nil || senderId == "" {
		return false
	}
	if recipient.Id == senderId {
		return true
	}
	if contact.GetString(util.Fields.Contact.TrustState) == util.ContactVerified {
		return true
	}
	if sharesWorkspace(app, contact.GetString(util.Fields.Contact.Workspace), recipient.Id) {
		return true
	}
	// Reciprocity: something came from them to this sender. An unreadable
	// count reads as no standing, so a database hiccup cannot hand out the
	// precise answer.
	back, err := contactDeliveries(app, recipient.Id, senderId, 0)
	return err == nil && back > 0
}

// sharesWorkspace reports whether this account is a member of that workspace.
func sharesWorkspace(app core.App, workspaceId, userId string) bool {
	if workspaceId == "" || userId == "" {
		return false
	}
	member, err := app.FindFirstRecordByFilter(util.Coll.WorkspaceMembers,
		util.Fields.WorkspaceMember.Workspace+" = {:workspace} && "+
			util.Fields.WorkspaceMember.User+" = {:user}",
		map[string]any{"workspace": workspaceId, "user": userId})
	return err == nil && member != nil
}

// ContactDeliveryRefusal reports why a grant may not be put in this
// recipient's tray, or "" when it may.
//
// The order matters: a block is the recipient's own decision and holds however
// long the pair have been in touch, while the cap only bounds a sender nothing
// connects them to. Both answers go in the audit row and neither reaches the
// sender.
func ContactDeliveryRefusal(app core.App, sender *core.Record, recipient *core.Record, standing bool) string {
	if ContactSenderBlocked(app, sender, recipient) {
		return util.ContactRefusedBlocked
	}
	if standing {
		return ""
	}
	limit := util.LimitFromEnv(util.ContactPairPerDayEnv, util.DefaultContactPairPerDay)
	if limit <= 0 {
		return ""
	}
	// Fail closed: an unreadable count must not read as budget left. The grant
	// still exists and its slug is still in the answer, so a refusal here
	// costs the sender a tray entry, not the hand-over.
	spent, err := contactDeliveries(app, sender.Id, recipient.Id, util.ContactPairWindow)
	if err != nil || spent >= limit {
		return util.ContactRefusedPairCap
	}
	return ""
}

// ContactSenderBlocked reports whether the recipient refuses this sender: the
// account itself, the address it signed up with, or that address's domain.
func ContactSenderBlocked(app core.App, sender *core.Record, recipient *core.Record) bool {
	if sender == nil || recipient == nil {
		return false
	}
	address := NormalizeEmail(sender.Email())
	block, err := app.FindFirstRecordByFilter(util.Coll.ContactBlocks,
		util.Fields.ContactBlock.User+" = {:user} && ("+
			util.Fields.ContactBlock.BlockedUser+" = {:sender}"+
			" || ("+util.Fields.ContactBlock.Email+" != '' && "+
			util.Fields.ContactBlock.Email+" = {:address})"+
			" || ("+util.Fields.ContactBlock.Domain+" != '' && "+
			util.Fields.ContactBlock.Domain+" = {:domain}))",
		map[string]any{
			"user":    recipient.Id,
			"sender":  sender.Id,
			"address": address,
			"domain":  EmailDomain(address),
		})
	return err == nil && block != nil
}

// RecordContactDelivery adds the ledger row the per-pair cap counts and the
// standing check reads. It is written after the delivery, so a failed write
// never costs the recipient a tray entry they did not get.
func RecordContactDelivery(app core.App, sender *core.Record, recipient *core.Record, workspaceId, kind string) {
	col, err := app.FindCollectionByNameOrId(util.Coll.ContactDeliveries)
	if err != nil {
		app.Logger().Error("Contact delivery ledger missing", "error", err)
		return
	}
	d := util.Fields.ContactDelivery
	row := core.NewRecord(col)
	row.Set(d.Sender, sender.Id)
	row.Set(d.Recipient, recipient.Id)
	row.Set(d.Workspace, workspaceId)
	row.Set(d.Kind, kind)
	if err := app.Save(row); err != nil {
		app.Logger().Error("Failed to record a contact delivery", "error", err)
	}
}

// contactDeliveries counts what this sender put in this recipient's tray
// inside window; a zero window counts all of it, which is the question "has
// anything ever come this way?".
//
// Like the per-address email cap this counts rows rather than keeping a
// counter in memory: the budget protects somebody else's tray, and a
// per-process limiter would hand out one per instance. idxContactDeliveriesPair
// is what keeps the count cheap. The error is returned rather than folded into
// a number because its two readers fail closed in opposite directions — one
// must not find budget, the other must not find standing.
func contactDeliveries(app core.App, senderId, recipientId string, window time.Duration) (int, error) {
	query := `
		SELECT COUNT(*) FROM {{contactDeliveries}}
		WHERE sender = {:sender} AND recipient = {:recipient}`
	params := dbx.Params{"sender": senderId, "recipient": recipientId}
	if window > 0 {
		query += ` AND created > {:cutoff}`
		params["cutoff"] = time.Now().Add(-window).UTC().Format("2006-01-02 15:04:05.000Z")
	}
	var count int
	if err := app.DB().NewQuery(query).Bind(params).Row(&count); err != nil {
		app.Logger().Error("Failed to count contact deliveries", "error", err)
		return 0, err
	}
	return count, nil
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
func DeliverToContact(app core.App, sender *core.Record, recipient *core.Record, kind, slug, label, from string) error {
	if sender != nil {
		f := util.Fields.Bookmark
		existing, err := app.FindFirstRecordByFilter(util.Coll.Bookmarks,
			f.User+" = {:user} && "+f.Sender+" = {:sender} && "+f.Kind+" = {:kind} && "+
				f.Slug+" = {:slug} && "+f.Origin+" = ''",
			dbx.Params{"user": recipient.Id, "sender": sender.Id, "kind": kind, "slug": slug})
		if err == nil && existing != nil {
			return nil
		}
	}
	col, err := app.FindCollectionByNameOrId(util.Coll.Bookmarks)
	if err != nil {
		return err
	}
	bookmark := core.NewRecord(col)
	bookmark.Set(util.Fields.Bookmark.User, recipient.Id)
	// Who put it there, so "stop sending me this" has something to name. The
	// recipient is shown a workspace name, which its own members typed; the
	// account id is the only part of a delivery they can block on.
	if sender != nil {
		bookmark.Set(util.Fields.Bookmark.Sender, sender.Id)
	}
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
