package tests

import (
	"crypto/rand"
	"net/http"
	"slices"
	"strings"
	"testing"

	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
	"github.com/pocketbase/dbx"
)

// The server opens none of this, so random bytes of the right length stand in
// for what a device would make: what is under test is who may put an encrypted
// record on a link, that a link never falls behind the record, and that
// nothing but ciphertext is served (design/e2ee-sharing.md §3).
func sealedEnvelope(t *testing.T, content int) string {
	t.Helper()
	raw := make([]byte, util.SealedEnvelopeOverhead+content)
	if _, err := rand.Read(raw); err != nil {
		t.Fatal(err)
	}
	raw[0] = 1
	return encodeSealed(raw)
}

func (f *sealedFixture) viewerWrap() string {
	return sealedEnvelope(f.t, util.SealedKeyLength+len(f.party.workspace))
}

func (f *sealedFixture) writerWrap() string { return sealedEnvelope(f.t, util.SealedKeyLength) }

func (f *sealedFixture) linkID(slug string) string {
	f.t.Helper()
	link, err := f.app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:s}", dbx.Params{"s": slug})
	if err != nil {
		f.t.Fatal(err)
	}
	return link.Id
}

// ownerKeyWrap is the link's key for its owner's devices.
func (f *sealedFixture) ownerKeyWrap() map[string]any {
	return map[string]any{
		util.SealedAccountScope(f.party.id): map[string]any{"epoch": 1, "wrap": f.writerWrap()},
	}
}

func (f *sealedFixture) putLink(token, linkID string, body map[string]any) *httpexpect.Response {
	f.t.Helper()
	return f.request("PUT", "/api/sealed/links/"+linkID, token, body).Expect()
}

// sealOnLink puts an encrypted record on a link the way the app does, and
// returns the two wraps it sent.
func (f *sealedFixture) sealOnLink(linkID, recordID string, version int) (viewer, writer string) {
	f.t.Helper()
	viewer, writer = f.viewerWrap(), f.writerWrap()
	f.putLink(f.party.token, linkID, map[string]any{
		"seals": []any{map[string]any{
			"record": recordID, "version": version, "viewerWrap": viewer, "writerWrap": writer,
		}},
		"keyWraps": f.ownerKeyWrap(),
	}).Status(http.StatusOK)
	return viewer, writer
}

// newSealedLinkFixture is someone with encryption on, an account key, one
// encrypted record and a link holding one plain record.
func newSealedLinkFixture(t *testing.T) (f *sealedFixture, sealedID, plainID, slug, linkID string) {
	f = newSealedFixture(t)
	f.enroll()
	f.startAccountEpoch(1, "", 1, 2).Status(http.StatusOK)
	sealedID = f.createSealed("smtp_password")
	plainID = newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "visible", "shown")
	slug = f.link(plainID)
	return f, sealedID, plainID, slug, f.linkID(slug)
}

func publicRecords(t *testing.T, baseURL, slug string) (*httpexpect.Array, string) {
	t.Helper()
	resp := testutils.NewPBClient(t, baseURL).E.POST("/api/public/links/" + slug).
		WithJSON(map[string]any{}).Expect().Status(http.StatusOK)
	return resp.JSON().Object().Value("records").Array(), resp.Body().Raw()
}

func sealedEntryOf(records *httpexpect.Array, id string) *httpexpect.Object {
	for _, r := range records.Iter() {
		if r.Object().Value("id").String().Raw() == id {
			return r.Object()
		}
	}
	return nil
}

func TestALinkTakesASealedRecordOnlyWithItsSeal(t *testing.T) {
	f, sealedID, plainID, _, linkID := newSealedLinkFixture(t)
	seal := func(version int, viewer, writer string) map[string]any {
		return map[string]any{"record": sealedID, "version": version, "viewerWrap": viewer, "writerWrap": writer}
	}

	t.Run("the collection API still refuses it", func(t *testing.T) {
		testutils.NewPBClient(t, f.baseURL).Update(util.Coll.Links, linkID, f.party.token, map[string]any{
			util.Fields.Link.Records: []string{plainID, sealedID},
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("and cannot write the link's key", func(t *testing.T) {
		testutils.NewPBClient(t, f.baseURL).Update(util.Coll.Links, linkID, f.party.token, map[string]any{
			util.Fields.Link.SealedKeyWraps: f.ownerKeyWrap(),
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("an empty request is refused", func(t *testing.T) {
		f.putLink(f.party.token, linkID, map[string]any{}).Status(http.StatusBadRequest).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedInvalid.ErrorCode)
	})

	t.Run("a seal without the owner's copy of the key is refused", func(t *testing.T) {
		f.putLink(f.party.token, linkID, map[string]any{
			"seals": []any{seal(1, f.viewerWrap(), f.writerWrap())},
		}).Status(http.StatusBadRequest).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedLinkContent.ErrorCode)
		if services.LinkSeal(f.app, linkID, sealedID) != nil {
			t.Fatal("a refused request left a seal behind")
		}
	})

	t.Run("a seal made for another version is refused", func(t *testing.T) {
		f.putLink(f.party.token, linkID, map[string]any{
			"seals": []any{seal(2, f.viewerWrap(), f.writerWrap())}, "keyWraps": f.ownerKeyWrap(),
		}).Status(http.StatusConflict).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedVersionConflict.ErrorCode)
	})

	t.Run("a wrap of the wrong length is refused", func(t *testing.T) {
		for name, body := range map[string]map[string]any{
			"viewer":   {"seals": []any{seal(1, f.writerWrap(), f.writerWrap())}, "keyWraps": f.ownerKeyWrap()},
			"writer":   {"seals": []any{seal(1, f.viewerWrap(), f.viewerWrap())}, "keyWraps": f.ownerKeyWrap()},
			"stand-in": {"seals": []any{seal(1, sealedKeyWrap, sealedKeyWrap)}, "keyWraps": f.ownerKeyWrap()},
			"link key": {"seals": []any{seal(1, f.viewerWrap(), f.writerWrap())}, "keyWraps": map[string]any{
				util.SealedAccountScope(f.party.id): map[string]any{"epoch": 1, "wrap": f.viewerWrap()},
			}},
		} {
			t.Run(name, func(t *testing.T) {
				f.putLink(f.party.token, linkID, body).Status(http.StatusBadRequest).
					JSON().Object().Value("code").IsEqual(util.Errors.SealedInvalid.ErrorCode)
			})
		}
	})

	t.Run("a key for an epoch the owner does not hold is refused", func(t *testing.T) {
		f.putLink(f.party.token, linkID, map[string]any{
			"seals": []any{seal(1, f.viewerWrap(), f.writerWrap())},
			"keyWraps": map[string]any{
				util.SealedAccountScope(f.party.id): map[string]any{"epoch": 2, "wrap": f.writerWrap()},
			},
		}).Status(http.StatusConflict).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedEpochStale.ErrorCode)
	})

	t.Run("the workspace gets no copy of a private link's key", func(t *testing.T) {
		f.putLink(f.party.token, linkID, map[string]any{
			"seals": []any{seal(1, f.viewerWrap(), f.writerWrap())},
			"keyWraps": map[string]any{
				util.SealedAccountScope(f.party.id): map[string]any{"epoch": 1, "wrap": f.writerWrap()},
				f.party.workspace:                   map[string]any{"epoch": 1, "wrap": f.writerWrap()},
			},
		}).Status(http.StatusBadRequest)
	})

	t.Run("a plain record is no content for a seal", func(t *testing.T) {
		f.putLink(f.party.token, linkID, map[string]any{
			"seals": []any{map[string]any{
				"record": plainID, "version": 0, "viewerWrap": f.viewerWrap(), "writerWrap": f.writerWrap(),
			}},
			"keyWraps": f.ownerKeyWrap(),
		}).Status(http.StatusBadRequest).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedLinkContent.ErrorCode)
	})

	t.Run("with its seal and the key, the record joins the link", func(t *testing.T) {
		body := f.putLink(f.party.token, linkID, map[string]any{
			"seals": []any{seal(1, f.viewerWrap(), f.writerWrap())}, "keyWraps": f.ownerKeyWrap(),
		}).Status(http.StatusOK).JSON().Object()
		body.Value("records").Array().IsEqual([]any{plainID, sealedID})

		state := f.request("GET", "/api/sealed/links/"+linkID, f.party.token, nil).Expect().
			Status(http.StatusOK).JSON().Object()
		state.Value("keyWraps").Object().ContainsKey(util.SealedAccountScope(f.party.id))
		only := state.Value("seals").Array()
		only.Length().IsEqual(1)
		only.Value(0).Object().Value("record").IsEqual(sealedID)
		only.Value(0).Object().Value("current").IsEqual(true)
	})

	t.Run("the link keeps saving through the collection API", func(t *testing.T) {
		testutils.NewPBClient(t, f.baseURL).Update(util.Coll.Links, linkID, f.party.token, map[string]any{
			util.Fields.Link.Label: "renamed",
		}).Expect().Status(http.StatusOK)
		if services.LinkSeal(f.app, linkID, sealedID) == nil {
			t.Fatal("an unrelated save dropped the seal")
		}
	})

	t.Run("none of it answers without a session", func(t *testing.T) {
		f.request("GET", "/api/sealed/links/"+linkID, "", nil).Expect().Status(http.StatusUnauthorized)
		f.putLink("", linkID, map[string]any{"keyWraps": f.ownerKeyWrap()}).Status(http.StatusUnauthorized)
	})
}

func TestASealedRecordIsServedAsCiphertextOnItsLink(t *testing.T) {
	f, sealedID, _, slug, linkID := newSealedLinkFixture(t)
	viewer, writer := f.sealOnLink(linkID, sealedID, 1)
	api := testutils.NewPBClient(t, f.baseURL)

	t.Run("the public read carries the ciphertext and the viewer's wrap", func(t *testing.T) {
		records, raw := publicRecords(t, f.baseURL, slug)
		records.Length().IsEqual(2)
		entry := sealedEntryOf(records, sealedID)
		if entry == nil {
			t.Fatalf("the encrypted record is missing:\n%s", raw)
		}
		entry.Value("sealed").IsEqual(true)
		entry.Value("sealedValue").IsEqual(sealedCiphertext)
		entry.Value("sealedVersion").IsEqual(1)
		entry.Value("viewerWrap").IsEqual(viewer)
		entry.NotContainsKey("value")
		entry.NotContainsKey("unavailable")
		// Nothing a viewer has no use for: the record's own key wrap, the
		// writer's wrap, the link's key, or the workspace's id.
		for name, leak := range map[string]string{
			"the record's key wrap": sealedKeyWrap, "the writer's wrap": writer,
			"the workspace id": f.party.workspace, "the owner's id": f.party.id,
			"a key wrap": "sealedKeyWraps",
		} {
			if strings.Contains(raw, leak) {
				t.Fatalf("the public read carries %s:\n%s", name, raw)
			}
		}
	})

	t.Run("reads made for tools leave it out", func(t *testing.T) {
		for _, suffix := range []string{".json", ".txt", ".csv", ".vcf", ".ics"} {
			body := api.T(t).E.GET("/s/" + slug + suffix).Expect().Status(http.StatusOK).Body().Raw()
			for _, leak := range []string{sealedCiphertext, viewer, writer, "smtp_password"} {
				if strings.Contains(body, leak) {
					t.Fatalf("%s carries %q:\n%s", suffix, leak, body)
				}
			}
		}
		api.T(t).E.GET("/s/"+slug).WithQuery("key", "smtp_password").Expect().Status(http.StatusNotFound)
	})

	t.Run("the page shell carries none of it", func(t *testing.T) {
		body := api.T(t).E.GET("/s/"+slug).WithHeader("Accept", "text/html").
			Expect().Status(http.StatusOK).Body().Raw()
		for _, leak := range []string{sealedCiphertext, viewer, writer} {
			if strings.Contains(body, leak) {
				t.Fatalf("the page carries %q", leak)
			}
		}
	})

	t.Run("a seal that fell behind is named but carries nothing", func(t *testing.T) {
		row := services.LinkSeal(f.app, linkID, sealedID)
		row.Set(util.Fields.LinkSeal.Version, 7)
		if err := f.app.Save(row); err != nil {
			t.Fatal(err)
		}
		records, raw := publicRecords(t, f.baseURL, slug)
		entry := sealedEntryOf(records, sealedID)
		if entry == nil {
			t.Fatalf("the encrypted record is missing:\n%s", raw)
		}
		entry.Value("unavailable").IsEqual(true)
		entry.NotContainsKey("sealedValue")
		entry.NotContainsKey("viewerWrap")
		if strings.Contains(raw, sealedCiphertext) || strings.Contains(raw, viewer) {
			t.Fatalf("a stale seal was served:\n%s", raw)
		}
		f.request("GET", "/api/sealed/links/"+linkID, f.party.token, nil).Expect().
			JSON().Object().Value("seals").Array().Value(0).Object().Value("current").IsEqual(false)
	})
}

func TestASealedWriteRenewsEveryLiveLink(t *testing.T) {
	f, sealedID, plainID, slug, linkID := newSealedLinkFixture(t)
	_, writer := f.sealOnLink(linkID, sealedID, 1)
	api := testutils.NewPBClient(t, f.baseURL)
	version := func() int {
		rec, err := f.app.FindRecordById(util.Coll.Records, sealedID)
		if err != nil {
			t.Fatal(err)
		}
		return rec.GetInt(util.Fields.Record.SealedVersion)
	}
	renewal := func(links ...string) (seals []any, viewer string) {
		viewer = f.viewerWrap()
		for _, id := range links {
			seals = append(seals, map[string]any{"link": id, "expectedWriterWrap": services.LinkSeal(f.app, id, sealedID).GetString(util.Fields.LinkSeal.WriterWrap), "viewerWrap": viewer, "writerWrap": f.writerWrap()})
		}
		return seals, viewer
	}

	t.Run("the writer is told which links to renew", func(t *testing.T) {
		body := f.request("GET", "/api/sealed/records/"+sealedID+"/links", f.party.token, nil).Expect().
			Status(http.StatusOK).JSON().Object()
		body.Value("version").IsEqual(1)
		links := body.Value("links").Array()
		links.Length().IsEqual(1)
		links.Value(0).Object().Value("link").IsEqual(linkID)
		links.Value(0).Object().Value("writerWrap").IsEqual(writer)
	})

	t.Run("a write without them is refused and changes nothing", func(t *testing.T) {
		body := f.request("PUT", "/api/sealed/records/"+sealedID, f.party.token,
			f.put(sealedID, 1, map[string]any{"expectedVersion": 1})).Expect().
			Status(http.StatusConflict).JSON().Object()
		body.Value("code").IsEqual(util.Errors.SealedLinkSealsMissing.ErrorCode)
		body.Value("links").Array().IsEqual([]any{linkID})
		if version() != 1 {
			t.Fatal("a refused write moved the record's version")
		}
	})

	t.Run("a malformed renewal is refused too", func(t *testing.T) {
		f.request("PUT", "/api/sealed/records/"+sealedID, f.party.token,
			f.put(sealedID, 1, map[string]any{"expectedVersion": 1, "linkSeals": []any{
				map[string]any{"link": linkID, "expectedWriterWrap": writer, "viewerWrap": sealedKeyWrap, "writerWrap": sealedKeyWrap},
			}})).Expect().Status(http.StatusBadRequest).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedInvalid.ErrorCode)
		if version() != 1 {
			t.Fatal("a refused write moved the record's version")
		}
	})

	t.Run("with them, record and link move together", func(t *testing.T) {
		seals, viewer := renewal(linkID)
		f.request("PUT", "/api/sealed/records/"+sealedID, f.party.token,
			f.put(sealedID, 1, map[string]any{"expectedVersion": 1, "linkSeals": seals})).Expect().
			Status(http.StatusOK)
		records, _ := publicRecords(t, f.baseURL, slug)
		entry := sealedEntryOf(records, sealedID)
		entry.Value("sealedVersion").IsEqual(2)
		entry.Value("viewerWrap").IsEqual(viewer)
	})

	t.Run("a paused link still has to be renewed", func(t *testing.T) {
		api.Update(util.Coll.Links, linkID, f.party.token, map[string]any{
			util.Fields.Link.Status: util.StatusPaused,
		}).Expect().Status(http.StatusOK)
		f.request("PUT", "/api/sealed/records/"+sealedID, f.party.token,
			f.put(sealedID, 1, map[string]any{"expectedVersion": 2})).Expect().
			Status(http.StatusConflict).JSON().Object().
			Value("code").IsEqual(util.Errors.SealedLinkSealsMissing.ErrorCode)
	})

	t.Run("a second link is one more to renew", func(t *testing.T) {
		second := f.linkID(f.link(plainID))
		f.sealOnLink(second, sealedID, 2)
		body := f.request("PUT", "/api/sealed/records/"+sealedID, f.party.token,
			f.put(sealedID, 1, map[string]any{"expectedVersion": 2, "linkSeals": first(renewal(linkID))})).
			Expect().Status(http.StatusConflict).JSON().Object()
		body.Value("links").Array().IsEqual([]any{second})

		seals, _ := renewal(linkID, second)
		f.request("PUT", "/api/sealed/records/"+sealedID, f.party.token,
			f.put(sealedID, 1, map[string]any{"expectedVersion": 2, "linkSeals": seals})).Expect().
			Status(http.StatusOK)

		// Taken off that link, the record's seal there goes with it.
		api.Update(util.Coll.Links, second, f.party.token, map[string]any{
			util.Fields.Link.Records: []string{plainID},
		}).Expect().Status(http.StatusOK)
		if services.LinkSeal(f.app, second, sealedID) != nil {
			t.Fatal("a record taken off a link left its seal behind")
		}
	})

	t.Run("a revoked link is not waited for, and falls behind", func(t *testing.T) {
		api.Update(util.Coll.Links, linkID, f.party.token, map[string]any{
			util.Fields.Link.Status: util.StatusRevoked,
		}).Expect().Status(http.StatusOK)
		f.request("GET", "/api/sealed/records/"+sealedID+"/links", f.party.token, nil).Expect().
			JSON().Object().Value("links").Array().IsEmpty()
		f.request("PUT", "/api/sealed/records/"+sealedID, f.party.token,
			f.put(sealedID, 1, map[string]any{"expectedVersion": 3})).Expect().Status(http.StatusOK)
		f.request("GET", "/api/sealed/links/"+linkID, f.party.token, nil).Expect().
			JSON().Object().Value("seals").Array().Value(0).Object().Value("current").IsEqual(false)
		// Nothing more goes onto a link that is over.
		f.putLink(f.party.token, linkID, map[string]any{"keyWraps": f.ownerKeyWrap()}).Status(http.StatusGone)
	})
}

func first(seals []any, _ string) []any { return seals }

func TestUnsealingARecordEndsItsSeals(t *testing.T) {
	f, sealedID, _, slug, linkID := newSealedLinkFixture(t)
	f.sealOnLink(linkID, sealedID, 1)

	f.request("POST", "/api/sealed/records/"+sealedID+"/unseal", f.party.token,
		f.unsealBody(sealedID, 1, "now plain")).Expect().Status(http.StatusOK)

	if services.LinkSeal(f.app, linkID, sealedID) != nil {
		t.Fatal("unsealing left the record's seal on its link")
	}
	records, raw := publicRecords(t, f.baseURL, slug)
	entry := sealedEntryOf(records, sealedID)
	if entry == nil {
		t.Fatalf("the record left its link when it stopped being encrypted:\n%s", raw)
	}
	entry.Value("value").IsEqual("now plain")
	entry.NotContainsKey("sealed")
}

// A link keeps its key once its last encrypted entry is gone, so clients read
// sealedEntries to decide whether its address ends in the key.
func TestALinkReportsTheEncryptedEntriesItCarries(t *testing.T) {
	f, sealedID, _, _, linkID := newSealedLinkFixture(t)
	entries := func() float64 {
		return f.request("GET", "/api/collections/"+util.Coll.Links+"/records/"+linkID, f.party.token, nil).
			Expect().Status(http.StatusOK).JSON().Object().Value(util.LinkSealedEntriesField).Number().Raw()
	}
	if n := entries(); n != 0 {
		t.Fatalf("a plain link reported %v encrypted entries", n)
	}
	f.sealOnLink(linkID, sealedID, 1)
	if n := entries(); n != 1 {
		t.Fatalf("a link carrying one encrypted entry reported %v", n)
	}
	f.request("POST", "/api/sealed/records/"+sealedID+"/unseal", f.party.token,
		f.unsealBody(sealedID, 1, "now plain")).Expect().Status(http.StatusOK)
	if n := entries(); n != 0 {
		t.Fatalf("a link whose entry stopped being encrypted reported %v", n)
	}
}

func TestALinksKeyFollowsWhoSeesTheLink(t *testing.T) {
	f, sealedID, _, _, linkID := newSealedLinkFixture(t)
	f.sealOnLink(linkID, sealedID, 1)
	api := testutils.NewPBClient(t, f.baseURL)
	workspaceWrap := map[string]any{f.party.workspace: map[string]any{"epoch": 1, "wrap": f.writerWrap()}}
	held := func() map[string]services.LinkKeyWrap {
		link, err := f.app.FindRecordById(util.Coll.Links, linkID)
		if err != nil {
			t.Fatal(err)
		}
		return services.LinkKeyWraps(link)
	}

	f.putLink(f.party.token, linkID, map[string]any{"keyWraps": workspaceWrap}).Status(http.StatusBadRequest)

	api.Update(util.Coll.Links, linkID, f.party.token, map[string]any{
		util.Fields.Section.AudienceKind: util.AudienceWorkspace,
	}).Expect().Status(http.StatusOK)
	f.putLink(f.party.token, linkID, map[string]any{"keyWraps": workspaceWrap}).Status(http.StatusOK)
	if _, ok := held()[f.party.workspace]; !ok {
		t.Fatal("the workspace's copy of the key was not kept")
	}

	// Narrowed again, the workspace's copy goes; the owner's stays.
	api.Update(util.Coll.Links, linkID, f.party.token, map[string]any{
		util.Fields.Section.AudienceKind: util.AudiencePrivate,
	}).Expect().Status(http.StatusOK)
	wraps := held()
	if _, ok := wraps[f.party.workspace]; ok {
		t.Fatal("a private link kept a copy of its key for the workspace")
	}
	if _, ok := wraps[util.SealedAccountScope(f.party.id)]; !ok {
		t.Fatal("narrowing the link took the owner's copy of its key")
	}
}

func TestLinkSealsKeepMembersApart(t *testing.T) {
	f, member := newGrantFixture(t)
	f.grant(f.party.token, 1, f.grantTo(member, 1, 1), f.grantTo(member, 1, 2)).Status(http.StatusOK)
	f.startAccountEpoch(1, "", 1, 2).Status(http.StatusOK)
	sealedID := f.createSealed("smtp_password")
	plainID := newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "visible", "shown")
	linkID := f.linkID(f.link(plainID))
	_, writer := f.sealOnLink(linkID, sealedID, 1)
	// The member's fixture knows their own workspace; here they act in the
	// owner's, where the membership row put them.
	member.party.workspace = f.party.workspace
	outsider := newContactParty(t, f.baseURL)

	t.Run("a private link is not there for anyone else", func(t *testing.T) {
		for _, token := range []string{member.party.token, outsider.token} {
			f.request("GET", "/api/sealed/links/"+linkID, token, nil).Expect().Status(http.StatusNotFound)
			f.putLink(token, linkID, map[string]any{"keyWraps": f.ownerKeyWrap()}).Status(http.StatusNotFound)
		}
	})

	t.Run("nor are a private record's links", func(t *testing.T) {
		for _, token := range []string{member.party.token, outsider.token} {
			f.request("GET", "/api/sealed/records/"+sealedID+"/links", token, nil).Expect().
				Status(http.StatusNotFound)
		}
	})

	t.Run("a colleague who may write the record renews the owner's private link", func(t *testing.T) {
		row, ok := util.WorkspaceMemberOf(f.app, f.party.workspace, member.party.id)
		if !ok {
			t.Fatal("the member has no membership row")
		}
		scopes, _ := util.ExpandPermissions([]string{util.PermVaultRead, util.PermVaultWrite, util.PermVaultPublish})
		row.Set(util.Fields.WorkspaceMember.Permissions, scopes)
		if err := f.app.Save(row); err != nil {
			t.Fatal(err)
		}
		testutils.NewPBClient(t, f.baseURL).Update(util.Coll.Records, sealedID, f.party.token, map[string]any{
			util.Fields.Section.AudienceKind: util.AudienceWorkspace,
			util.Fields.Section.Editing:      util.EditingAudience,
		}).Expect().Status(http.StatusOK)

		// They learn that the link exists and get the key to its wrap for
		// this record. The link itself stays out of their sight.
		links := f.request("GET", "/api/sealed/records/"+sealedID+"/links", member.party.token, nil).Expect().
			Status(http.StatusOK).JSON().Object().Value("links").Array()
		links.Length().IsEqual(1)
		links.Value(0).Object().Value("link").IsEqual(linkID)
		links.Value(0).Object().Value("writerWrap").IsEqual(writer)
		f.request("GET", "/api/sealed/links/"+linkID, member.party.token, nil).Expect().Status(http.StatusNotFound)

		f.request("PUT", "/api/sealed/records/"+sealedID, member.party.token,
			f.put(sealedID, 1, map[string]any{"expectedVersion": 1})).Expect().
			Status(http.StatusConflict).JSON().Object().
			Value("code").IsEqual(util.Errors.SealedLinkSealsMissing.ErrorCode)

		viewer := f.viewerWrap()
		f.request("PUT", "/api/sealed/records/"+sealedID, member.party.token,
			f.put(sealedID, 1, map[string]any{"expectedVersion": 1, "linkSeals": []any{
				map[string]any{"link": linkID, "expectedWriterWrap": writer, "viewerWrap": viewer, "writerWrap": f.writerWrap()},
			}})).Expect().Status(http.StatusOK)
		row2 := services.LinkSeal(f.app, linkID, sealedID)
		if row2 == nil || row2.GetInt(util.Fields.LinkSeal.Version) != 2 ||
			row2.GetString(util.Fields.LinkSeal.ViewerWrap) != viewer {
			t.Fatal("the colleague's write did not renew the owner's link")
		}
	})
}

func TestEncryptingARecordCarriesLinksAtomically(t *testing.T) {
	f, _, plain, slug, link := newSealedLinkFixture(t)
	keyWraps := f.ownerKeyWrap()
	carry := map[string]any{"link": link, "viewerWrap": f.viewerWrap(), "writerWrap": f.writerWrap(),
		"keyWraps": keyWraps, "expectedKeyWraps": map[string]any{}}
	body := func(seals []any, drop bool) map[string]any {
		return f.put(plain, 1, map[string]any{"expectedVersion": 0, "carryLinks": true, "dropLinks": drop, "linkSeals": seals})
	}
	// A second link added after preparation must be explicitly dropped.
	otherSlug := f.link(plain)
	other := f.linkID(otherSlug)
	f.request("PUT", "/api/sealed/records/"+plain, f.party.token, body([]any{carry}, false)).Expect().Status(http.StatusConflict)
	if services.LinkSeal(f.app, link, plain) != nil {
		t.Fatal("refused encryption left a seal behind")
	}
	rec, _ := f.app.FindRecordById(util.Coll.Records, plain)
	if services.IsSealed(rec) || rec.GetString(util.Fields.Record.Value) != "shown" {
		t.Fatal("refused encryption changed the value")
	}
	bad := map[string]any{"link": other, "viewerWrap": f.viewerWrap(), "writerWrap": f.writerWrap(),
		"expectedKeyWraps": map[string]any{}, "keyWraps": map[string]any{"wrong-scope": map[string]any{"epoch": 1, "wrap": f.writerWrap()}}}
	f.request("PUT", "/api/sealed/records/"+plain, f.party.token, body([]any{carry, bad}, false)).Expect().Status(http.StatusBadRequest)
	if services.LinkSeal(f.app, link, plain) != nil {
		t.Fatal("later link failure left an earlier link's seal committed")
	}
	unchanged, _ := f.app.FindRecordById(util.Coll.Links, link)
	if len(services.LinkKeyWraps(unchanged)) != 0 {
		t.Fatal("later link failure left an address key committed")
	}
	f.request("PUT", "/api/sealed/records/"+plain, f.party.token, body([]any{carry}, true)).Expect().Status(http.StatusOK)
	rec, _ = f.app.FindRecordById(util.Coll.Records, plain)
	if services.CurrentLinkSeal(f.app, link, rec) == nil {
		t.Fatal("carried link has no current seal")
	}
	kept, _ := f.app.FindRecordById(util.Coll.Links, link)
	dropped, _ := f.app.FindRecordById(util.Coll.Links, other)
	if !slices.Contains(kept.GetStringSlice(util.Fields.Link.Records), plain) || slices.Contains(dropped.GetStringSlice(util.Fields.Link.Records), plain) {
		t.Fatal("encryption did not preserve exactly the carried link")
	}
	entries, _ := publicRecords(t, f.baseURL, slug)
	sealedEntryOf(entries, plain).Value("viewerWrap").IsEqual(carry["viewerWrap"])
}

func TestReplacingLinkKeyIsCompleteAndRejectsStaleWriters(t *testing.T) {
	f, record, _, _, link := newSealedLinkFixture(t)
	_, oldWriter := f.sealOnLink(link, record, 1)
	before, _ := f.app.FindRecordById(util.Coll.Links, link)
	old := services.LinkKeyWraps(before)
	nextViewer, nextWriter := f.viewerWrap(), f.writerWrap()
	replacement := map[string]any{"replaceKey": true, "expectedKeyWraps": old, "keyWraps": f.ownerKeyWrap()}
	// Partial replacement changes nothing.
	f.putLink(f.party.token, link, replacement).Status(http.StatusConflict)
	replacement["seals"] = []any{map[string]any{"record": record, "version": 1, "viewerWrap": nextViewer, "writerWrap": nextWriter}}
	f.putLink(f.party.token, link, replacement).Status(http.StatusOK)
	// A second device replacing from its earlier state cannot undo this one.
	f.putLink(f.party.token, link, replacement).Status(http.StatusConflict)
	// Nor can a record write prepared with the earlier writer wrap.
	stale := []any{map[string]any{"link": link, "expectedWriterWrap": oldWriter, "viewerWrap": f.viewerWrap(), "writerWrap": f.writerWrap()}}
	f.request("PUT", "/api/sealed/records/"+record, f.party.token,
		f.put(record, 1, map[string]any{"expectedVersion": 1, "linkSeals": stale})).Expect().Status(http.StatusConflict)
	if services.LinkSeal(f.app, link, record).GetString(util.Fields.LinkSeal.WriterWrap) != nextWriter {
		t.Fatal("stale writer undid a replacement")
	}
	stale[0].(map[string]any)["expectedWriterWrap"] = nextWriter
	f.request("PUT", "/api/sealed/records/"+record, f.party.token,
		f.put(record, 1, map[string]any{"expectedVersion": 1, "linkSeals": stale})).Expect().Status(http.StatusOK)
}

func TestPlainRecordLinkDiscoveryDoesNotRevealPrivateLinks(t *testing.T) {
	f, member := newGrantFixture(t)
	f.grant(f.party.token, 1, f.grantTo(member, 1, 1), f.grantTo(member, 1, 2)).Status(http.StatusOK)
	member.party.workspace = f.party.workspace
	row, _ := util.WorkspaceMemberOf(f.app, f.party.workspace, member.party.id)
	scopes, _ := util.ExpandPermissions([]string{util.PermVaultRead, util.PermVaultWrite, util.PermVaultPublish})
	row.Set(util.Fields.WorkspaceMember.Permissions, scopes)
	if err := f.app.Save(row); err != nil {
		t.Fatal(err)
	}
	record := newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "published", "shown")
	testutils.NewPBClient(t, f.baseURL).Update(util.Coll.Records, record, f.party.token, map[string]any{
		util.Fields.Section.AudienceKind: util.AudienceWorkspace, util.Fields.Section.Editing: util.EditingAudience,
	}).Expect().Status(http.StatusOK)
	private := f.linkID(f.link(record))
	f.request("GET", "/api/sealed/records/"+record+"/links", member.party.token, nil).Expect().Status(http.StatusOK).
		JSON().Object().Value("links").Array().IsEmpty()
	// With explicit confirmation the colleague's link loses the record, and
	// its owner learns why without any decrypted content in the notification.
	f.request("PUT", "/api/sealed/records/"+record, member.party.token,
		f.put(record, 1, map[string]any{"expectedVersion": 0, "carryLinks": true, "dropLinks": true})).Expect().Status(http.StatusOK)
	note, err := f.app.FindFirstRecordByFilter(util.Coll.Notifications, "type = {:t} && refId = {:r}", dbx.Params{"t": util.NotificationSealedLinkChanged, "r": private})
	if err != nil || note.GetString(util.Fields.Notification.User) != f.party.id {
		t.Fatalf("missing notification to link owner: %v", err)
	}
}

func TestEncryptingAnEntrySharedThroughASectionKeepsItReadable(t *testing.T) {
	f, _, plain, slug, linkID := newSealedLinkFixture(t)
	section := extractID(t, f.baseURL, util.Coll.Sections, f.party.token, map[string]any{
		"key": "section", "name": "Section", "records": []string{plain}, "user": f.party.id, "workspace": f.party.workspace,
	})
	testutils.NewPBClient(t, f.baseURL).Update(util.Coll.Links, linkID, f.party.token,
		map[string]any{"records": []string{}, "sections": []string{section}}).Expect().Status(http.StatusOK)
	f.request("GET", "/api/sealed/records/"+plain+"/links", f.party.token, nil).Expect().Status(http.StatusOK).
		JSON().Object().Value("links").Array().Length().IsEqual(1)
	viewer := f.viewerWrap()
	f.request("PUT", "/api/sealed/records/"+plain, f.party.token,
		f.put(plain, 1, map[string]any{"expectedVersion": 0, "carryLinks": true, "linkSeals": []any{
			map[string]any{"link": linkID, "viewerWrap": viewer, "writerWrap": f.writerWrap(),
				"expectedKeyWraps": map[string]any{}, "keyWraps": f.ownerKeyWrap()},
		}})).Expect().Status(http.StatusOK)
	link, _ := f.app.FindRecordById(util.Coll.Links, linkID)
	if !slices.Contains(link.GetStringSlice(util.Fields.Link.Records), plain) {
		t.Fatal("section entry was not explicitly carried")
	}
	entries, _ := publicRecords(t, f.baseURL, slug)
	sealedEntryOf(entries, plain).Value("viewerWrap").IsEqual(viewer)
}
