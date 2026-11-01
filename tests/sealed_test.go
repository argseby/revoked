package tests

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
	"github.com/google/uuid"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
)

// The server treats sealed data as opaque, so these stand-ins are enough: what
// is under test is who may write what, and that nothing serves it. The canary
// is what a leak would look like, were a plaintext ever to reach these paths.
const (
	sealedCiphertext = "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA"
	sealedKeyWrap    = "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0"
	sealedPublicKey  = "BAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
	sealedSignature  = "c2lnbmF0dXJlLXN0YW5kLWlu"
	plainCanary      = "plain-canary-value-7f3a"
)

type sealedFixture struct {
	t       *testing.T
	baseURL string
	app     *pocketbase.PocketBase
	party   contactParty
}

func newSealedFixture(t *testing.T) *sealedFixture {
	t.Helper()
	baseURL, app := testutils.SetupTestApp(t)
	return &sealedFixture{t: t, baseURL: baseURL, app: app, party: newContactParty(t, baseURL)}
}

func (f *sealedFixture) request(method, path, token string, body any) *httpexpect.Request {
	req := testutils.NewExpect(f.t, f.baseURL).Request(method, path)
	if token != "" {
		req = req.WithHeader("Authorization", token)
	}
	if body != nil {
		req = req.WithJSON(body)
	}
	return req
}

func deviceEntry(seq, signer int) map[string]any {
	return map[string]any{
		"seq":              seq,
		"action":           "add",
		"kind":             "device",
		"label":            fmt.Sprintf("device %d", seq),
		"hpkePublicKey":    sealedPublicKey,
		"signingPublicKey": sealedPublicKey,
		"previousHash":     "",
		"signerSeq":        signer,
		"signature":        sealedSignature,
	}
}

// enroll adds a device and a recovery entry, and starts the workspace's key.
func (f *sealedFixture) enroll() {
	f.t.Helper()
	recovery := deviceEntry(2, 1)
	recovery["kind"] = "recovery"
	f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
		"entries": []any{deviceEntry(1, 1), recovery},
	}).Expect().Status(http.StatusOK)
	f.startEpoch(1, "", 1, 2)
}

func (f *sealedFixture) startEpoch(epoch int, prior string, devices ...int) *httpexpect.Response {
	f.t.Helper()
	wraps := []any{}
	for _, seq := range devices {
		wraps = append(wraps, map[string]any{
			"deviceSeq": seq, "wrap": sealedKeyWrap, "signerSeq": 1, "chainSeq": 2, "signature": sealedSignature,
		})
	}
	return f.request("POST", "/api/sealed/workspaces/"+f.party.workspace+"/epochs", f.party.token,
		map[string]any{"epoch": epoch, "priorWrap": prior, "wraps": wraps}).Expect()
}

func sealedBody(epoch int, extra map[string]any) map[string]any {
	body := map[string]any{"sealedValue": sealedCiphertext, "keyEpoch": epoch, "keyWrap": sealedKeyWrap}
	for k, v := range extra {
		body[k] = v
	}
	return body
}

func newSealedID() string {
	return strings.ReplaceAll(uuid.New().String(), "-", "")[:15]
}

// createSealed makes a sealed record and returns its id.
func (f *sealedFixture) createSealed(key string) string {
	f.t.Helper()
	id := newSealedID()
	f.request("POST", "/api/sealed/records", f.party.token, sealedBody(1, map[string]any{
		"id": id, "key": key, "label": key, "type": "text", "format": "default",
		"workspace": f.party.workspace,
	})).Expect().Status(http.StatusOK).JSON().Object().Value("sealed").IsEqual(true)
	return id
}

func (f *sealedFixture) link(records ...string) string {
	f.t.Helper()
	slug := "sealed-" + uuid.New().String()[:8]
	extractID(f.t, f.baseURL, util.Coll.Links, f.party.token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "test",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      f.party.id,
		util.Fields.Link.Workspace: f.party.workspace,
		util.Fields.Link.Records:   records,
	})
	return slug
}

func TestCollectionAPICannotTouchSealedFields(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	api := testutils.NewPBClient(t, f.baseURL)

	base := map[string]any{
		util.Fields.Record.Key:       "smuggled",
		util.Fields.Record.Value:     "x",
		util.Fields.Record.Label:     "smuggled",
		util.Fields.Record.Type:      util.TypeText,
		util.Fields.Record.Format:    util.FormatDefault,
		util.Fields.Record.User:      f.party.id,
		util.Fields.Record.Workspace: f.party.workspace,
	}

	t.Run("create refuses each sealed field", func(t *testing.T) {
		for field, value := range map[string]any{
			util.Fields.Record.Sealed:        true,
			util.Fields.Record.SealedValue:   sealedCiphertext,
			util.Fields.Record.SealedVersion: 3,
			util.Fields.Record.KeyEpoch:      1,
			util.Fields.Record.KeyWrap:       sealedKeyWrap,
		} {
			body := map[string]any{}
			for k, v := range base {
				body[k] = v
			}
			body[field] = value
			api.T(t).Create(util.Coll.Records, f.party.token, body).
				Expect().Status(http.StatusBadRequest)
		}
	})

	sealedID := f.createSealed("smtp_password")

	t.Run("an old app cannot write plaintext into a sealed record", func(t *testing.T) {
		api.T(t).Update(util.Coll.Records, sealedID, f.party.token, map[string]any{
			util.Fields.Record.Value: plainCanary,
		}).Expect().Status(http.StatusBadRequest)
		assertStoredValueEmpty(t, f.app, sealedID)
	})

	t.Run("nor unseal or replace it", func(t *testing.T) {
		for field, value := range map[string]any{
			util.Fields.Record.Sealed:      false,
			util.Fields.Record.SealedValue: "AAAA",
			util.Fields.Record.KeyWrap:     "AAAA",
			util.Fields.Record.KeyEpoch:    9,
		} {
			api.T(t).Update(util.Coll.Records, sealedID, f.party.token, map[string]any{field: value}).
				Expect().Status(http.StatusBadRequest)
		}
	})

	t.Run("a plain record cannot be marked sealed", func(t *testing.T) {
		plain := newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "plain", "v")
		api.T(t).Update(util.Coll.Records, plain, f.party.token, map[string]any{
			util.Fields.Record.Sealed: true,
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("metadata still edits", func(t *testing.T) {
		api.T(t).Update(util.Coll.Records, sealedID, f.party.token, map[string]any{
			util.Fields.Record.Label: "SMTP password",
		}).Expect().Status(http.StatusOK).JSON().Object().Value("label").IsEqual("SMTP password")
	})

	t.Run("a sealed record cannot be aliased", func(t *testing.T) {
		body := map[string]any{}
		for k, v := range base {
			body[k] = v
		}
		body[util.Fields.Record.Key] = "alias_of_sealed"
		body[util.Fields.Record.Value] = ""
		body[util.Fields.Record.AliasOf] = sealedID
		api.T(t).Create(util.Coll.Records, f.party.token, body).
			Expect().Status(http.StatusBadRequest)
	})
}

func assertStoredValueEmpty(t *testing.T, app *pocketbase.PocketBase, id string) {
	t.Helper()
	rec, err := app.FindRecordById(util.Coll.Records, id)
	if err != nil {
		t.Fatal(err)
	}
	if v := rec.GetString(util.Fields.Record.Value); v != "" {
		t.Fatalf("a sealed record holds a plain value: %q", v)
	}
}

// Every path that reads a record's value must behave as though a sealed record
// were not there: no plaintext, and no ciphertext passed off as a value.
func TestSealedRecordsDropFromEveryRead(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	api := testutils.NewPBClient(t, f.baseURL)

	plain := newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "visible", "shown")
	target := newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "smtp_password", plainCanary)
	slug := f.link(plain, target)

	f.request("PUT", "/api/sealed/records/"+target, f.party.token, sealedBody(1, map[string]any{
		"expectedVersion": 0, "dropLinks": true,
	})).Expect().Status(http.StatusOK)
	assertStoredValueEmpty(t, f.app, target)

	assertClean := func(t *testing.T, body string) {
		t.Helper()
		for _, leak := range []string{plainCanary, sealedCiphertext, sealedKeyWrap, "smtp_password"} {
			if strings.Contains(body, leak) {
				t.Fatalf("response carries %q:\n%s", leak, body)
			}
		}
	}

	t.Run("public resolve", func(t *testing.T) {
		resp := api.T(t).E.POST("/api/public/links/" + slug).WithJSON(map[string]any{}).
			Expect().Status(http.StatusOK)
		assertClean(t, resp.Body().Raw())
		resp.JSON().Object().Value("records").Array().Length().IsEqual(1)
	})

	for _, suffix := range []string{"", ".json", ".txt", ".csv", ".vcf", ".ics"} {
		t.Run("short link "+suffix, func(t *testing.T) {
			resp := api.T(t).E.GET("/s/" + slug + suffix).Expect().Status(http.StatusOK)
			assertClean(t, resp.Body().Raw())
		})
	}

	t.Run("short link by key", func(t *testing.T) {
		api.T(t).E.GET("/s/"+slug).WithQuery("key", "smtp_password").
			Expect().Status(http.StatusNotFound)
	})

	t.Run("browser page", func(t *testing.T) {
		resp := api.T(t).E.GET("/s/"+slug).WithHeader("Accept", "text/html").
			Expect().Status(http.StatusOK)
		assertClean(t, resp.Body().Raw())
	})

	t.Run("audit log keeps no ciphertext", func(t *testing.T) {
		rows, err := f.app.FindRecordsByFilter(util.Coll.AuditLogs,
			util.Fields.AuditLog.RecordId+" = {:id}", "", 0, 0, dbx.Params{"id": target})
		if err != nil || len(rows) == 0 {
			t.Fatalf("no audit rows for the sealing: %v", err)
		}
		for _, row := range rows {
			raw, _ := json.Marshal(row)
			if strings.Contains(string(raw), sealedCiphertext) ||
				strings.Contains(string(raw), sealedKeyWrap) ||
				strings.Contains(string(raw), plainCanary) {
				t.Fatalf("audit row retained sealed material: %s", raw)
			}
		}
	})
}

func TestSealedRecordsCannotBeShared(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	sealedID := f.createSealed("smtp_password")

	t.Run("a new link refuses it", func(t *testing.T) {
		testutils.NewPBClient(t, f.baseURL).Create(util.Coll.Links, f.party.token, map[string]any{
			util.Fields.Link.Slug:      "sealed-" + uuid.New().String()[:8],
			util.Fields.Link.Label:     "test",
			util.Fields.Link.Status:    util.StatusActive,
			util.Fields.Link.User:      f.party.id,
			util.Fields.Link.Workspace: f.party.workspace,
			util.Fields.Link.Records:   []string{sealedID},
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("adding it to a link refuses too", func(t *testing.T) {
		plain := newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "visible", "shown")
		slug := f.link(plain)
		link, err := f.app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:s}", dbx.Params{"s": slug})
		if err != nil {
			t.Fatal(err)
		}
		testutils.NewPBClient(t, f.baseURL).Update(util.Coll.Links, link.Id, f.party.token, map[string]any{
			util.Fields.Link.Records: []string{plain, sealedID},
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("sending to a contact refuses it", func(t *testing.T) {
		contactID := newContact(t, f.baseURL, f.party.token, f.party.workspace, "Ada", "ada@example.com")
		grant(t, f.baseURL, "send", contactID, f.party.token, map[string]any{
			"records": []string{sealedID}, "label": "x",
		}).Expect().Status(http.StatusBadRequest).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedRecordUnsupported.ErrorCode)
	})

	t.Run("an existing link keeps saving after a record on it is sealed", func(t *testing.T) {
		target := newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "later", "v")
		slug := f.link(target)
		f.request("PUT", "/api/sealed/records/"+target, f.party.token, sealedBody(1, map[string]any{
			"expectedVersion": 0, "dropLinks": true,
		})).Expect().Status(http.StatusOK)
		link, err := f.app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:s}", dbx.Params{"s": slug})
		if err != nil {
			t.Fatal(err)
		}
		testutils.NewPBClient(t, f.baseURL).Update(util.Coll.Links, link.Id, f.party.token, map[string]any{
			util.Fields.Link.Status: util.StatusPaused,
		}).Expect().Status(http.StatusOK)
	})
}

func TestSealingWarnsAboutLiveLinks(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	target := newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "shared", "v")
	f.link(target)

	sectionID := extractID(t, f.baseURL, util.Coll.Sections, f.party.token, map[string]any{
		util.Fields.Section.Key:       "group",
		util.Fields.Section.Name:      "Group",
		util.Fields.Section.User:      f.party.id,
		util.Fields.Section.Workspace: f.party.workspace,
		util.Fields.Section.Records:   []string{target},
	})
	extractID(t, f.baseURL, util.Coll.Links, f.party.token, map[string]any{
		util.Fields.Link.Slug:      "sealed-" + uuid.New().String()[:8],
		util.Fields.Link.Label:     "section",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      f.party.id,
		util.Fields.Link.Workspace: f.party.workspace,
		util.Fields.Link.Sections:  []string{sectionID},
	})

	body := f.request("PUT", "/api/sealed/records/"+target, f.party.token, sealedBody(1, map[string]any{
		"expectedVersion": 0,
	})).Expect().Status(http.StatusConflict).JSON().Object()
	body.Value("code").IsEqual(util.Errors.SealedLinksAffected.ErrorCode)
	body.Value("links").IsEqual(2)

	rec, _ := f.app.FindRecordById(util.Coll.Records, target)
	if rec.GetBool(util.Fields.Record.Sealed) || rec.GetString(util.Fields.Record.Value) != "v" {
		t.Fatal("a refused sealing changed the record")
	}

	f.request("PUT", "/api/sealed/records/"+target, f.party.token, sealedBody(1, map[string]any{
		"expectedVersion": 0, "dropLinks": true,
	})).Expect().Status(http.StatusOK)
}

func TestSealedWritesMoveOneVersionAtATime(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	id := f.createSealed("smtp_password")

	t.Run("a stale version is refused", func(t *testing.T) {
		f.request("PUT", "/api/sealed/records/"+id, f.party.token, sealedBody(1, map[string]any{
			"expectedVersion": 5,
		})).Expect().Status(http.StatusConflict).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedVersionConflict.ErrorCode)
	})

	t.Run("sealing what is already sealed is refused", func(t *testing.T) {
		f.request("PUT", "/api/sealed/records/"+id, f.party.token, sealedBody(1, map[string]any{
			"expectedVersion": 0,
		})).Expect().Status(http.StatusConflict)
	})

	t.Run("of concurrent writers exactly one wins", func(t *testing.T) {
		var wg sync.WaitGroup
		results := make([]int, 8)
		for i := range results {
			wg.Add(1)
			go func() {
				defer wg.Done()
				results[i] = f.request("PUT", "/api/sealed/records/"+id, f.party.token,
					sealedBody(1, map[string]any{"expectedVersion": 1})).Expect().Raw().StatusCode
			}()
		}
		wg.Wait()
		wins := 0
		for _, status := range results {
			if status == http.StatusOK {
				wins++
			} else if status != http.StatusConflict {
				t.Errorf("unexpected status %d", status)
			}
		}
		if wins != 1 {
			t.Fatalf("%d concurrent writers won", wins)
		}
		rec, _ := f.app.FindRecordById(util.Coll.Records, id)
		if v := rec.GetInt(util.Fields.Record.SealedVersion); v != 2 {
			t.Fatalf("version is %d", v)
		}
	})
}

func TestSealedKeyEpochs(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	id := f.createSealed("smtp_password")

	remove := func(target, seq int) {
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{map[string]any{
				"seq": seq, "action": "remove", "targetSeq": target, "signerSeq": 1, "signature": sealedSignature,
			}},
		}).Expect().Status(http.StatusOK)
	}

	t.Run("a new epoch must reach every live device", func(t *testing.T) {
		f.startEpoch(2, sealedKeyWrap, 1).Status(http.StatusBadRequest)
	})

	t.Run("a new epoch needs the old key wrapped under it", func(t *testing.T) {
		f.startEpoch(2, "", 1, 2).Status(http.StatusBadRequest)
	})

	t.Run("epochs cannot be skipped", func(t *testing.T) {
		f.startEpoch(5, sealedKeyWrap, 1, 2).Status(http.StatusConflict)
	})

	t.Run("a write under an old epoch is refused", func(t *testing.T) {
		f.startEpoch(2, sealedKeyWrap, 1, 2).Status(http.StatusOK)
		f.request("PUT", "/api/sealed/records/"+id, f.party.token, sealedBody(1, map[string]any{
			"expectedVersion": 1,
		})).Expect().Status(http.StatusConflict).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedEpochStale.ErrorCode)
	})

	t.Run("removing a device withdraws its key and blocks writes until rotation", func(t *testing.T) {
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{deviceEntry(3, 1)},
			"wraps": []any{map[string]any{
				"workspace": f.party.workspace, "epoch": 2, "deviceSeq": 3,
				"wrap": sealedKeyWrap, "signerSeq": 1, "chainSeq": 2, "signature": sealedSignature,
			}},
		}).Expect().Status(http.StatusOK)

		remove(3, 4)

		w := util.Fields.WorkspaceKeyWrap
		rows, _ := f.app.FindRecordsByFilter(util.Coll.WorkspaceKeyWraps,
			w.User+" = {:u} && "+w.DeviceSeq+" = 3", "", 0, 0, dbx.Params{"u": f.party.id})
		if len(rows) != 0 {
			t.Fatal("the removed device kept its key")
		}

		f.request("PUT", "/api/sealed/records/"+id, f.party.token, sealedBody(2, map[string]any{
			"expectedVersion": 1,
		})).Expect().Status(http.StatusConflict).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedEpochStale.ErrorCode)

		f.startEpoch(3, sealedKeyWrap, 1, 2).Status(http.StatusOK)
		f.request("PUT", "/api/sealed/records/"+id, f.party.token, sealedBody(3, map[string]any{
			"expectedVersion": 1,
		})).Expect().Status(http.StatusOK)
	})

	t.Run("a key cannot be handed to a removed device", func(t *testing.T) {
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{deviceEntry(5, 1)},
			"wraps": []any{map[string]any{
				"workspace": f.party.workspace, "epoch": 3, "deviceSeq": 3,
				"wrap": sealedKeyWrap, "signerSeq": 1, "chainSeq": 2, "signature": sealedSignature,
			}},
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("the list cannot skip or rewrite entries", func(t *testing.T) {
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{deviceEntry(99, 1)},
		}).Expect().Status(http.StatusConflict)
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{deviceEntry(1, 1)},
		}).Expect().Status(http.StatusConflict)
	})
}

func TestSealedRoutesKeepPeopleApart(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	id := f.createSealed("smtp_password")
	stranger := newContactParty(t, f.baseURL)

	t.Run("anonymous callers get nothing", func(t *testing.T) {
		f.request("GET", "/api/sealed/state", "", nil).Expect().Status(http.StatusUnauthorized)
		f.request("PUT", "/api/sealed/records/"+id, "", sealedBody(1, map[string]any{"expectedVersion": 1})).
			Expect().Status(http.StatusUnauthorized)
	})

	t.Run("state shows only the caller's own", func(t *testing.T) {
		body := f.request("GET", "/api/sealed/state", stranger.token, nil).
			Expect().Status(http.StatusOK).JSON().Object()
		body.Value("devices").Array().IsEmpty()
		body.Value("workspaces").Array().IsEmpty()
	})

	t.Run("a stranger cannot write the record", func(t *testing.T) {
		f.request("PUT", "/api/sealed/records/"+id, stranger.token, sealedBody(1, map[string]any{
			"expectedVersion": 1,
		})).Expect().Status(http.StatusNotFound)
		f.request("POST", "/api/sealed/records/"+id+"/unseal", stranger.token, map[string]any{
			"expectedVersion": 1, "value": "x",
		}).Expect().Status(http.StatusNotFound)
	})

	t.Run("a stranger cannot start an epoch in the workspace", func(t *testing.T) {
		f.request("POST", "/api/sealed/workspaces/"+f.party.workspace+"/epochs", stranger.token, map[string]any{
			"epoch": 2, "priorWrap": sealedKeyWrap, "wraps": []any{map[string]any{
				"deviceSeq": 1, "wrap": sealedKeyWrap, "signerSeq": 1, "chainSeq": 2, "signature": sealedSignature,
			}},
		}).Expect().Status(http.StatusNotFound)
	})

	t.Run("a stranger cannot create in the workspace", func(t *testing.T) {
		f.request("POST", "/api/sealed/records", stranger.token, sealedBody(1, map[string]any{
			"id": newSealedID(), "key": "x", "label": "x", "type": "text", "format": "default",
			"workspace": f.party.workspace,
		})).Expect().Status(http.StatusForbidden)
	})

	t.Run("a stranger cannot hand themselves a key", func(t *testing.T) {
		f.request("POST", "/api/sealed/devices", stranger.token, map[string]any{
			"entries": []any{deviceEntry(1, 1)},
			"wraps": []any{map[string]any{
				"workspace": f.party.workspace, "epoch": 1, "deviceSeq": 1,
				"wrap": sealedKeyWrap, "signerSeq": 1, "chainSeq": 2, "signature": sealedSignature,
			}},
		}).Expect().Status(http.StatusForbidden)
	})

	t.Run("the collections are not reachable directly", func(t *testing.T) {
		api := testutils.NewPBClient(t, f.baseURL)
		for _, coll := range []string{util.Coll.DeviceKeys, util.Coll.WorkspaceKeyEpochs, util.Coll.WorkspaceKeyWraps} {
			api.List(coll, f.party.token).Expect().Status(http.StatusForbidden)
		}
	})

	t.Run("a member who holds no key cannot write or rotate", func(t *testing.T) {
		member := addWorkspaceMember(t, f)
		f.request("PUT", "/api/sealed/records/"+id, member.token, sealedBody(1, map[string]any{
			"expectedVersion": 1,
		})).Expect().Status(http.StatusForbidden)
		f.request("POST", "/api/sealed/workspaces/"+f.party.workspace+"/epochs", member.token, map[string]any{
			"epoch": 2, "priorWrap": sealedKeyWrap, "wraps": []any{map[string]any{
				"deviceSeq": 1, "wrap": sealedKeyWrap, "signerSeq": 1, "chainSeq": 2, "signature": sealedSignature,
			}},
		}).Expect().Status(http.StatusForbidden).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedKeyMissing.ErrorCode)
	})
}

// addWorkspaceMember adds an account to the fixture's workspace with vault
// access, the way the server would, and switches it there.
func addWorkspaceMember(t *testing.T, f *sealedFixture) contactParty {
	t.Helper()
	member := newContactParty(t, f.baseURL)
	collection, err := f.app.FindCollectionByNameOrId(util.Coll.WorkspaceMembers)
	if err != nil {
		t.Fatal(err)
	}
	row := core.NewRecord(collection)
	row.Set(util.Fields.WorkspaceMember.Workspace, f.party.workspace)
	row.Set(util.Fields.WorkspaceMember.User, member.id)
	row.Set(util.Fields.WorkspaceMember.Role, util.RoleMember)
	scopes, _ := util.ExpandPermissions([]string{util.PermVaultRead, util.PermVaultWrite})
	row.Set(util.Fields.WorkspaceMember.Permissions, scopes)
	if err := f.app.Save(row); err != nil {
		t.Fatal(err)
	}
	user, err := f.app.FindRecordById(util.Coll.Users, member.id)
	if err != nil {
		t.Fatal(err)
	}
	user.Set(util.Fields.User.ActiveWorkspace, f.party.workspace)
	user.Set(util.Fields.User.ActiveRole, util.RoleMember)
	if err := f.app.Save(user); err != nil {
		t.Fatal(err)
	}
	return member
}

func TestRemovingAKeyHoldingMemberMakesRotationDue(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	f.createSealed("smtp_password")

	holder := addWorkspaceMember(t, f)
	wraps, err := f.app.FindCollectionByNameOrId(util.Coll.WorkspaceKeyWraps)
	if err != nil {
		t.Fatal(err)
	}
	w := util.Fields.WorkspaceKeyWrap
	row := core.NewRecord(wraps)
	row.Set(w.Workspace, f.party.workspace)
	row.Set(w.Epoch, 1)
	row.Set(w.User, holder.id)
	row.Set(w.DeviceSeq, 1)
	row.Set(w.Wrap, sealedKeyWrap)
	row.Set(w.SignerSeq, 1)
	row.Set(w.Signature, sealedSignature)
	if err := f.app.Save(row); err != nil {
		t.Fatal(err)
	}

	m := util.Fields.WorkspaceMember
	member, err := f.app.FindFirstRecordByFilter(util.Coll.WorkspaceMembers,
		m.Workspace+" = {:w} && "+m.User+" = {:u}", dbx.Params{"w": f.party.workspace, "u": holder.id})
	if err != nil {
		t.Fatal(err)
	}
	if err := f.app.Delete(member); err != nil {
		t.Fatal(err)
	}

	left, _ := f.app.FindRecordsByFilter(util.Coll.WorkspaceKeyWraps,
		w.User+" = {:u}", "", 0, 0, dbx.Params{"u": holder.id})
	if len(left) != 0 {
		t.Fatal("the removed member kept their key")
	}
	f.request("POST", "/api/sealed/records", f.party.token, sealedBody(1, map[string]any{
		"id": newSealedID(), "key": "next", "label": "next", "type": "text", "format": "default",
		"workspace": f.party.workspace,
	})).Expect().Status(http.StatusConflict).
		JSON().Object().Value("code").IsEqual(util.Errors.SealedEpochStale.ErrorCode)
}

func TestSealedRecordRules(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()

	t.Run("a file cannot be sealed yet", func(t *testing.T) {
		f.request("POST", "/api/sealed/records", f.party.token, sealedBody(1, map[string]any{
			"id": newSealedID(), "key": "doc", "label": "doc", "type": util.TypeFile, "format": "default",
			"workspace": f.party.workspace,
		})).Expect().Status(http.StatusBadRequest).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedRecordUnsupported.ErrorCode)
	})

	t.Run("a malformed id or payload is refused", func(t *testing.T) {
		for _, body := range []map[string]any{
			sealedBody(1, map[string]any{"id": "../../etc", "key": "a", "workspace": f.party.workspace}),
			{"id": newSealedID(), "sealedValue": "not base64!", "keyEpoch": 1, "keyWrap": sealedKeyWrap},
			{"id": newSealedID(), "sealedValue": sealedCiphertext, "keyEpoch": 0, "keyWrap": sealedKeyWrap},
		} {
			f.request("POST", "/api/sealed/records", f.party.token, body).
				Expect().Status(http.StatusBadRequest)
		}
	})

	t.Run("nothing can be written before anyone holds a key", func(t *testing.T) {
		other := &sealedFixture{t: t, baseURL: f.baseURL, app: f.app, party: newContactParty(t, f.baseURL)}
		other.request("POST", "/api/sealed/records", other.party.token, sealedBody(1, map[string]any{
			"id": newSealedID(), "key": "a", "label": "a", "type": "text", "format": "default",
			"workspace": other.party.workspace,
		})).Expect().Status(http.StatusForbidden).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedKeyMissing.ErrorCode)
	})

	t.Run("unsealing writes the value back and clears the rest", func(t *testing.T) {
		id := f.createSealed("to_unseal")
		f.request("POST", "/api/sealed/records/"+id+"/unseal", f.party.token, map[string]any{
			"expectedVersion": 9, "value": "back",
		}).Expect().Status(http.StatusConflict)
		f.request("POST", "/api/sealed/records/"+id+"/unseal", f.party.token, map[string]any{
			"expectedVersion": 1, "value": "back",
		}).Expect().Status(http.StatusOK)

		rec, _ := f.app.FindRecordById(util.Coll.Records, id)
		r := util.Fields.Record
		if rec.GetBool(r.Sealed) || rec.GetString(r.Value) != "back" ||
			rec.GetString(r.SealedValue) != "" || rec.GetString(r.KeyWrap) != "" {
			t.Fatal("unsealing left sealed state behind")
		}
	})
}

func TestStartingOverDeletesWhatNobodyCanRead(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	sealedID := f.createSealed("smtp_password")
	plainID := newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "visible", "v")

	f.request("POST", "/api/sealed/reset", f.party.token, map[string]any{"confirm": "yes"}).
		Expect().Status(http.StatusBadRequest)
	if _, err := f.app.FindRecordById(util.Coll.Records, sealedID); err != nil {
		t.Fatal("a refused reset deleted a record")
	}

	f.request("POST", "/api/sealed/reset", f.party.token, map[string]any{
		"confirm": "delete my encrypted records",
	}).Expect().Status(http.StatusOK).JSON().Object().Value("deleted").IsEqual(1)

	if _, err := f.app.FindRecordById(util.Coll.Records, sealedID); err == nil {
		t.Fatal("the unreadable record survived")
	}
	if _, err := f.app.FindRecordById(util.Coll.Records, plainID); err != nil {
		t.Fatal("a plain record was deleted")
	}
	body := f.request("GET", "/api/sealed/state", f.party.token, nil).
		Expect().Status(http.StatusOK).JSON().Object()
	body.Value("devices").Array().IsEmpty()
	body.Value("workspaces").Array().IsEmpty()

	f.enroll()
	f.createSealed("smtp_password")
}

func TestServerAdvertisesSealing(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	testutils.NewExpect(t, baseURL).GET("/api/server").Expect().Status(http.StatusOK).
		JSON().Object().Value("sealing").Object().Value("records").IsEqual(true)
}

// Unsealing must not quietly share a value again on links its owner gave up on.
func TestSealingTakesARecordOffItsLinks(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	target := newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "smtp_password", plainCanary)
	other := newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "visible", "shown")
	slug := f.link(target, other)

	f.request("PUT", "/api/sealed/records/"+target, f.party.token, sealedBody(1, map[string]any{
		"expectedVersion": 0, "dropLinks": true,
	})).Expect().Status(http.StatusOK)

	link, err := f.app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:s}", dbx.Params{"s": slug})
	if err != nil {
		t.Fatal(err)
	}
	if got := link.GetStringSlice(util.Fields.Link.Records); len(got) != 1 || got[0] != other {
		t.Fatalf("link still names %v", got)
	}

	f.request("POST", "/api/sealed/records/"+target+"/unseal", f.party.token, map[string]any{
		"expectedVersion": 1, "value": plainCanary,
	}).Expect().Status(http.StatusOK)

	body := testutils.NewExpect(t, f.baseURL).GET("/s/" + slug + ".txt").
		Expect().Status(http.StatusOK).Body().Raw()
	if strings.Contains(body, plainCanary) {
		t.Fatalf("unsealing shared it again:\n%s", body)
	}
}

func TestUnsealingNeedsTheKeyAndKeepsTheVersionRising(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	id := f.createSealed("smtp_password")

	t.Run("a member without the key cannot replace the ciphertext", func(t *testing.T) {
		member := addWorkspaceMember(t, f)
		rec, _ := f.app.FindRecordById(util.Coll.Records, id)
		rec.Set(util.Fields.Record.User, member.id)
		if err := f.app.Save(rec); err != nil {
			t.Fatal(err)
		}
		f.request("POST", "/api/sealed/records/"+id+"/unseal", member.token, map[string]any{
			"expectedVersion": 1, "value": "planted",
		}).Expect().Status(http.StatusForbidden).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedKeyMissing.ErrorCode)
		rec.Set(util.Fields.Record.User, f.party.id)
		if err := f.app.Save(rec); err != nil {
			t.Fatal(err)
		}
	})

	t.Run("the version never goes back", func(t *testing.T) {
		f.request("POST", "/api/sealed/records/"+id+"/unseal", f.party.token, map[string]any{
			"expectedVersion": 1, "value": "plain again",
		}).Expect().Status(http.StatusOK).JSON().Object().Value("sealedVersion").IsEqual(2)
		f.request("PUT", "/api/sealed/records/"+id, f.party.token, sealedBody(1, map[string]any{
			"expectedVersion": 2,
		})).Expect().Status(http.StatusOK).JSON().Object().Value("sealedVersion").IsEqual(3)
	})
}

// An answer holds a snapshot of what it granted. Sealing the record must take
// that plaintext too, or the requester goes on reading it from the server.
func TestSealingClearsTheAnswerSnapshot(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	target := newRecord(t, f.baseURL, f.party.token, f.party.id, f.party.workspace, "address", plainCanary)

	slug := "sealed-" + uuid.New().String()[:8]
	extractID(t, f.baseURL, util.Coll.Links, f.party.token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "answer",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      f.party.id,
		util.Fields.Link.Workspace: f.party.workspace,
		util.Fields.Link.Records:   []string{target},
	})
	link, err := f.app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:s}", dbx.Params{"s": slug})
	if err != nil {
		t.Fatal(err)
	}
	link.Set(util.Fields.Link.Data, map[string]any{"address": plainCanary, "note": "kept"})
	link.Set(util.Fields.Link.Grants, map[string]string{"address": target})
	if err := f.app.Save(link); err != nil {
		t.Fatal(err)
	}

	f.request("PUT", "/api/sealed/records/"+target, f.party.token, sealedBody(1, map[string]any{
		"expectedVersion": 0, "dropLinks": true,
	})).Expect().Status(http.StatusOK)

	link, err = f.app.FindRecordById(util.Coll.Links, link.Id)
	if err != nil {
		t.Fatal(err)
	}
	raw := link.GetString(util.Fields.Link.Data)
	if strings.Contains(raw, plainCanary) {
		t.Fatalf("the answer kept the plaintext: %s", raw)
	}
	if !strings.Contains(raw, "kept") {
		t.Fatalf("the rest of the answer was lost: %s", raw)
	}
}

func TestAKeyAlreadyHandedOverIsNeverReplaced(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
		"entries": []any{deviceEntry(3, 1)},
		"wraps": []any{map[string]any{
			"workspace": f.party.workspace, "epoch": 1, "deviceSeq": 1,
			"wrap": "AAAA", "signerSeq": 1, "chainSeq": 3, "signature": sealedSignature,
		}},
	}).Expect().Status(http.StatusConflict)

	w := util.Fields.WorkspaceKeyWrap
	row, err := f.app.FindFirstRecordByFilter(util.Coll.WorkspaceKeyWraps,
		w.User+" = {:u} && "+w.DeviceSeq+" = 1", dbx.Params{"u": f.party.id})
	if err != nil || row.GetString(w.Wrap) == "AAAA" {
		t.Fatal("the stored key was overwritten")
	}
}

func TestSealedRecordKeyCannotChange(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	id := f.createSealed("smtp_password")
	testutils.NewPBClient(t, f.baseURL).Update(util.Coll.Records, id, f.party.token, map[string]any{
		util.Fields.Record.Key: "something_else",
	}).Expect().Status(http.StatusBadRequest)
}

func TestStartingOverTellsThePerson(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	f.request("POST", "/api/sealed/reset", f.party.token, map[string]any{
		"confirm": "delete my encrypted records",
	}).Expect().Status(http.StatusOK)
	n := util.Fields.Notification
	rows, err := f.app.FindRecordsByFilter(util.Coll.Notifications,
		n.Type+" = {:t} && user = {:u}", "", 0, 0,
		dbx.Params{"t": util.NotificationSealingReset, "u": f.party.id})
	if err != nil || len(rows) == 0 {
		t.Fatalf("no notification for a reset: %v", err)
	}
}
