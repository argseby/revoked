package tests

import (
	"net/http"
	"strings"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
	"github.com/google/uuid"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// contactParty is one account in a send-or-ask exchange.
type contactParty struct {
	id, token, email, workspace string
}

func newContactParty(t *testing.T, baseURL string) contactParty {
	t.Helper()
	id, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	api := testutils.NewPBClient(t, baseURL)
	refreshed := api.AuthRefresh(util.Coll.Users, token).Expect().Status(http.StatusOK).
		JSON().Object()
	record := refreshed.Value("record").Object()
	return contactParty{
		id:        id,
		token:     refreshed.Value("token").String().Raw(),
		email:     record.Value(util.Fields.User.Email).String().Raw(),
		workspace: record.Value(util.Fields.User.ActiveWorkspace).String().Raw(),
	}
}

// grant posts to one of the contact grant routes.
func grant(t *testing.T, baseURL, action, contactID, token string, body map[string]any) *httpexpect.Request {
	t.Helper()
	req := testutils.NewExpect(t, baseURL).
		Request("POST", "/api/contacts/"+contactID+"/"+action).
		WithJSON(body)
	if token != "" {
		req = req.WithHeader("Authorization", token)
	}
	return req
}

func newContact(t *testing.T, baseURL, token, workspace, name, email string) string {
	t.Helper()
	return extractID(t, baseURL, util.Coll.Contacts, token, map[string]any{
		util.Fields.Contact.Workspace: workspace,
		util.Fields.Contact.Name:      name,
		util.Fields.Contact.Email:     email,
	})
}

func newRecord(t *testing.T, baseURL, token, user, workspace, key, value string) string {
	t.Helper()
	return extractID(t, baseURL, util.Coll.Records, token, map[string]any{
		util.Fields.Record.Key:       key,
		util.Fields.Record.Value:     value,
		util.Fields.Record.Label:     key,
		util.Fields.Record.Type:      "text",
		util.Fields.Record.Format:    "default",
		util.Fields.Record.User:      user,
		util.Fields.Record.Workspace: workspace,
	})
}

// Sending to a contact who has an account here puts the share in their own
// tray, which is the only path that writes into somebody else's account.
func TestSendToContactLandsInTheirTray(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	sender := newContactParty(t, baseURL)
	recipient := newContactParty(t, baseURL)

	recordID := newRecord(t, baseURL, sender.token, sender.id, sender.workspace,
		"iban", "DE89370400440532013000")
	contactID := newContact(t, baseURL, sender.token, sender.workspace, "Ada", recipient.email)

	sent := grant(t, baseURL, "send", contactID, sender.token, map[string]any{
		"records": []string{recordID},
		"label":   "My bank details",
	}).Expect().Status(http.StatusOK).JSON().Object()
	// Nothing connects these two yet, so the answer says only that the grant
	// exists — TestContactAnswerSaysNothingAboutTheAddress has the why. That
	// the delivery itself happened is what the subtests below check.
	sent.Value("channel").String().IsEqual(util.ContactChannelHandedOver)
	sent.Value("kind").String().IsEqual(util.BookmarkKindShare)
	slug := sent.Value("slug").String().Raw()

	t.Run("the recipient holds a pointer to it", func(t *testing.T) {
		api := api.T(t)
		items := api.List(util.Coll.Bookmarks, recipient.token).Expect().
			Status(http.StatusOK).JSON().Object().Value("items").Array()
		items.Length().IsEqual(1)
		bookmark := items.Value(0).Object()
		bookmark.Value(util.Fields.Bookmark.Slug).String().IsEqual(slug)
		bookmark.Value(util.Fields.Bookmark.Kind).String().IsEqual(util.BookmarkKindShare)
		bookmark.Value(util.Fields.Bookmark.Label).String().IsEqual("My bank details")
		// Empty origin is what says "the server this account lives on".
		bookmark.Value(util.Fields.Bookmark.Origin).String().IsEmpty()
	})

	t.Run("and is told it arrived", func(t *testing.T) {
		api := api.T(t)
		items := api.List(util.Coll.Notifications, recipient.token).Expect().
			Status(http.StatusOK).JSON().Object().Value("items").Array()
		items.Length().IsEqual(1)
		items.Value(0).Object().Value(util.Fields.Notification.Type).
			String().IsEqual(util.NotificationContactShare)
	})

	t.Run("the pointer resolves to the live value", func(t *testing.T) {
		testutils.NewExpect(t, baseURL).GET("/s/" + slug + ".json").
			Expect().Status(http.StatusOK).JSON().Object().
			Value("records").Array().Value(0).Object().
			Value("value").String().IsEqual("DE89370400440532013000")
	})

	t.Run("the sender keeps the side they can revoke", func(t *testing.T) {
		api := api.T(t)
		items := api.List(util.Coll.Links, sender.token).Expect().
			Status(http.StatusOK).JSON().Object().Value("items").Array()
		items.Length().IsEqual(1)
		items.Value(0).Object().Value(util.Fields.Link.Slug).String().IsEqual(slug)
	})

	// The resolution is deliberately not cached on the contact here: the app
	// reads that field as "they are here", so filling it in for an address
	// nobody has confirmed would leave an account-existence oracle sitting on
	// the contact row. It is written once the two are in touch —
	// TestReciprocityEarnsThePreciseAnswer covers that side.
	t.Run("the resolved account is not cached on an unconfirmed contact", func(t *testing.T) {
		api := api.T(t)
		api.Get(util.Coll.Contacts, contactID, sender.token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Contact.User).String().IsEmpty()
	})
}

// A section goes as a unit, so an entry added to it later is shared too —
// the same promise a share made from the vault screen carries.
func TestSendCanHandOverAWholeSection(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	sender := newContactParty(t, baseURL)
	recipient := newContactParty(t, baseURL)

	recordID := newRecord(t, baseURL, sender.token, sender.id, sender.workspace,
		"iban", "DE89370400440532013000")
	sectionID := extractID(t, baseURL, util.Coll.Sections, sender.token, map[string]any{
		util.Fields.Section.Key:       "bank",
		util.Fields.Section.Name:      "Bank details",
		util.Fields.Section.Records:   []string{recordID},
		util.Fields.Section.User:      sender.id,
		util.Fields.Section.Workspace: sender.workspace,
	})
	contactID := newContact(t, baseURL, sender.token, sender.workspace, "Ada", recipient.email)

	sent := grant(t, baseURL, "send", contactID, sender.token, map[string]any{
		"sections": []string{sectionID},
		"label":    "My bank details",
	}).Expect().Status(http.StatusOK).JSON().Object()
	sent.Value("channel").String().IsEqual(util.ContactChannelHandedOver)
	slug := sent.Value("slug").String().Raw()

	api.Get(util.Coll.Links, sent.Value("id").String().Raw(), sender.token).
		Expect().Status(http.StatusOK).JSON().Object().
		Value(util.Fields.Link.Sections).Array().Value(0).String().IsEqual(sectionID)

	// The section arrives as a unit — named, with the entries it holds — which
	// is what makes a later addition to it reach the recipient too.
	section := testutils.NewExpect(t, baseURL).GET("/s/" + slug + ".json").
		Expect().Status(http.StatusOK).JSON().Object().
		Value("sections").Array().Value(0).Object()
	section.Value("name").String().IsEqual("Bank details")
	section.Value("records").Array().Value(0).String().IsEqual(recordID)

	t.Run("a section from another workspace is not there", func(t *testing.T) {
		stranger := newContactParty(t, baseURL)
		strangerContact := newContact(t, baseURL, stranger.token, stranger.workspace,
			"Ada", recipient.email)
		grant(t, baseURL, "send", strangerContact, stranger.token, map[string]any{
			"sections": []string{sectionID},
			"label":    "not mine",
		}).Expect().Status(http.StatusNotFound).
			JSON().Object().Value("code").String().
			IsEqual(util.Errors.RecordNotFound.ErrorCode)
	})
}

// An address with no account here still gets a link; it just has to be passed
// on by hand, because nothing is pushed to another server.
func TestSendToAStrangerMintsWithoutDelivering(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)

	sender := newContactParty(t, baseURL)
	recordID := newRecord(t, baseURL, sender.token, sender.id, sender.workspace,
		"phone", "+49 30 123456")
	contactID := newContact(t, baseURL, sender.token, sender.workspace,
		"Nobody here", "nobody@elsewhere.test")

	sent := grant(t, baseURL, "send", contactID, sender.token, map[string]any{
		"records": []string{recordID},
		"label":   "My number",
	}).Expect().Status(http.StatusOK).JSON().Object()
	sent.Value("delivered").Boolean().IsFalse()
	sent.Value("slug").String().NotEmpty()

	api := testutils.NewPBClient(t, baseURL)
	api.Get(util.Coll.Contacts, contactID, sender.token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Contact.User).String().IsEmpty()
}

// Record ids travel in API responses, so naming one is not the same as being
// allowed to share it.
func TestSendRefusesWhatTheCallerMayNotShare(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)

	owner := newContactParty(t, baseURL)
	stranger := newContactParty(t, baseURL)

	ownerRecord := newRecord(t, baseURL, owner.token, owner.id, owner.workspace,
		"secret", "do-not-leave-this-workspace")
	ownerContact := newContact(t, baseURL, owner.token, owner.workspace, "Ada", owner.email)
	strangerContact := newContact(t, baseURL, stranger.token, stranger.workspace,
		"Ada", owner.email)

	t.Run("an entry from another workspace", func(t *testing.T) {
		grant(t, baseURL, "send", strangerContact, stranger.token, map[string]any{
			"records": []string{ownerRecord},
			"label":   "not mine",
		}).Expect().Status(http.StatusNotFound).
			JSON().Object().Value("code").String().IsEqual(util.Errors.RecordNotFound.ErrorCode)
	})

	t.Run("another workspace's contact is simply not there", func(t *testing.T) {
		grant(t, baseURL, "send", ownerContact, stranger.token, map[string]any{
			"records": []string{ownerRecord},
			"label":   "not mine",
		}).Expect().Status(http.StatusNotFound).
			JSON().Object().Value("code").String().IsEqual(util.Errors.ContactNotFound.ErrorCode)
	})

	t.Run("a send naming nothing", func(t *testing.T) {
		grant(t, baseURL, "send", ownerContact, owner.token, map[string]any{
			"label": "nothing at all",
		}).Expect().Status(http.StatusBadRequest).
			JSON().Object().Value("code").String().
			IsEqual(util.Errors.ContactNothingToSend.ErrorCode)
	})

	t.Run("an unauthenticated send", func(t *testing.T) {
		grant(t, baseURL, "send", ownerContact, "", map[string]any{
			"records": []string{ownerRecord},
			"label":   "whoever",
		}).Expect().Status(http.StatusUnauthorized)
	})
}

// An ask is a request addressed to one person: it arrives as something to
// answer, not as something to read.
func TestAskContactMintsARequestTheyCanAnswer(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	asker := newContactParty(t, baseURL)
	recipient := newContactParty(t, baseURL)

	identityID, _ := newIdentity(t, baseURL, asker.token, "Landlord", asker.id, asker.workspace)
	contactID := newContact(t, baseURL, asker.token, asker.workspace, "Ada", recipient.email)

	asked := grant(t, baseURL, "ask", contactID, asker.token, map[string]any{
		"label":    "Your new address",
		"identity": identityID,
	}).Expect().Status(http.StatusOK).JSON().Object()
	asked.Value("channel").String().IsEqual(util.ContactChannelHandedOver)
	asked.Value("kind").String().IsEqual(util.BookmarkKindRequest)
	slug := asked.Value("slug").String().Raw()
	requestID := asked.Value("id").String().Raw()

	t.Run("it arrives as a request, not a share", func(t *testing.T) {
		api := api.T(t)
		bookmark := api.List(util.Coll.Bookmarks, recipient.token).Expect().
			Status(http.StatusOK).JSON().Object().Value("items").Array().Value(0).Object()
		bookmark.Value(util.Fields.Bookmark.Kind).String().IsEqual(util.BookmarkKindRequest)
		bookmark.Value(util.Fields.Bookmark.Slug).String().IsEqual(slug)

		api.List(util.Coll.Notifications, recipient.token).Expect().Status(http.StatusOK).
			JSON().Object().Value("items").Array().Value(0).Object().
			Value(util.Fields.Notification.Type).String().IsEqual(util.NotificationContactAsk)
	})

	t.Run("one answer closes it, because it was addressed to one person", func(t *testing.T) {
		api := api.T(t)
		api.Get(util.Coll.Requests, requestID, asker.token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Request.MaxResponses).Number().IsEqual(1)
	})

	t.Run("the person asked can answer it", func(t *testing.T) {
		testutils.NewExpect(t, baseURL).
			POST("/api/public/requests/"+slug).
			WithHeader("Authorization", recipient.token).
			WithJSON(map[string]any{
				"data": map[string]any{"address": "1 Mill Lane"},
			}).Expect().Status(http.StatusOK).
			JSON().Object().Value("ok").Boolean().IsTrue()
	})
}

// An ask carries a name the responder is meant to trust, so the identity on it
// must be one the asking workspace actually holds.
func TestAskRefusesANameTheWorkspaceDoesNotHold(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)

	asker := newContactParty(t, baseURL)
	other := newContactParty(t, baseURL)

	foreignIdentity, _ := newIdentity(t, baseURL, other.token, "Town Hall", other.id, other.workspace)
	contactID := newContact(t, baseURL, asker.token, asker.workspace, "Ada", "ada@example.com")

	t.Run("somebody else's identity", func(t *testing.T) {
		grant(t, baseURL, "ask", contactID, asker.token, map[string]any{
			"label":    "Your address",
			"identity": foreignIdentity,
		}).Expect().Status(http.StatusForbidden).
			JSON().Object().Value("code").String().
			IsEqual(util.Errors.IdentityNotOwned.ErrorCode)
	})

	t.Run("no identity at all", func(t *testing.T) {
		grant(t, baseURL, "ask", contactID, asker.token, map[string]any{
			"label": "Your address",
		}).Expect().Status(http.StatusForbidden).
			JSON().Object().Value("code").String().
			IsEqual(util.Errors.IdentityRequired.ErrorCode)
	})

	t.Run("somebody else's form", func(t *testing.T) {
		foreignTemplate := extractID(t, baseURL, util.Coll.Templates, other.token, map[string]any{
			util.Fields.Template.Name:      "Move-in form",
			util.Fields.Template.Workspace: other.workspace,
			util.Fields.Template.Schema:    map[string]any{"fields": []any{}},
		})
		identityID, _ := newIdentity(t, baseURL, asker.token, "Landlord", asker.id, asker.workspace)
		grant(t, baseURL, "ask", contactID, asker.token, map[string]any{
			"label":    "Your address",
			"identity": identityID,
			"template": foreignTemplate,
		}).Expect().Status(http.StatusForbidden).
			JSON().Object().Value("code").String().
			IsEqual(util.Errors.TemplateNotOwned.ErrorCode)
	})
}

// There is no user directory here, so an account id in a contact is an account
// the client could not have discovered — it may only name an address.
func TestContactAccountIsNotTheClientsToName(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	sender := newContactParty(t, baseURL)
	victim := newContactParty(t, baseURL)

	api.Create(util.Coll.Contacts, sender.token, map[string]any{
		util.Fields.Contact.Workspace: sender.workspace,
		util.Fields.Contact.Name:      "Aimed at a stranger",
		util.Fields.Contact.Email:     "someone@example.com",
		util.Fields.Contact.User:      victim.id,
	}).Expect().Status(http.StatusBadRequest)

	contactID := newContact(t, baseURL, sender.token, sender.workspace,
		"Aimed at a stranger", "someone@example.com")
	api.Update(util.Coll.Contacts, contactID, sender.token, map[string]any{
		util.Fields.Contact.User: victim.id,
	}).Expect().Status(http.StatusBadRequest)
}

// Handing a grant over is a vault read on somebody else's behalf, so the
// workspace's audit log has to answer both what was minted and who got it.
func TestHandingAGrantOverIsAudited(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)

	sender := newContactParty(t, baseURL)
	recipient := newContactParty(t, baseURL)

	canary := "iban-canary-" + uuid.New().String()[:8]
	recordID := newRecord(t, baseURL, sender.token, sender.id, sender.workspace,
		"iban", canary)
	contactID := newContact(t, baseURL, sender.token, sender.workspace, "Ada", recipient.email)

	sent := grant(t, baseURL, "send", contactID, sender.token, map[string]any{
		"records": []string{recordID},
		"label":   "My bank details",
	}).Expect().Status(http.StatusOK).JSON().Object()
	linkID := sent.Value("id").String().Raw()
	slug := sent.Value("slug").String().Raw()
	snapshotOf := func(row *core.Record) string {
		return row.GetString(util.Fields.AuditLog.OldData) +
			row.GetString(util.Fields.AuditLog.NewData)
	}

	auditRows := func(collection, recordId string) []*core.Record {
		t.Helper()
		rows, err := app.FindAllRecords(util.Coll.AuditLogs, dbx.HashExp{
			util.Fields.AuditLog.Collection: collection,
			util.Fields.AuditLog.RecordId:   recordId,
		})
		if err != nil {
			t.Fatalf("Failed to read audit logs: %v", err)
		}
		return rows
	}

	t.Run("the share is recorded like any other create", func(t *testing.T) {
		rows := auditRows(util.Coll.Links, linkID)
		if len(rows) != 1 {
			t.Fatalf("audit rows for the minted share = %d, want 1", len(rows))
		}
		row := rows[0]
		if got := row.GetString(util.Fields.AuditLog.Action); got != util.AuditActionCreate {
			t.Errorf("action = %q, want %q", got, util.AuditActionCreate)
		}
		if got := row.GetString(util.Fields.AuditLog.User); got != sender.id {
			t.Errorf("user = %q, want the sender", got)
		}
		if got := row.GetString(util.Fields.AuditLog.Workspace); got != sender.workspace {
			t.Errorf("workspace = %q, want the sender's", got)
		}
		// Their own share's slug is their own capability, recorded in their
		// own log — the opposite of the handover row below.
		if !strings.Contains(snapshotOf(row), slug) {
			t.Error("the share's own row lost its slug")
		}
	})

	t.Run("and the handover says who got it", func(t *testing.T) {
		rows := auditRows(util.Coll.Contacts, contactID)
		var handed *core.Record
		for _, row := range rows {
			if row.GetString(util.Fields.AuditLog.Action) == util.AuditActionSend {
				handed = row
			}
		}
		if handed == nil {
			t.Fatal("expected an audit row for the handover")
		}
		var snapshot map[string]any
		if err := handed.UnmarshalJSONField(util.Fields.AuditLog.NewData, &snapshot); err != nil {
			t.Fatalf("Failed to read the handover snapshot: %v", err)
		}
		if snapshot["grant"] != linkID {
			t.Errorf("grant = %v, want the minted share", snapshot["grant"])
		}
		if snapshot["grantCollection"] != util.Coll.Links {
			t.Errorf("grantCollection = %v, want links", snapshot["grantCollection"])
		}
		if snapshot["recipient"] != recipient.id {
			t.Errorf("recipient = %v, want the account it reached", snapshot["recipient"])
		}
		if snapshot["delivered"] != true {
			t.Errorf("delivered = %v, want true", snapshot["delivered"])
		}
		// The capability is in somebody else's hands now, so it is no more the
		// audit trail's than a bookmarked slug is.
		if strings.Contains(snapshotOf(handed), slug) {
			t.Error("the handover row retained the slug")
		}
	})

	t.Run("an ask is recorded as one", func(t *testing.T) {
		identityID, _ := newIdentity(t, baseURL, sender.token, "Landlord", sender.id, sender.workspace)
		asked := grant(t, baseURL, "ask", contactID, sender.token, map[string]any{
			"label":    "Your new address",
			"identity": identityID,
		}).Expect().Status(http.StatusOK).JSON().Object()
		requestID := asked.Value("id").String().Raw()

		if rows := auditRows(util.Coll.Requests, requestID); len(rows) != 1 {
			t.Fatalf("audit rows for the minted request = %d, want 1", len(rows))
		}
		found := false
		for _, row := range auditRows(util.Coll.Contacts, contactID) {
			if row.GetString(util.Fields.AuditLog.Action) == util.AuditActionAsk {
				found = true
			}
		}
		if !found {
			t.Error("expected an audit row for the ask")
		}
	})

	t.Run("no row in the whole flow retains the value that was shared", func(t *testing.T) {
		rows, err := app.FindAllRecords(util.Coll.AuditLogs, dbx.HashExp{
			util.Fields.AuditLog.Workspace: sender.workspace,
		})
		if err != nil {
			t.Fatalf("Failed to read audit logs: %v", err)
		}
		if len(rows) == 0 {
			t.Fatal("expected audit rows for this workspace")
		}
		for _, row := range rows {
			if strings.Contains(snapshotOf(row), canary) {
				t.Fatalf("audit row %s retained the shared value", row.Id)
			}
		}
	})
}
