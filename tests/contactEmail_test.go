package tests

import (
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/hook"
)

// grantMailbox captures whole messages, not just subjects: what must NOT be in
// a grant email is as much the point as what must.
type grantMailbox struct {
	mu   sync.Mutex
	sent []capturedMail
}

type capturedMail struct {
	to, subject, html, text string
}

func catchGrantMail(t *testing.T, app *pocketbase.PocketBase) *grantMailbox {
	t.Helper()
	box := &grantMailbox{}
	id := app.OnMailerSend().Bind(&hook.Handler[*core.MailerEvent]{
		Func: func(e *core.MailerEvent) error {
			box.mu.Lock()
			defer box.mu.Unlock()
			for _, to := range e.Message.To {
				box.sent = append(box.sent, capturedMail{
					to:      to.Address,
					subject: e.Message.Subject,
					html:    e.Message.HTML,
					text:    e.Message.Text,
				})
			}
			// Not e.Next(): nothing leaves the test machine.
			return nil
		},
	})
	t.Cleanup(func() { app.OnMailerSend().Unbind(id) })
	return box
}

func (b *grantMailbox) to(address string) []capturedMail {
	b.mu.Lock()
	defer b.mu.Unlock()
	var out []capturedMail
	for _, m := range b.sent {
		if strings.EqualFold(m.to, address) {
			out = append(out, m)
		}
	}
	return out
}

// await waits for the outbox worker, which delivers off the request.
func (b *grantMailbox) await(t *testing.T, address string, want int) []capturedMail {
	t.Helper()
	deadline := time.Now().Add(8 * time.Second)
	for {
		if got := b.to(address); len(got) >= want {
			return got
		}
		if time.Now().After(deadline) {
			t.Fatalf("mailed %d of %d expected messages to %s", len(b.to(address)), want, address)
		}
		time.Sleep(50 * time.Millisecond)
	}
}

// quiet gives the worker a moment and asserts nothing was mailed.
func (b *grantMailbox) quiet(t *testing.T, address string) {
	t.Helper()
	time.Sleep(600 * time.Millisecond)
	if got := b.to(address); len(got) > 0 {
		t.Fatalf("mailed %s when it should not have: %q", address, got[0].subject)
	}
}

// mailPolicy sets the operator's recipient policy for one test.
func mailPolicy(t *testing.T, value string) {
	t.Helper()
	setEnvForTest(t, util.GrantEmailRecipientsEnv, value)
}

// The regression that protects every install that upgrades into this feature:
// mail is off until an operator says otherwise.
func TestGrantEmailOffByDefault(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	box := catchGrantMail(t, app)
	setEnvForTest(t, util.GrantEmailRecipientsEnv, "")

	sender := newContactParty(t, baseURL)
	record := newRecord(t, baseURL, sender.token, sender.id, sender.workspace, "iban", "DE89")
	contact := newContact(t, baseURL, sender.token, sender.workspace,
		"Ada", "ada@elsewhere.example")

	sent := grant(t, baseURL, "send", contact, sender.token, map[string]any{
		"records": []string{record},
		"label":   "My bank details",
	}).Expect().Status(http.StatusOK).JSON().Object()
	// The answer does not say whether mail went out — for a contact nobody
	// has confirmed it says only that the grant exists, or it would resolve
	// the address. The mailbox is where "nothing was sent" is checked.
	sent.Value("channel").String().IsEqual(util.ContactChannelHandedOver)
	// The slug still comes back: the sender can always pass it on by hand.
	sent.Value("slug").String().NotEmpty()
	box.quiet(t, "ada@elsewhere.example")
}

func TestSendToEmailOnlyContactMailsTheLink(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	box := catchGrantMail(t, app)
	mailPolicy(t, "all")

	sender := newContactParty(t, baseURL)
	identity, _ := newIdentity(t, baseURL, sender.token, "Ada Lovelace", sender.id, sender.workspace)
	_ = identity
	record := newRecord(t, baseURL, sender.token, sender.id, sender.workspace, "iban", "DE89")
	contact := newContact(t, baseURL, sender.token, sender.workspace,
		"Ada", "ada@elsewhere.example")

	sent := grant(t, baseURL, "send", contact, sender.token, map[string]any{
		"records": []string{record},
		"label":   "My bank details",
	}).Expect().Status(http.StatusOK).JSON().Object()
	sent.Value("channel").String().IsEqual(util.ContactChannelHandedOver)
	slug := sent.Value("slug").String().Raw()

	mail := box.await(t, "ada@elsewhere.example", 1)[0]
	if !strings.Contains(mail.html, "/s/"+slug) {
		t.Error("the email does not carry the share's own link")
	}
	if !strings.Contains(mail.html, "test.invalid") {
		t.Error("the email does not name the server it came from")
	}
	if !strings.Contains(mail.subject, "My bank details") {
		t.Errorf("subject = %q, want it to name the label", mail.subject)
	}
	if !strings.Contains(mail.text, "/s/"+slug) {
		t.Error("the plain-text part does not carry the link")
	}
}

func TestSamedomainPolicyRefusesOutsideDomain(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	box := catchGrantMail(t, app)
	mailPolicy(t, "same-domain")

	sender := newContactParty(t, baseURL)
	record := newRecord(t, baseURL, sender.token, sender.id, sender.workspace, "iban", "DE89")

	outside := newContact(t, baseURL, sender.token, sender.workspace,
		"Outsider", "someone@elsewhere.example")
	grant(t, baseURL, "send", outside, sender.token, map[string]any{
		"records": []string{record},
		"label":   "Not for them",
	}).Expect().Status(http.StatusOK).JSON().Object().
		Value("slug").String().NotEmpty()
	box.quiet(t, "someone@elsewhere.example")

	inside := newContact(t, baseURL, sender.token, sender.workspace,
		"Colleague", "colleague@test.invalid")
	grant(t, baseURL, "send", inside, sender.token, map[string]any{
		"records": []string{record},
		"label":   "For them",
	}).Expect().Status(http.StatusOK).JSON().Object().
		Value("slug").String().NotEmpty()
	box.await(t, "colleague@test.invalid", 1)
}

// An emailed ask has to land somewhere the recipient can finish, and
// answering needs an account.
func TestAskEmailNeedsOpenSignups(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	box := catchGrantMail(t, app)
	mailPolicy(t, "all")

	sender := newContactParty(t, baseURL)
	identity, _ := newIdentity(t, baseURL, sender.token, "Landlord", sender.id, sender.workspace)
	contact := newContact(t, baseURL, sender.token, sender.workspace,
		"Ada", "ada@elsewhere.example")

	setEnvForTest(t, "ALLOW_SIGNUPS", "false")
	grant(t, baseURL, "ask", contact, sender.token, map[string]any{
		"label":    "Your new address",
		"identity": identity,
	}).Expect().Status(http.StatusOK).JSON().Object().
		Value("slug").String().NotEmpty()
	box.quiet(t, "ada@elsewhere.example")

	setEnvForTest(t, "ALLOW_SIGNUPS", "true")
	asked := grant(t, baseURL, "ask", contact, sender.token, map[string]any{
		"label":    "Your new address",
		"identity": identity,
	}).Expect().Status(http.StatusOK).JSON().Object()
	slug := asked.Value("slug").String().Raw()

	mail := box.await(t, "ada@elsewhere.example", 1)[0]
	if !strings.Contains(mail.html, "/passkey?ask="+slug) {
		t.Error("the ask email does not point at the sign-up bridge")
	}
}

// The one cap whose victim is not a user of this server, and the one an
// in-process limiter would have got wrong: the sends come from different
// workspaces and all aim at one inbox.
func TestGrantEmailPerAddressCap(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	box := catchGrantMail(t, app)
	mailPolicy(t, "all")
	setEnvForTest(t, util.GrantEmailsPerHourEnv, "2")

	const victim = "victim@elsewhere.example"
	for i := 0; i < 4; i++ {
		sender := newContactParty(t, baseURL)
		record := newRecord(t, baseURL, sender.token, sender.id, sender.workspace, "k", "v")
		contact := newContact(t, baseURL, sender.token, sender.workspace, "Victim", victim)
		grant(t, baseURL, "send", contact, sender.token, map[string]any{
			"records": []string{record},
			"label":   "Unwanted",
		}).Expect().Status(http.StatusOK)
	}

	time.Sleep(1200 * time.Millisecond)
	if got := len(box.to(victim)); got > 2 {
		t.Errorf("mailed one address %d times with a cap of 2", got)
	}

	// The cap refuses before a row is written, so the outbox does not fill
	// with work that would only be thrown away — and because the count is
	// over those rows, it holds across instances rather than per process.
	var queued int
	if err := app.DB().NewQuery(`
		SELECT COUNT(*) FROM {{grantDeliveries}} WHERE kind = {:k} AND target = {:t}
	`).Bind(dbx.Params{"k": util.DeliveryKindEmail, "t": victim}).Row(&queued); err != nil {
		t.Fatalf("Failed to count outbox rows: %v", err)
	}
	if queued != 2 {
		t.Errorf("outbox rows = %d, want 2: the cap should refuse at enqueue", queued)
	}
}

func TestEmailedDeliveryShowsInTheAuditTrail(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	catchGrantMail(t, app)
	mailPolicy(t, "all")

	sender := newContactParty(t, baseURL)
	record := newRecord(t, baseURL, sender.token, sender.id, sender.workspace, "iban", "DE89")
	const address = "ada@elsewhere.example"
	contact := newContact(t, baseURL, sender.token, sender.workspace, "Ada", address)

	sent := grant(t, baseURL, "send", contact, sender.token, map[string]any{
		"records": []string{record},
		"label":   "My bank details",
	}).Expect().Status(http.StatusOK).JSON().Object()
	slug := sent.Value("slug").String().Raw()

	rows, err := app.FindAllRecords(util.Coll.AuditLogs, dbx.HashExp{
		util.Fields.AuditLog.Collection: util.Coll.Contacts,
		util.Fields.AuditLog.RecordId:   contact,
	})
	if err != nil {
		t.Fatalf("Failed to read audit logs: %v", err)
	}
	var handed *core.Record
	for _, row := range rows {
		if row.GetString(util.Fields.AuditLog.Action) == util.AuditActionSend {
			handed = row
		}
	}
	if handed == nil {
		t.Fatal("expected a handover audit row")
	}
	var snapshot map[string]any
	if err := handed.UnmarshalJSONField(util.Fields.AuditLog.NewData, &snapshot); err != nil {
		t.Fatalf("Failed to read the handover snapshot: %v", err)
	}
	if snapshot["emailed"] != true {
		t.Errorf("emailed = %v, want true", snapshot["emailed"])
	}
	// An audit row is read by people who hold no key.
	blob := handed.GetString(util.Fields.AuditLog.NewData)
	if strings.Contains(blob, address) {
		t.Error("the audit row retained the recipient's address")
	}
	if strings.Contains(blob, slug) {
		t.Error("the audit row retained the slug")
	}
}

func TestServerInfoReportsMailPolicy(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	mailPolicy(t, "same-domain")

	testutils.NewExpect(t, baseURL).GET("/api/server").
		Expect().Status(http.StatusOK).JSON().Object().
		Value("mail").Object().Value("recipients").String().IsEqual("same-domain")
}
