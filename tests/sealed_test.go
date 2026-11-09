package tests

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"testing"

	"revoked/cmd/revoked/services"
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
const plainCanary = "plain-canary-value-7f3a"

var (
	sealedCiphertext = base64.URLEncoding.EncodeToString([]byte("stand-in ciphertext, opaque to the server"))
	sealedKeyWrap    = base64.URLEncoding.EncodeToString([]byte("stand-in wrapped key"))
	sealedSignature  = base64.URLEncoding.EncodeToString([]byte("stand-in signature"))
)

type sealedFixture struct {
	t       *testing.T
	baseURL string
	app     *pocketbase.PocketBase
	party   contactParty
	chain   *util.SealedChain
	signers map[int]*sealedSigner
}

func newSealedFixture(t *testing.T) *sealedFixture {
	t.Helper()
	baseURL, app := testutils.SetupTestApp(t)
	return sealedFixtureFor(t, baseURL, app, newContactParty(t, baseURL))
}

func sealedFixtureFor(t *testing.T, baseURL string, app *pocketbase.PocketBase, party contactParty) *sealedFixture {
	return &sealedFixture{
		t: t, baseURL: baseURL, app: app, party: party,
		chain: &util.SealedChain{}, signers: map[int]*sealedSigner{},
	}
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

// sealedSigner plays a device's signing key: what the app holds, and what a
// stolen session does not.
type sealedSigner struct {
	key    *ecdsa.PrivateKey
	public []byte
}

func newSealedSigner(t *testing.T) *sealedSigner {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return &sealedSigner{key: key, public: elliptic.Marshal(elliptic.P256(), key.X, key.Y)}
}

func (s *sealedSigner) signRaw(message []byte) []byte {
	digest := sha256.Sum256(message)
	r, sig, err := ecdsa.Sign(rand.Reader, s.key, digest[:])
	if err != nil {
		panic(err)
	}
	n := elliptic.P256().Params().N
	if sig.Cmp(new(big.Int).Rsh(n, 1)) > 0 {
		sig = new(big.Int).Sub(n, sig)
	}
	return append(r.FillBytes(make([]byte, 32)), sig.FillBytes(make([]byte, 32))...)
}

func encodeSealed(b []byte) string { return base64.URLEncoding.EncodeToString(b) }

func sealedEntryJSON(e util.SealedChainEntry) map[string]any {
	return map[string]any{
		"seq":              e.Seq,
		"action":           e.Action,
		"kind":             e.Kind,
		"label":            e.Label,
		"credentialId":     e.CredentialID,
		"hpkePublicKey":    encodeSealed(e.HpkePublicKey),
		"signingPublicKey": encodeSealed(e.SigningPublicKey),
		"targetSeq":        e.TargetSeq,
		"previousHash":     encodeSealed(e.PreviousHash),
		"signerSeq":        e.SignerSeq,
		"anchorSignature":  encodeSealed(e.AnchorSignature),
		"signature":        encodeSealed(e.Signature),
	}
}

// addition builds a correctly signed entry adding a device or recovery key,
// without assuming the server took it.
func (f *sealedFixture) addition(kind string) (util.SealedChainEntry, *sealedSigner) {
	f.t.Helper()
	signer := newSealedSigner(f.t)
	hpke := newSealedSigner(f.t)
	e := util.SealedChainEntry{
		User: f.party.id, Seq: f.chain.NextSeq(), Action: util.SealedActionAdd, Kind: kind,
		Label: kind, HpkePublicKey: hpke.public, SigningPublicKey: signer.public,
		PreviousHash: f.chain.HeadHash(), SignerSeq: 1,
	}
	if e.Seq == 1 {
		e.Signature = signer.signRaw(e.Payload())
		return e, signer
	}
	if kind == util.SealedKindRecovery {
		e.AnchorSignature = signer.signRaw(util.SealedRecoveryAnchorPayload(f.party.id, f.chain.Entry(1).Hash()))
	}
	e.Signature = f.signers[1].signRaw(e.Payload())
	return e, signer
}

// passkeyAddition builds a passkey entry signed by signerSeq and anchored by
// the passkey's own derived key, as the app does from a PRF output.
func (f *sealedFixture) passkeyAddition(credential string, signerSeq int) (util.SealedChainEntry, *sealedSigner) {
	f.t.Helper()
	signer := newSealedSigner(f.t)
	hpke := newSealedSigner(f.t)
	e := util.SealedChainEntry{
		User: f.party.id, Seq: f.chain.NextSeq(), Action: util.SealedActionAdd, Kind: util.SealedKindPasskey,
		Label: "Chrome on Mac", CredentialID: credential, HpkePublicKey: hpke.public, SigningPublicKey: signer.public,
		PreviousHash: f.chain.HeadHash(), SignerSeq: signerSeq,
	}
	e.AnchorSignature = signer.signRaw(util.SealedPasskeyAnchorPayload(f.party.id, f.chain.Entry(1).Hash(), credential))
	e.Signature = f.signers[signerSeq].signRaw(e.Payload())
	return e, signer
}

func (f *sealedFixture) removal(target int) util.SealedChainEntry {
	f.t.Helper()
	e := util.SealedChainEntry{
		User: f.party.id, Seq: f.chain.NextSeq(), Action: util.SealedActionRemove,
		TargetSeq: target, PreviousHash: f.chain.HeadHash(), SignerSeq: 1,
	}
	e.Signature = f.signers[1].signRaw(e.Payload())
	return e
}

// accept records an entry the server took, so the next one follows from it.
func (f *sealedFixture) accept(e util.SealedChainEntry, signer *sealedSigner) {
	f.t.Helper()
	f.chain.Load(e)
	if signer != nil {
		f.signers[e.Seq] = signer
	}
}

func (f *sealedFixture) wrapTo(workspace string, epoch, deviceSeq int) map[string]any {
	chainSeq := f.chain.HeadSeq()
	return f.wrapSigned(workspace, epoch, deviceSeq, chainSeq)
}

func (f *sealedFixture) wrapSigned(workspace string, epoch, deviceSeq, chainSeq int) map[string]any {
	wrap := sealedKeyWrap
	payload := util.SealedWrapPayload(workspace, epoch, f.chain.Entry(deviceSeq).HpkePublicKey, wrap, chainSeq)
	return map[string]any{
		"workspace": workspace, "epoch": epoch, "deviceSeq": deviceSeq, "wrap": wrap,
		"signerSeq": 1, "chainSeq": chainSeq, "signature": encodeSealed(f.signers[1].signRaw(payload)),
	}
}

// enroll adds a device and a recovery entry, and starts the workspace's key.
func (f *sealedFixture) enroll() {
	f.t.Helper()
	first, firstSigner := f.addition(util.SealedKindDevice)
	f.accept(first, firstSigner)
	recovery, recoverySigner := f.addition(util.SealedKindRecovery)
	f.accept(recovery, recoverySigner)
	f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
		"entries": []any{sealedEntryJSON(first), sealedEntryJSON(recovery)},
	}).Expect().Status(http.StatusOK)
	f.startEpoch(1, "", 1, 2).Status(http.StatusOK)
}

func (f *sealedFixture) startEpoch(epoch int, prior string, devices ...int) *httpexpect.Response {
	f.t.Helper()
	wraps := []any{}
	for _, seq := range devices {
		wraps = append(wraps, f.wrapTo(f.party.workspace, epoch, seq))
	}
	return f.request("POST", "/api/sealed/workspaces/"+f.party.workspace+"/epochs", f.party.token,
		map[string]any{"epoch": epoch, "priorWrap": prior, "wraps": wraps}).Expect()
}

// unsealBody is what the app sends: signed by a device on the list.
func (f *sealedFixture) unsealBody(id string, version int, value string) map[string]any {
	payload := util.SealedUnsealPayload(f.party.id, id, version, value)
	return map[string]any{
		"expectedVersion": version, "value": value, "deviceSeq": 1,
		"signature": encodeSealed(f.signers[1].signRaw(payload)),
	}
}

// put is a sealed write naming the record key the ciphertext is bound to.
func (f *sealedFixture) put(id string, epoch int, extra map[string]any) map[string]any {
	rec, err := f.app.FindRecordById(util.Coll.Records, id)
	if err != nil {
		f.t.Fatal(err)
	}
	body := sealedBody(epoch, extra)
	body["key"] = rec.GetString(util.Fields.Record.Key)
	return body
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

	f.request("PUT", "/api/sealed/records/"+target, f.party.token, f.put(target, 1, map[string]any{
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
		f.request("PUT", "/api/sealed/records/"+target, f.party.token, f.put(target, 1, map[string]any{
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

	body := f.request("PUT", "/api/sealed/records/"+target, f.party.token, f.put(target, 1, map[string]any{
		"expectedVersion": 0,
	})).Expect().Status(http.StatusConflict).JSON().Object()
	body.Value("code").IsEqual(util.Errors.SealedLinksAffected.ErrorCode)
	body.Value("links").IsEqual(2)

	rec, _ := f.app.FindRecordById(util.Coll.Records, target)
	if rec.GetBool(util.Fields.Record.Sealed) || rec.GetString(util.Fields.Record.Value) != "v" {
		t.Fatal("a refused sealing changed the record")
	}

	f.request("PUT", "/api/sealed/records/"+target, f.party.token, f.put(target, 1, map[string]any{
		"expectedVersion": 0, "dropLinks": true,
	})).Expect().Status(http.StatusOK)
}

func TestSealedWritesMoveOneVersionAtATime(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	id := f.createSealed("smtp_password")

	t.Run("a stale version is refused", func(t *testing.T) {
		f.request("PUT", "/api/sealed/records/"+id, f.party.token, f.put(id, 1, map[string]any{
			"expectedVersion": 5,
		})).Expect().Status(http.StatusConflict).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedVersionConflict.ErrorCode)
	})

	t.Run("sealing what is already sealed is refused", func(t *testing.T) {
		f.request("PUT", "/api/sealed/records/"+id, f.party.token, f.put(id, 1, map[string]any{
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
				results[i] = f.request("PUT", "/api/sealed/records/"+id, f.party.token, f.put(id, 1, map[string]any{"expectedVersion": 1})).Expect().Raw().StatusCode
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
		f.request("PUT", "/api/sealed/records/"+id, f.party.token, f.put(id, 1, map[string]any{
			"expectedVersion": 1,
		})).Expect().Status(http.StatusConflict).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedEpochStale.ErrorCode)
	})

	t.Run("removing a device withdraws its key and blocks writes until rotation", func(t *testing.T) {
		added, signer := f.addition(util.SealedKindDevice)
		f.accept(added, signer)
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{sealedEntryJSON(added)},
			"wraps":   []any{f.wrapTo(f.party.workspace, 2, added.Seq)},
		}).Expect().Status(http.StatusOK)

		removal := f.removal(added.Seq)
		f.accept(removal, nil)
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{sealedEntryJSON(removal)},
		}).Expect().Status(http.StatusOK)

		w := util.Fields.WorkspaceKeyWrap
		rows, _ := f.app.FindRecordsByFilter(util.Coll.WorkspaceKeyWraps,
			w.User+" = {:u} && "+w.DeviceSeq+" = {:d}", "", 0, 0,
			dbx.Params{"u": f.party.id, "d": added.Seq})
		if len(rows) != 0 {
			t.Fatal("the removed device kept its key")
		}

		f.request("PUT", "/api/sealed/records/"+id, f.party.token, f.put(id, 2, map[string]any{
			"expectedVersion": 1,
		})).Expect().Status(http.StatusConflict).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedEpochStale.ErrorCode)

		f.startEpoch(3, sealedKeyWrap, 1, 2).Status(http.StatusOK)
		f.request("PUT", "/api/sealed/records/"+id, f.party.token, f.put(id, 3, map[string]any{
			"expectedVersion": 1,
		})).Expect().Status(http.StatusOK)
	})

	t.Run("a key cannot be handed to a removed device", func(t *testing.T) {
		removedSeq := f.chain.HeadSeq() - 1
		added, signer := f.addition(util.SealedKindDevice)
		wrap := f.wrapSigned(f.party.workspace, 3, 1, f.chain.HeadSeq())
		wrap["deviceSeq"] = removedSeq
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{sealedEntryJSON(added)},
			"wraps":   []any{wrap},
		}).Expect().Status(http.StatusBadRequest)
		_ = signer
	})

	t.Run("the list cannot skip or rewrite entries", func(t *testing.T) {
		added, _ := f.addition(util.SealedKindDevice)
		skipped := sealedEntryJSON(added)
		skipped["seq"] = 99
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{skipped},
		}).Expect().Status(http.StatusConflict)
		rewritten := sealedEntryJSON(added)
		rewritten["seq"] = 1
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{rewritten},
		}).Expect().Status(http.StatusConflict)
	})
}

// A session can be stolen. A device's signing key can't be taken from here, so a
// session alone must not be able to change the list or the keys on it.
func TestAStolenSessionCannotChangeTheList(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	id := f.createSealed("smtp_password")

	wrapCount := func() int {
		w := util.Fields.WorkspaceKeyWrap
		rows, _ := f.app.FindRecordsByFilter(util.Coll.WorkspaceKeyWraps,
			w.User+" = {:u}", "", 0, 0, dbx.Params{"u": f.party.id})
		return len(rows)
	}
	before := wrapCount()
	listLength := func() int {
		d := util.Fields.DeviceKey
		rows, _ := f.app.FindRecordsByFilter(util.Coll.DeviceKeys,
			d.User+" = {:u}", "", 0, 0, dbx.Params{"u": f.party.id})
		return len(rows)
	}

	post := func(entry map[string]any) *httpexpect.Response {
		return f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{entry},
		}).Expect()
	}

	t.Run("an unsigned removal deletes nothing", func(t *testing.T) {
		removal := f.removal(1)
		entry := sealedEntryJSON(removal)
		entry["signature"] = encodeSealed(make([]byte, 64))
		post(entry).Status(http.StatusBadRequest)
		if wrapCount() != before || listLength() != 2 {
			t.Fatal("an unsigned removal changed something")
		}
	})

	t.Run("a removal signed by a stranger's key is refused", func(t *testing.T) {
		removal := f.removal(1)
		removal.Signature = newSealedSigner(t).signRaw(removal.Payload())
		post(sealedEntryJSON(removal)).Status(http.StatusBadRequest)
	})

	t.Run("an entry not following the last is refused", func(t *testing.T) {
		added, _ := f.addition(util.SealedKindDevice)
		added.PreviousHash = make([]byte, 32)
		added.Signature = f.signers[1].signRaw(added.Payload())
		post(sealedEntryJSON(added)).Status(http.StatusBadRequest)
	})

	t.Run("a garbage public key is refused", func(t *testing.T) {
		added, _ := f.addition(util.SealedKindDevice)
		added.HpkePublicKey = []byte("not a point")
		added.Signature = f.signers[1].signRaw(added.Payload())
		post(sealedEntryJSON(added)).Status(http.StatusBadRequest)
	})

	t.Run("a second recovery key is refused", func(t *testing.T) {
		added, _ := f.addition(util.SealedKindRecovery)
		post(sealedEntryJSON(added)).Status(http.StatusBadRequest)
	})

	t.Run("a malleated signature is refused", func(t *testing.T) {
		added, _ := f.addition(util.SealedKindDevice)
		n := elliptic.P256().Params().N
		s := new(big.Int).SetBytes(added.Signature[32:])
		added.Signature = append(added.Signature[:32:32], new(big.Int).Sub(n, s).FillBytes(make([]byte, 32))...)
		post(sealedEntryJSON(added)).Status(http.StatusBadRequest)
	})

	t.Run("a junk key hand-over is refused", func(t *testing.T) {
		f.request("POST", "/api/sealed/workspaces/"+f.party.workspace+"/epochs", f.party.token, map[string]any{
			"epoch": 2, "priorWrap": sealedKeyWrap, "wraps": []any{
				map[string]any{"deviceSeq": 1, "wrap": sealedKeyWrap, "signerSeq": 1, "chainSeq": 2, "signature": sealedSignature},
				map[string]any{"deviceSeq": 2, "wrap": sealedKeyWrap, "signerSeq": 1, "chainSeq": 2, "signature": sealedSignature},
			},
		}).Expect().Status(http.StatusBadRequest)
		e := util.Fields.WorkspaceKeyEpoch
		rows, _ := f.app.FindRecordsByFilter(util.Coll.WorkspaceKeyEpochs,
			e.Workspace+" = {:w}", "", 0, 0, dbx.Params{"w": f.party.workspace})
		if len(rows) != 1 {
			t.Fatal("a junk epoch was stored")
		}
	})

	t.Run("it cannot unseal and plant a value", func(t *testing.T) {
		f.request("POST", "/api/sealed/records/"+id+"/unseal", f.party.token, map[string]any{
			"expectedVersion": 1, "value": "attacker-chosen", "deviceSeq": 1, "signature": encodeSealed(make([]byte, 64)),
		}).Expect().Status(http.StatusForbidden)
		f.request("POST", "/api/sealed/records/"+id+"/unseal", f.party.token, map[string]any{
			"expectedVersion": 1, "value": "attacker-chosen",
		}).Expect().Status(http.StatusForbidden)
		// A signature over another value doesn't carry over.
		body := f.unsealBody(id, 1, "what the owner meant")
		body["value"] = "attacker-chosen"
		f.request("POST", "/api/sealed/records/"+id+"/unseal", f.party.token, body).
			Expect().Status(http.StatusForbidden)
		rec, _ := f.app.FindRecordById(util.Coll.Records, id)
		if !rec.GetBool(util.Fields.Record.Sealed) {
			t.Fatal("the record was unsealed")
		}
	})
}

func TestADeviceListCannotGrowWithoutLimit(t *testing.T) {
	f := newSealedFixture(t)
	first, signer := f.addition(util.SealedKindDevice)
	f.accept(first, signer)
	entries := []any{sealedEntryJSON(first)}
	for len(f.chain.Live()) < util.MaxSealedLiveEntries {
		added, s := f.addition(util.SealedKindDevice)
		f.accept(added, s)
		entries = append(entries, sealedEntryJSON(added))
	}
	f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{"entries": entries}).
		Expect().Status(http.StatusOK)
	over, _ := f.addition(util.SealedKindDevice)
	f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
		"entries": []any{sealedEntryJSON(over)},
	}).Expect().Status(http.StatusBadRequest)

	// And a full list can still be emptied in one write.
	removals := []any{}
	for _, seq := range f.chain.Live() {
		if seq == 1 {
			continue
		}
		removal := f.removal(seq)
		f.accept(removal, nil)
		removals = append(removals, sealedEntryJSON(removal))
	}
	f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{"entries": removals}).
		Expect().Status(http.StatusOK)
}

func TestSigningOutOtherSessions(t *testing.T) {
	f := newSealedFixture(t)
	old := f.party.token
	fresh := f.request("POST", "/api/sealed/sessions/revoke", old, nil).
		Expect().Status(http.StatusOK).JSON().Object().Value("token").String().Raw()

	f.request("GET", "/api/sealed/state", old, nil).Expect().Status(http.StatusUnauthorized)
	f.request("GET", "/api/sealed/state", fresh, nil).Expect().Status(http.StatusOK)
	f.request("POST", "/api/sealed/sessions/revoke", "", nil).Expect().Status(http.StatusUnauthorized)
}

func TestASealedWriteIsBoundToTheKeyItsClientSaw(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	id := f.createSealed("smtp_password")
	body := f.put(id, 1, map[string]any{"expectedVersion": 1})
	body["key"] = "renamed_meanwhile"
	f.request("PUT", "/api/sealed/records/"+id, f.party.token, body).
		Expect().Status(http.StatusConflict)

	saved := f.put(id, 1, map[string]any{
		"expectedVersion": 1, "label": "SMTP login", "format": util.FormatHidden,
	})
	f.request("PUT", "/api/sealed/records/"+id, f.party.token, saved).
		Expect().Status(http.StatusOK).JSON().Object().Value("label").IsEqual("SMTP login")
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
		f.request("PUT", "/api/sealed/records/"+id, stranger.token, f.put(id, 1, map[string]any{
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
		other := sealedFixtureFor(t, f.baseURL, f.app, stranger)
		first, signer := other.addition(util.SealedKindDevice)
		other.accept(first, signer)
		other.request("POST", "/api/sealed/devices", stranger.token, map[string]any{
			"entries": []any{sealedEntryJSON(first)},
			"wraps":   []any{other.wrapTo(f.party.workspace, 1, 1)},
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
		// The record is the owner's and private, so to the member it is not
		// there at all.
		f.request("PUT", "/api/sealed/records/"+id, member.token, f.put(id, 1, map[string]any{
			"expectedVersion": 1,
		})).Expect().Status(http.StatusNotFound)
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

func TestLosingVaultReadTakesTheKeyAway(t *testing.T) {
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
	copies := func() int {
		left, _ := f.app.FindRecordsByFilter(util.Coll.WorkspaceKeyWraps,
			w.User+" = {:u}", "", 0, 0, dbx.Params{"u": holder.id})
		return len(left)
	}

	// A change that keeps vault read leaves the key where it is.
	readOnly, _ := util.ExpandPermissions([]string{util.PermVaultRead})
	member.Set(m.Permissions, readOnly)
	if err := f.app.Save(member); err != nil {
		t.Fatal(err)
	}
	if copies() != 1 {
		t.Fatal("a member who can still read the vault lost their key")
	}

	noVault, _ := util.ExpandPermissions([]string{util.PermSharesRead})
	member.Set(m.Permissions, noVault)
	if err := f.app.Save(member); err != nil {
		t.Fatal(err)
	}
	if copies() != 0 {
		t.Fatal("a member who can no longer read the vault kept their key")
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
		other := sealedFixtureFor(t, f.baseURL, f.app, newContactParty(t, f.baseURL))
		other.request("POST", "/api/sealed/records", other.party.token, sealedBody(1, map[string]any{
			"id": newSealedID(), "key": "a", "label": "a", "type": "text", "format": "default",
			"workspace": other.party.workspace,
		})).Expect().Status(http.StatusForbidden).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedKeyMissing.ErrorCode)
	})

	t.Run("unsealing writes the value back and clears the rest", func(t *testing.T) {
		id := f.createSealed("to_unseal")
		f.request("POST", "/api/sealed/records/"+id+"/unseal", f.party.token, f.unsealBody(id, 9, "back")).Expect().Status(http.StatusConflict)
		f.request("POST", "/api/sealed/records/"+id+"/unseal", f.party.token, f.unsealBody(id, 1, "back")).Expect().Status(http.StatusOK)

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

	f.chain = &util.SealedChain{}
	f.signers = map[int]*sealedSigner{}
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

	f.request("PUT", "/api/sealed/records/"+target, f.party.token, f.put(target, 1, map[string]any{
		"expectedVersion": 0, "dropLinks": true,
	})).Expect().Status(http.StatusOK)

	link, err := f.app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:s}", dbx.Params{"s": slug})
	if err != nil {
		t.Fatal(err)
	}
	if got := link.GetStringSlice(util.Fields.Link.Records); len(got) != 1 || got[0] != other {
		t.Fatalf("link still names %v", got)
	}

	f.request("POST", "/api/sealed/records/"+target+"/unseal", f.party.token, f.unsealBody(target, 1, plainCanary)).Expect().Status(http.StatusOK)

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
		f.request("POST", "/api/sealed/records/"+id+"/unseal", f.party.token, f.unsealBody(id, 1, "plain again")).Expect().Status(http.StatusOK).JSON().Object().Value("sealedVersion").IsEqual(2)
		f.request("PUT", "/api/sealed/records/"+id, f.party.token, f.put(id, 1, map[string]any{
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

	f.request("PUT", "/api/sealed/records/"+target, f.party.token, f.put(target, 1, map[string]any{
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
	added, _ := f.addition(util.SealedKindDevice)
	wrap := f.wrapTo(f.party.workspace, 1, 1)
	wrap["wrap"] = "AAAA"
	wrap["signature"] = encodeSealed(f.signers[1].signRaw(util.SealedWrapPayload(
		f.party.workspace, 1, f.chain.Entry(1).HpkePublicKey, "AAAA", f.chain.HeadSeq())))
	f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
		"entries": []any{sealedEntryJSON(added)},
		"wraps":   []any{wrap},
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

// Go's decoder skips newlines and tolerates spare trailing bits; the app's
// doesn't. One entry the server accepts and no client can parse would brick the
// list for good, so the server takes only the app's exact encoding.
func TestOnlyTheCanonicalEncodingIsAccepted(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()

	variants := map[string]func(map[string]any){
		"a newline as an anchor":       func(e map[string]any) { e["anchorSignature"] = "\n" },
		"a CRLF as an anchor":          func(e map[string]any) { e["anchorSignature"] = "\r\n" },
		"a newline inside a signature": func(e map[string]any) { e["signature"] = "\n" + e["signature"].(string) },
		"spare bits in a signature": func(e map[string]any) {
			sig := e["signature"].(string)
			e["signature"] = sig[:len(sig)-3] + "B=="
		},
		"spare bits in the previous hash": func(e map[string]any) {
			hash := e["previousHash"].(string)
			e["previousHash"] = hash[:len(hash)-2] + "B="
		},
		"unpadded": func(e map[string]any) { e["signature"] = strings.TrimRight(e["signature"].(string), "=") },
	}
	for name, spoil := range variants {
		t.Run(name, func(t *testing.T) {
			added, _ := f.addition(util.SealedKindDevice)
			entry := sealedEntryJSON(added)
			spoil(entry)
			f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
				"entries": []any{entry},
			}).Expect().Status(http.StatusBadRequest)
		})
	}

	t.Run("a newline on a removal's empty key", func(t *testing.T) {
		removal := sealedEntryJSON(f.removal(2))
		removal["hpkePublicKey"] = "\n"
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{removal},
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("the list is untouched", func(t *testing.T) {
		body := f.request("GET", "/api/sealed/state", f.party.token, nil).
			Expect().Status(http.StatusOK).JSON().Object()
		body.Value("devices").Array().Length().IsEqual(2)
	})
}

// A passkey holds a key through a chain entry of its own (E2EE.md §6.8). What
// keeps a stolen session out is that such an entry is never self-signed: the
// session can make a passkey, but holds nothing that may vouch for one.
func TestAPasskeyCanHoldTheKey(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	d := util.Fields.DeviceKey
	w := util.Fields.WorkspaceKeyWrap
	listLength := func() int {
		rows, _ := f.app.FindRecordsByFilter(util.Coll.DeviceKeys,
			d.User+" = {:u}", "", 0, 0, dbx.Params{"u": f.party.id})
		return len(rows)
	}
	wrapsTo := func(seq int) int {
		rows, _ := f.app.FindRecordsByFilter(util.Coll.WorkspaceKeyWraps,
			w.User+" = {:u} && "+w.DeviceSeq+" = {:d}", "", 0, 0, dbx.Params{"u": f.party.id, "d": seq})
		return len(rows)
	}
	post := func(entry util.SealedChainEntry, wraps ...map[string]any) *httpexpect.Response {
		body := map[string]any{"entries": []any{sealedEntryJSON(entry)}}
		if len(wraps) > 0 {
			body["wraps"] = wraps
		}
		return f.request("POST", "/api/sealed/devices", f.party.token, body).Expect()
	}

	t.Run("a stolen session cannot make its own passkey a key holder", func(t *testing.T) {
		// Self-signed: the only signature a session without a device key can make.
		e, signer := f.passkeyAddition("thief-credential", 1)
		e.SignerSeq = e.Seq
		e.Signature = signer.signRaw(e.Payload())
		post(e).Status(http.StatusBadRequest)
		// Or signed by a key of its own choosing.
		e, _ = f.passkeyAddition("thief-credential", 1)
		e.Signature = newSealedSigner(t).signRaw(e.Payload())
		post(e).Status(http.StatusBadRequest)
		if listLength() != 2 {
			t.Fatal("a passkey entry landed without a device's signature")
		}
	})

	t.Run("its anchor must cover this root and this credential", func(t *testing.T) {
		e, signer := f.passkeyAddition("cred-a", 1)
		e.AnchorSignature = signer.signRaw(util.SealedPasskeyAnchorPayload(f.party.id, make([]byte, 32), "cred-a"))
		e.Signature = f.signers[1].signRaw(e.Payload())
		post(e).Status(http.StatusBadRequest)

		e, signer = f.passkeyAddition("cred-a", 1)
		e.AnchorSignature = signer.signRaw(util.SealedPasskeyAnchorPayload(f.party.id, f.chain.Entry(1).Hash(), "cred-b"))
		e.Signature = f.signers[1].signRaw(e.Payload())
		post(e).Status(http.StatusBadRequest)

		e, _ = f.passkeyAddition("", 1)
		post(e).Status(http.StatusBadRequest)

		// A device entry cannot borrow the credential field.
		device, _ := f.addition(util.SealedKindDevice)
		device.CredentialID = "cred-a"
		device.Signature = f.signers[1].signRaw(device.Payload())
		post(device).Status(http.StatusBadRequest)
		if listLength() != 2 {
			t.Fatal("a mis-anchored entry landed")
		}
	})

	t.Run("a device holding the key enrols it and hands it the key", func(t *testing.T) {
		e, signer := f.passkeyAddition("cred-a", 1)
		f.accept(e, signer)
		post(e, f.wrapTo(f.party.workspace, 1, e.Seq)).Status(http.StatusOK)
		state := f.request("GET", "/api/sealed/state", f.party.token, nil).Expect().Status(http.StatusOK).JSON().Object()
		third := state.Value("devices").Array().Value(2).Object()
		third.Value("kind").String().IsEqual(util.SealedKindPasskey)
		third.Value("credentialId").String().IsEqual("cred-a")
		if wrapsTo(e.Seq) != 1 {
			t.Fatal("the passkey entry received no key")
		}
	})

	t.Run("one live entry per credential", func(t *testing.T) {
		e, _ := f.passkeyAddition("cred-a", 1)
		post(e).Status(http.StatusBadRequest)
	})

	t.Run("the passkey can vouch for a device", func(t *testing.T) {
		signer := newSealedSigner(t)
		hpke := newSealedSigner(t)
		e := util.SealedChainEntry{
			User: f.party.id, Seq: f.chain.NextSeq(), Action: util.SealedActionAdd, Kind: util.SealedKindDevice,
			Label: "iPhone or iPad", HpkePublicKey: hpke.public, SigningPublicKey: signer.public,
			PreviousHash: f.chain.HeadHash(), SignerSeq: 3,
		}
		e.Signature = f.signers[3].signRaw(e.Payload())
		f.accept(e, signer)
		post(e).Status(http.StatusOK)
		if listLength() != 4 {
			t.Fatal("the device the passkey vouched for was refused")
		}
	})

	t.Run("removing it withdraws its key and makes a new one due", func(t *testing.T) {
		removal := f.removal(3)
		f.accept(removal, nil)
		post(removal).Status(http.StatusOK)
		if wrapsTo(3) != 0 {
			t.Fatal("the removed passkey still holds a key")
		}
		epoch := util.Fields.WorkspaceKeyEpoch
		current, _ := f.app.FindFirstRecordByFilter(util.Coll.WorkspaceKeyEpochs,
			epoch.Workspace+" = {:w}", dbx.Params{"w": f.party.workspace})
		if current == nil || !current.GetBool(epoch.RotationDue) {
			t.Fatal("no new key is due after removing a key holder")
		}
	})
}

func (f *sealedFixture) startAccountEpoch(epoch int, prior string, devices ...int) *httpexpect.Response {
	f.t.Helper()
	scope := util.SealedAccountScope(f.party.id)
	wraps := []any{}
	for _, seq := range devices {
		wraps = append(wraps, f.wrapTo(scope, epoch, seq))
	}
	return f.request("POST", "/api/sealed/account/epochs", f.party.token,
		map[string]any{"epoch": epoch, "priorWrap": prior, "wraps": wraps}).Expect()
}

func TestTheAccountKeyStaysWithItsOwner(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	scope := util.SealedAccountScope(f.party.id)

	t.Run("it must reach every live device", func(t *testing.T) {
		f.startAccountEpoch(1, "", 1).Status(http.StatusBadRequest)
	})

	t.Run("the first one starts at epoch 1, with nothing before it", func(t *testing.T) {
		f.startAccountEpoch(2, sealedKeyWrap, 1, 2).Status(http.StatusConflict)
		f.startAccountEpoch(1, "", 1, 2).Status(http.StatusOK)
		f.startAccountEpoch(1, "", 1, 2).Status(http.StatusConflict)
	})

	t.Run("the state serves it under its scope, only to its owner", func(t *testing.T) {
		account := f.request("GET", "/api/sealed/state", f.party.token, nil).Expect().
			Status(http.StatusOK).JSON().Object().Value("account").Object()
		account.Value("workspace").IsEqual(scope)
		account.Value("wraps").Array().Length().IsEqual(2)

		other := newContactParty(t, f.baseURL)
		f.request("GET", "/api/sealed/state", other.token, nil).Expect().
			Status(http.StatusOK).JSON().Object().Value("account").IsNull()
	})

	t.Run("nobody else's device can be handed it", func(t *testing.T) {
		other := sealedFixtureFor(t, f.baseURL, f.app, newContactParty(t, f.baseURL))
		other.enroll()
		added, signer := other.addition(util.SealedKindDevice)
		other.accept(added, signer)
		other.request("POST", "/api/sealed/devices", other.party.token, map[string]any{
			"entries": []any{sealedEntryJSON(added)},
			"wraps":   []any{other.wrapTo(scope, 1, added.Seq)},
		}).Expect().Status(http.StatusBadRequest)
		wrap := other.wrapTo(scope, 1, 1)
		other.request("POST", "/api/sealed/account/epochs", other.party.token, map[string]any{
			"epoch": 1, "priorWrap": "", "wraps": []any{wrap},
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("a new device gets it with its entry", func(t *testing.T) {
		added, signer := f.addition(util.SealedKindDevice)
		f.accept(added, signer)
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{sealedEntryJSON(added)},
			"wraps":   []any{f.wrapTo(f.party.workspace, 1, added.Seq), f.wrapTo(scope, 1, added.Seq)},
		}).Expect().Status(http.StatusOK)

		w := util.Fields.AccountKeyWrap
		rows, _ := f.app.FindRecordsByFilter(util.Coll.AccountKeyWraps,
			w.User+" = {:u} && "+w.DeviceSeq+" = {:d}", "", 0, 0,
			dbx.Params{"u": f.party.id, "d": added.Seq})
		if len(rows) != 1 {
			t.Fatal("the new device did not get the account key")
		}

		removal := f.removal(added.Seq)
		f.accept(removal, nil)
		f.request("POST", "/api/sealed/devices", f.party.token, map[string]any{
			"entries": []any{sealedEntryJSON(removal)},
		}).Expect().Status(http.StatusOK)
		rows, _ = f.app.FindRecordsByFilter(util.Coll.AccountKeyWraps,
			w.User+" = {:u} && "+w.DeviceSeq+" = {:d}", "", 0, 0,
			dbx.Params{"u": f.party.id, "d": added.Seq})
		if len(rows) != 0 {
			t.Fatal("the removed device kept the account key")
		}
		current := services.CurrentAccountEpoch(f.app, f.party.id)
		if current == nil || !current.GetBool(util.Fields.AccountKeyEpoch.RotationDue) {
			t.Fatal("removing a device that held the account key did not make a new one due")
		}
	})

	t.Run("replacing it needs the old one wrapped under it", func(t *testing.T) {
		f.startAccountEpoch(2, "", 1, 2).Status(http.StatusBadRequest)
		f.startAccountEpoch(2, sealedKeyWrap, 1, 2).Status(http.StatusOK)
	})

	t.Run("starting over deletes it and the identity keys under it", func(t *testing.T) {
		identities, err := f.app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			t.Fatal(err)
		}
		i := util.Fields.Identity
		identity := core.NewRecord(identities)
		identity.Set(i.Name, "Signer")
		identity.Set(i.Certificate, "stand-in certificate")
		identity.Set(i.PublicKey, "stand-in public key")
		identity.Set(i.Fingerprint, newSealedID())
		identity.Set(i.User, f.party.id)
		identity.Set(i.Workspace, f.party.workspace)
		identity.Set(i.Status, util.StatusActive)
		identity.Set(i.SealedKey, sealedCiphertext)
		identity.Set(i.SealedKeyEpoch, 2)
		identity.Set(i.SealedKeyScope, util.SealedKeyScopeAccount)
		if err := f.app.Save(identity); err != nil {
			t.Fatal(err)
		}

		f.request("POST", "/api/sealed/reset", f.party.token, map[string]any{
			"confirm": "delete my encrypted records",
		}).Expect().Status(http.StatusOK)

		if services.CurrentAccountEpoch(f.app, f.party.id) != nil {
			t.Fatal("the account key outlived starting over")
		}
		left, _ := f.app.FindRecordsByFilter(util.Coll.AccountKeyWraps,
			util.Fields.AccountKeyWrap.User+" = {:u}", "", 0, 0, dbx.Params{"u": f.party.id})
		if len(left) != 0 {
			t.Fatal("copies of the account key outlived starting over")
		}
		reloaded, err := f.app.FindRecordById(util.Coll.Identities, identity.Id)
		if err != nil {
			t.Fatal(err)
		}
		if reloaded.GetString(i.SealedKey) != "" || reloaded.GetString(i.SealedKeyScope) != "" {
			t.Fatal("an identity kept a key nobody can open")
		}
	})
}

func TestMembersDeviceListsAreServedToMembersOnly(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	member := addWorkspaceMember(t, f)
	path := "/api/sealed/workspaces/" + f.party.workspace + "/members"

	members := f.request("GET", path, member.token, nil).Expect().
		Status(http.StatusOK).JSON().Object().Value("members").Array()
	members.Length().IsEqual(2)
	var owner *httpexpect.Object
	for _, m := range members.Iter() {
		o := m.Object()
		if o.Value("user").String().Raw() == f.party.id {
			owner = o
		}
	}
	if owner == nil {
		t.Fatal("the owner's list is missing")
	}
	owner.Value("isSelf").IsEqual(false)
	owner.Value("canRead").IsEqual(true)
	devices := owner.Value("devices").Array()
	devices.Length().IsEqual(2)
	devices.Value(0).Object().Value("hpkePublicKey").IsEqual(encodeSealed(f.chain.Entry(1).HpkePublicKey))

	// Public keys only: nothing a member could use to open anything.
	body := f.request("GET", path, member.token, nil).Expect().Body().Raw()
	if strings.Contains(body, sealedKeyWrap) || strings.Contains(body, "wraps") {
		t.Fatal("the member list carries key material")
	}

	outsider := newContactParty(t, f.baseURL)
	f.request("GET", path, outsider.token, nil).Expect().Status(http.StatusNotFound)
	f.request("GET", path, "", nil).Expect().Status(http.StatusUnauthorized)
}

// grantTo hands the owner's current key to one of a member's devices, signed by
// the owner's first device over what the member's list holds now.
func (f *sealedFixture) grantTo(recipient *sealedFixture, epoch, deviceSeq int) map[string]any {
	wrap := sealedKeyWrap
	payload := util.SealedGrantPayload(f.party.workspace, epoch, recipient.party.id,
		recipient.chain.Entry(deviceSeq).HpkePublicKey, wrap, f.party.id,
		f.chain.HeadSeq(), recipient.chain.HeadSeq())
	return map[string]any{
		"user": recipient.party.id, "deviceSeq": deviceSeq, "wrap": wrap,
		"signerSeq": 1, "chainSeq": f.chain.HeadSeq(), "recipientChainSeq": recipient.chain.HeadSeq(),
		"signature": encodeSealed(f.signers[1].signRaw(payload)),
	}
}

func (f *sealedFixture) grant(token string, epoch int, grants ...map[string]any) *httpexpect.Response {
	f.t.Helper()
	list := []any{}
	for _, g := range grants {
		list = append(list, g)
	}
	return f.request("POST", "/api/sealed/workspaces/"+f.party.workspace+"/grants", token,
		map[string]any{"epoch": epoch, "grants": list}).Expect()
}

// newGrantFixture is an owner with a key in their workspace and a member with a
// device list of their own.
func newGrantFixture(t *testing.T) (*sealedFixture, *sealedFixture) {
	f := newSealedFixture(t)
	f.enroll()
	member := sealedFixtureFor(t, f.baseURL, f.app, addWorkspaceMember(t, f))
	member.enroll()
	return f, member
}

func TestGrantingTheWorkspaceKey(t *testing.T) {
	t.Run("hands the key to a member's devices", func(t *testing.T) {
		f, member := newGrantFixture(t)
		f.grant(f.party.token, 1, f.grantTo(member, 1, 1), f.grantTo(member, 1, 2)).
			Status(http.StatusOK).JSON().Object().Value("granted").Array().IsEqual([]any{member.party.id})

		if !services.HoldsWorkspaceKey(f.app, f.party.workspace, member.party.id, 1) {
			t.Fatal("the member holds no key")
		}
		var ws *httpexpect.Object
		for _, w := range f.request("GET", "/api/sealed/state", member.party.token, nil).Expect().
			JSON().Object().Value("workspaces").Array().Iter() {
			if w.Object().Value("workspace").String().Raw() == f.party.workspace {
				ws = w.Object()
			}
		}
		if ws == nil {
			t.Fatal("the member's state does not name the workspace")
		}
		ws.Value("wraps").Array().Value(0).Object().Value("granter").IsEqual(f.party.id)

		// The member can now write encrypted records here.
		member.request("POST", "/api/sealed/records", member.party.token, sealedBody(1, map[string]any{
			"id": newSealedID(), "key": "granted", "label": "granted", "type": "text", "format": "default",
			"workspace": f.party.workspace,
		})).Expect().Status(http.StatusOK)

		f.grant(f.party.token, 1, f.grantTo(member, 1, 1)).Status(http.StatusConflict)
	})

	t.Run("only someone who can invite may grant", func(t *testing.T) {
		f, member := newGrantFixture(t)
		other := sealedFixtureFor(t, f.baseURL, f.app, addWorkspaceMember(t, f))
		other.enroll()
		f.grant(f.party.token, 1, f.grantTo(member, 1, 1), f.grantTo(member, 1, 2)).Status(http.StatusOK)
		// The member holds the key now, but cannot bring anyone in.
		member.party.workspace = f.party.workspace
		member.grant(member.party.token, 1, member.grantTo(other, 1, 1)).Status(http.StatusForbidden)
	})

	t.Run("only to someone who can read the vault", func(t *testing.T) {
		f, member := newGrantFixture(t)
		m := util.Fields.WorkspaceMember
		row, _ := f.app.FindFirstRecordByFilter(util.Coll.WorkspaceMembers,
			m.Workspace+" = {:w} && "+m.User+" = {:u}", dbx.Params{"w": f.party.workspace, "u": member.party.id})
		noVault, _ := util.ExpandPermissions([]string{util.PermSharesRead})
		row.Set(m.Permissions, noVault)
		if err := f.app.Save(row); err != nil {
			t.Fatal(err)
		}
		f.grant(f.party.token, 1, f.grantTo(member, 1, 1)).Status(http.StatusForbidden)
	})

	t.Run("never to an outsider, oneself, or a dead device", func(t *testing.T) {
		f, member := newGrantFixture(t)
		outsider := sealedFixtureFor(t, f.baseURL, f.app, newContactParty(t, f.baseURL))
		outsider.enroll()
		f.grant(f.party.token, 1, f.grantTo(outsider, 1, 1)).Status(http.StatusForbidden)

		self := f.grantTo(f, 1, 1)
		f.grant(f.party.token, 1, self).Status(http.StatusBadRequest)

		removal := member.removal(2)
		member.accept(removal, nil)
		member.request("POST", "/api/sealed/devices", member.party.token, map[string]any{
			"entries": []any{sealedEntryJSON(removal)},
		}).Expect().Status(http.StatusOK)
		f.grant(f.party.token, 1, f.grantTo(member, 1, 2)).Status(http.StatusBadRequest)
	})

	t.Run("a copy signed for someone else does not land", func(t *testing.T) {
		f, member := newGrantFixture(t)
		other := sealedFixtureFor(t, f.baseURL, f.app, addWorkspaceMember(t, f))
		other.enroll()
		g := f.grantTo(member, 1, 1)
		g["user"] = other.party.id
		f.grant(f.party.token, 1, g).Status(http.StatusBadRequest)
	})

	t.Run("not under an old key or one that must be replaced", func(t *testing.T) {
		f, member := newGrantFixture(t)
		f.grant(f.party.token, 2, f.grantTo(member, 2, 1)).Status(http.StatusConflict)
		if err := services.MarkKeyRotationDue(f.app, f.party.workspace); err != nil {
			t.Fatal(err)
		}
		f.grant(f.party.token, 1, f.grantTo(member, 1, 1)).Status(http.StatusConflict)
	})

	t.Run("not while an identity key is still under the workspace key", func(t *testing.T) {
		f, member := newGrantFixture(t)
		identities, _ := f.app.FindCollectionByNameOrId(util.Coll.Identities)
		i := util.Fields.Identity
		identity := core.NewRecord(identities)
		identity.Set(i.Name, "Signer")
		identity.Set(i.Certificate, "stand-in certificate")
		identity.Set(i.PublicKey, "stand-in public key")
		identity.Set(i.Fingerprint, newSealedID())
		identity.Set(i.User, f.party.id)
		identity.Set(i.Workspace, f.party.workspace)
		identity.Set(i.Status, util.StatusActive)
		identity.Set(i.SealedKey, sealedCiphertext)
		identity.Set(i.SealedKeyEpoch, 1)
		if err := f.app.Save(identity); err != nil {
			t.Fatal(err)
		}
		f.grant(f.party.token, 1, f.grantTo(member, 1, 1)).Status(http.StatusConflict).
			JSON().Object().Value("code").IsEqual(util.Errors.SealedIdentityKeysPending.ErrorCode)

		identity.Set(i.SealedKeyScope, util.SealedKeyScopeAccount)
		if err := f.app.Save(identity); err != nil {
			t.Fatal(err)
		}
		f.grant(f.party.token, 1, f.grantTo(member, 1, 1)).Status(http.StatusOK)
	})

	t.Run("a new key can carry the members along", func(t *testing.T) {
		f, member := newGrantFixture(t)
		f.grant(f.party.token, 1, f.grantTo(member, 1, 1), f.grantTo(member, 1, 2)).Status(http.StatusOK)
		wraps := []any{f.wrapTo(f.party.workspace, 2, 1), f.wrapTo(f.party.workspace, 2, 2)}
		f.request("POST", "/api/sealed/workspaces/"+f.party.workspace+"/epochs", f.party.token, map[string]any{
			"epoch": 2, "priorWrap": sealedKeyWrap, "wraps": wraps,
			"grants": []any{f.grantTo(member, 2, 1), f.grantTo(member, 2, 2)},
		}).Expect().Status(http.StatusOK)
		if !services.HoldsWorkspaceKey(f.app, f.party.workspace, member.party.id, 2) {
			t.Fatal("the member was left behind by the new key")
		}
	})

	t.Run("the member list says who holds the key", func(t *testing.T) {
		f, member := newGrantFixture(t)
		path := "/api/sealed/workspaces/" + f.party.workspace + "/members"
		holds := func() map[string]bool {
			out := map[string]bool{}
			for _, m := range f.request("GET", path, f.party.token, nil).Expect().
				JSON().Object().Value("members").Array().Iter() {
				o := m.Object()
				out[o.Value("user").String().Raw()] = o.Value("holdsKey").Boolean().Raw()
			}
			return out
		}
		if h := holds(); !h[f.party.id] || h[member.party.id] {
			t.Fatalf("before the grant: %v", h)
		}
		f.grant(f.party.token, 1, f.grantTo(member, 1, 1)).Status(http.StatusOK)
		if h := holds(); !h[member.party.id] {
			t.Fatalf("after the grant: %v", h)
		}
	})
}
