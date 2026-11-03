package tests

import (
	"net/http"
	"strings"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
)

// bookmarkCount is how many pointers this account holds.
func bookmarkCount(t *testing.T, baseURL, token string) int {
	t.Helper()
	return int(testutils.NewPBClient(t, baseURL).List(util.Coll.Bookmarks, token).
		Expect().Status(http.StatusOK).JSON().Object().
		Value("items").Array().Length().Raw())
}

// sendStranger hands a fresh share to one contact and returns the answer.
func sendStranger(t *testing.T, baseURL string, sender contactParty, contactID, label string) *httpexpect.Object {
	t.Helper()
	// A key of its own per send: a vault holds one entry per key, and these
	// tests hand over several in a row. Keys are slugs, so the label is
	// reduced to one.
	key := "iban"
	for _, r := range strings.ToLower(label) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			key += string(r)
		case r == ' ':
			key += "-"
		}
	}
	record := newRecord(t, baseURL, sender.token, sender.id, sender.workspace, key, "DE89")
	return grant(t, baseURL, "send", contactID, sender.token, map[string]any{
		"records": []string{record},
		"label":   label,
	}).Expect().Status(http.StatusOK).JSON().Object()
}

// handedOver asserts the answer says the grant exists and nothing else: the
// shape every unproven sender gets, whatever became of the grant.
func handedOver(t *testing.T, answer *httpexpect.Object) {
	t.Helper()
	answer.Value("ok").Boolean().IsTrue()
	answer.Value("slug").String().NotEmpty()
	answer.Value("channel").String().IsEqual(util.ContactChannelHandedOver)
	answer.Value("delivered").Boolean().IsFalse()
	answer.Value("emailed").Boolean().IsFalse()
}

// The oracle this guards: with a precise answer, anyone could type an address
// and read off whether it has an account on this server — sixty guesses an
// hour, with nothing to show for it on the other side. An address that
// resolves and one that does not must answer identically.
func TestContactAnswerSaysNothingAboutTheAddress(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	sender := newContactParty(t, baseURL)
	resident := newContactParty(t, baseURL)

	here := newContact(t, baseURL, sender.token, sender.workspace, "Ada", resident.email)
	nowhere := newContact(t, baseURL, sender.token, sender.workspace, "Nobody",
		"guessed-"+resident.id+"@elsewhere.example")

	hit := sendStranger(t, baseURL, sender, here, "A guess that landed")
	miss := sendStranger(t, baseURL, sender, nowhere, "A guess that did not")
	handedOver(t, hit)
	handedOver(t, miss)

	t.Run("the delivery still happened", func(t *testing.T) {
		// The reserve is in what the sender is told, not in what the
		// recipient gets: withholding the delivery too would make the
		// feature useless for the first hand-over, which is most of them.
		if got := bookmarkCount(t, baseURL, resident.token); got != 1 {
			t.Errorf("recipient holds %d bookmarks, want 1", got)
		}
	})

	t.Run("and the contact row does not keep the answer either", func(t *testing.T) {
		// The app reads this field as "they are here", so caching the
		// resolution would leave the oracle sitting on the contact.
		api.Get(util.Coll.Contacts, here, sender.token).Expect().
			Status(http.StatusOK).JSON().Object().
			Value(util.Fields.Contact.User).String().IsEmpty()
	})
}

// The cap that bounds a stranger: enough for a first hand-over and a
// correction, far short of a flood, and counted in the database so deleting
// the bookmarks does not buy a fresh allowance.
func TestContactPairCapBoundsUnsolicitedDeliveries(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	setEnvForTest(t, util.ContactPairPerDayEnv, "2")

	sender := newContactParty(t, baseURL)
	victim := newContactParty(t, baseURL)
	contact := newContact(t, baseURL, sender.token, sender.workspace, "Victim", victim.email)

	for _, label := range []string{"first", "second", "third"} {
		// The refusal is not reported either: "you have had your two" is
		// itself an answer about the address.
		handedOver(t, sendStranger(t, baseURL, sender, contact, label))
	}

	if got := bookmarkCount(t, baseURL, victim.token); got != 2 {
		t.Errorf("victim holds %d bookmarks, want the cap of 2", got)
	}

	t.Run("clearing the tray does not refill the budget", func(t *testing.T) {
		items := api.List(util.Coll.Bookmarks, victim.token).Expect().
			Status(http.StatusOK).JSON().Object().Value("items").Array()
		for i := 0; i < int(items.Length().Raw()); i++ {
			id := items.Value(i).Object().Value("id").String().Raw()
			api.Delete(util.Coll.Bookmarks, id, victim.token).Expect().Status(http.StatusNoContent)
		}
		handedOver(t, sendStranger(t, baseURL, sender, contact, "fourth"))
		if got := bookmarkCount(t, baseURL, victim.token); got != 0 {
			t.Errorf("victim holds %d bookmarks after the cap was spent, want 0", got)
		}
	})
}

// Being in touch is what buys the precise answer, and a grant that came the
// other way is one of the three ways to be in touch.
func TestReciprocityEarnsThePreciseAnswer(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)

	first := newContactParty(t, baseURL)
	second := newContactParty(t, baseURL)

	// Nothing connects them yet, so this one is told nothing.
	toSecond := newContact(t, baseURL, first.token, first.workspace, "Second", second.email)
	handedOver(t, sendStranger(t, baseURL, first, toSecond, "Opening move"))

	// Now something has come from the first to the second, so the second
	// sending back is answered in full.
	toFirst := newContact(t, baseURL, second.token, second.workspace, "First", first.email)
	back := sendStranger(t, baseURL, second, toFirst, "The reply")
	back.Value("delivered").Boolean().IsTrue()
	back.Value("channel").String().IsEqual(util.ContactChannelAccount)
}

// A co-member is not a stranger: the workspace already knows who is in it.
func TestCoMemberGetsThePreciseAnswer(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	owner := newContactParty(t, baseURL)
	colleague := newContactParty(t, baseURL)
	api.Create(util.Coll.WorkspaceMembers, owner.token, map[string]any{
		util.Fields.WorkspaceMember.User:      colleague.id,
		util.Fields.WorkspaceMember.Workspace: owner.workspace,
		util.Fields.WorkspaceMember.Role:      util.RoleMember,
	}).Expect().Status(http.StatusOK)

	contact := newContact(t, baseURL, owner.token, owner.workspace, "Colleague", colleague.email)
	answer := sendStranger(t, baseURL, owner, contact, "The quarterly numbers")
	answer.Value("delivered").Boolean().IsTrue()
	answer.Value("channel").String().IsEqual(util.ContactChannelAccount)
}

// "Stop sending me this" has to actually stop it, and hold however long the
// two have been in touch.
func TestBlockedSenderReachesNobody(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	sender := newContactParty(t, baseURL)
	victim := newContactParty(t, baseURL)
	contact := newContact(t, baseURL, sender.token, sender.workspace, "Victim", victim.email)

	// One gets through, which is also what gives the sender standing — a
	// block has to beat that, or it would only work on strangers.
	handedOver(t, sendStranger(t, baseURL, sender, contact, "Before the block"))
	back := newContact(t, baseURL, victim.token, victim.workspace, "Sender", sender.email)
	sendStranger(t, baseURL, victim, back, "A reply, so they are in touch")

	block := extractID(t, baseURL, util.Coll.ContactBlocks, victim.token, map[string]any{
		util.Fields.ContactBlock.User:        victim.id,
		util.Fields.ContactBlock.BlockedUser: sender.id,
	})
	before := bookmarkCount(t, baseURL, victim.token)
	handedOver(t, sendStranger(t, baseURL, sender, contact, "After the block"))
	if got := bookmarkCount(t, baseURL, victim.token); got != before {
		t.Errorf("victim holds %d bookmarks, want the %d from before the block", got, before)
	}

	t.Run("lifting it lets them through again", func(t *testing.T) {
		api.Delete(util.Coll.ContactBlocks, block, victim.token).Expect().Status(http.StatusNoContent)
		sendStranger(t, baseURL, sender, contact, "After the block was lifted")
		if got := bookmarkCount(t, baseURL, victim.token); got != before+1 {
			t.Errorf("victim holds %d bookmarks, want %d", got, before+1)
		}
	})
}

// A whole domain can be refused, for the case the sender just makes another
// account.
func TestBlockedDomainReachesNobody(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)

	sender := newContactParty(t, baseURL)
	victim := newContactParty(t, baseURL)
	contact := newContact(t, baseURL, sender.token, sender.workspace, "Victim", victim.email)

	at := strings.LastIndex(sender.email, "@")
	if at < 0 {
		t.Fatalf("the test account has no address to take a domain from: %q", sender.email)
	}
	domain := strings.ToLower(sender.email[at+1:])
	extractID(t, baseURL, util.Coll.ContactBlocks, victim.token, map[string]any{
		util.Fields.ContactBlock.User:   victim.id,
		util.Fields.ContactBlock.Domain: domain,
	})

	handedOver(t, sendStranger(t, baseURL, sender, contact, "From a blocked domain"))
	if got := bookmarkCount(t, baseURL, victim.token); got != 0 {
		t.Errorf("victim holds %d bookmarks, want 0", got)
	}
}

// A block has to name something, or it quietly refuses nobody.
func TestBlockMustNameSomething(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	victim := newContactParty(t, baseURL)
	api.Create(util.Coll.ContactBlocks, victim.token, map[string]any{
		util.Fields.ContactBlock.User: victim.id,
	}).Expect().Status(http.StatusBadRequest)
}

// The field a block is aimed at must be the server's: a client that could
// write it would be able to pin a delivery on an account that sent none.
func TestBookmarkSenderIsTheServersToWrite(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	sender := newContactParty(t, baseURL)
	recipient := newContactParty(t, baseURL)
	contact := newContact(t, baseURL, sender.token, sender.workspace, "Ada", recipient.email)
	sendStranger(t, baseURL, sender, contact, "Something to block later")

	api.List(util.Coll.Bookmarks, recipient.token).Expect().Status(http.StatusOK).
		JSON().Object().Value("items").Array().Value(0).Object().
		Value(util.Fields.Bookmark.Sender).String().IsEqual(sender.id)

	api.Create(util.Coll.Bookmarks, recipient.token, map[string]any{
		util.Fields.Bookmark.User:   recipient.id,
		util.Fields.Bookmark.Slug:   "aslugofitsown",
		util.Fields.Bookmark.Kind:   util.BookmarkKindShare,
		util.Fields.Bookmark.Sender: sender.id,
	}).Expect().Status(http.StatusBadRequest)
}
