package tests

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
)

// The server never opens an encrypted file, so random bytes in the blob's
// shape stand in for one (design/e2ee-sharing.md §7.2). Under test: that only
// ciphertext is ever stored or served for it, that nothing the client named
// survives, that a file never changes state without its blob changing too,
// and that stamped links and tool reads keep away from it.
func sealedBlob(t *testing.T, n int) []byte {
	t.Helper()
	raw := make([]byte, n)
	if _, err := rand.Read(raw); err != nil {
		t.Fatal(err)
	}
	raw[0] = 1
	return raw
}

// sealedMultipart sends a sealed write the way the app sends a file: the
// usual JSON in `meta`, the blob beside it.
func (f *sealedFixture) sealedMultipart(method, path string, meta map[string]any, name string, blob []byte) *httpexpect.Response {
	f.t.Helper()
	raw, err := json.Marshal(meta)
	if err != nil {
		f.t.Fatal(err)
	}
	return testutils.NewExpect(f.t, f.baseURL).Request(method, path).
		WithHeader("Authorization", f.party.token).
		WithMultipart().
		WithFormField("meta", string(raw)).
		WithFileBytes("blob", name, blob).
		Expect()
}

func (f *sealedFixture) createSealedFile(key string, blob []byte) string {
	f.t.Helper()
	id := newSealedID()
	f.sealedMultipart("POST", "/api/sealed/records", sealedBody(1, map[string]any{
		"id": id, "key": key, "label": key, "type": util.TypeFile, "format": "default",
		"workspace": f.party.workspace,
	}), "Lohnabrechnung-Oktober.pdf", blob).Status(http.StatusOK).
		JSON().Object().Value("sealed").IsEqual(true)
	return id
}

func (f *sealedFixture) storedBytes(id string) []byte {
	f.t.Helper()
	rec, err := f.app.FindRecordById(util.Coll.Records, id)
	if err != nil {
		f.t.Fatal(err)
	}
	fsys, err := f.app.NewFilesystem()
	if err != nil {
		f.t.Fatal(err)
	}
	defer fsys.Close()
	r, err := fsys.GetReader(rec.BaseFilesPath() + "/" + rec.GetString(util.Fields.Record.File))
	if err != nil {
		f.t.Fatal(err)
	}
	defer r.Close()
	var buf bytes.Buffer
	if _, err := buf.ReadFrom(r); err != nil {
		f.t.Fatal(err)
	}
	return buf.Bytes()
}

func TestASealedFileKeepsNothingItsClientNamed(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	blob := sealedBlob(t, 3000)
	id := f.createSealedFile("payslip", blob)

	rec, _ := f.app.FindRecordById(util.Coll.Records, id)
	r := util.Fields.Record
	if rec.GetString(r.Filename) != "" || rec.GetString(r.ContentHash) != "" || rec.GetString(r.HashSalt) != "" {
		t.Fatalf("the server kept what it learned from the upload: %v", rec.PublicExport())
	}
	if rec.GetString(r.Mime) != "application/octet-stream" || rec.GetInt(r.Size) != len(blob) {
		t.Fatalf("mime %q size %d", rec.GetString(r.Mime), rec.GetInt(r.Size))
	}
	stored := rec.GetString(r.File)
	if !strings.HasPrefix(stored, "encrypted_") || strings.Contains(strings.ToLower(stored), "lohn") {
		t.Fatalf("stored as %q", stored)
	}
	if !bytes.Equal(f.storedBytes(id), blob) {
		t.Fatal("the stored blob differs from the upload")
	}
	assertStoredValueEmpty(t, f.app, id)
}

func TestASealedFileNeedsItsBlob(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	meta := func(typ string) map[string]any {
		return sealedBody(1, map[string]any{
			"id": newSealedID(), "key": "doc", "label": "doc", "type": typ, "format": "default",
			"workspace": f.party.workspace,
		})
	}
	invalid := util.Errors.SealedInvalid.ErrorCode

	t.Run("a file without one", func(t *testing.T) {
		f.request("POST", "/api/sealed/records", f.party.token, meta(util.TypeFile)).
			Expect().Status(http.StatusBadRequest).JSON().Object().Value("code").IsEqual(invalid)
	})
	t.Run("a blob on something that is not a file", func(t *testing.T) {
		f.sealedMultipart("POST", "/api/sealed/records", meta(util.TypeText), "x.bin", sealedBlob(t, 3000)).
			Status(http.StatusBadRequest).JSON().Object().Value("code").IsEqual(invalid)
	})
	t.Run("a blob too short to be one", func(t *testing.T) {
		f.sealedMultipart("POST", "/api/sealed/records", meta(util.TypeFile), "x.bin", sealedBlob(t, 100)).
			Status(http.StatusBadRequest)
	})
	t.Run("a blob in another format", func(t *testing.T) {
		blob := sealedBlob(t, 3000)
		blob[0] = 2
		f.sealedMultipart("POST", "/api/sealed/records", meta(util.TypeFile), "x.bin", blob).
			Status(http.StatusBadRequest)
	})
	t.Run("plaintext, which starts like anything", func(t *testing.T) {
		f.sealedMultipart("POST", "/api/sealed/records", meta(util.TypeFile), "cv.pdf",
			[]byte("%PDF-1.4 "+strings.Repeat(plainCanary, 100))).
			Status(http.StatusBadRequest)
	})
}

func TestTheCollectionAPICannotReplaceASealedFile(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	blob := sealedBlob(t, 3000)
	id := f.createSealedFile("payslip", blob)

	testutils.NewExpect(t, f.baseURL).PATCH("/api/collections/"+util.Coll.Records+"/records/"+id).
		WithHeader("Authorization", f.party.token).
		WithMultipart().
		WithFileBytes(util.Fields.Record.File, "cv.pdf", []byte(plainCanary)).
		Expect().Status(http.StatusBadRequest)
	testutils.NewPBClient(t, f.baseURL).Update(util.Coll.Records, id, f.party.token, map[string]any{
		util.Fields.Record.Filename: "cv.pdf",
	}).Expect().Status(http.StatusBadRequest)

	if !bytes.Equal(f.storedBytes(id), blob) {
		t.Fatal("the blob was replaced")
	}
}

func TestEncryptingAPlainFileReplacesIt(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	api := testutils.NewPBClient(t, f.baseURL)
	id := uploadFileRecord(api, f.party.token, fileRecordFields(f.party.id, f.party.workspace, "cv"),
		"cv.pdf", []byte("%PDF-1.4 "+plainCanary)).Status(http.StatusOK).JSON().Object().Value("id").String().Raw()

	t.Run("not without the encrypted copy", func(t *testing.T) {
		f.request("PUT", "/api/sealed/records/"+id, f.party.token, f.put(id, 1, map[string]any{"expectedVersion": 0})).
			Expect().Status(http.StatusBadRequest)
		if !strings.Contains(string(f.storedBytes(id)), plainCanary) {
			t.Fatal("the plain file was touched by a refused write")
		}
	})

	blob := sealedBlob(t, 3000)
	t.Run("with it, in one write", func(t *testing.T) {
		f.sealedMultipart("PUT", "/api/sealed/records/"+id, f.put(id, 1, map[string]any{"expectedVersion": 0}),
			"cv.pdf", blob).Status(http.StatusOK)
		rec, _ := f.app.FindRecordById(util.Coll.Records, id)
		r := util.Fields.Record
		if !rec.GetBool(r.Sealed) || rec.GetString(r.ContentHash) != "" || rec.GetString(r.Filename) != "" {
			t.Fatalf("still describes the plain file: %v", rec.PublicExport())
		}
		if !bytes.Equal(f.storedBytes(id), blob) {
			t.Fatal("the plain file is still stored")
		}
	})

	t.Run("a rename keeps the blob", func(t *testing.T) {
		f.request("PUT", "/api/sealed/records/"+id, f.party.token,
			f.put(id, 1, map[string]any{"expectedVersion": 1, "label": "Lebenslauf"})).
			Expect().Status(http.StatusOK)
		if !bytes.Equal(f.storedBytes(id), blob) {
			t.Fatal("a rename replaced the blob")
		}
	})

	t.Run("a file stays a file", func(t *testing.T) {
		f.request("PUT", "/api/sealed/records/"+id, f.party.token,
			f.put(id, 1, map[string]any{"expectedVersion": 2, "type": util.TypeText})).
			Expect().Status(http.StatusBadRequest)
	})

	t.Run("and nothing else gains a blob", func(t *testing.T) {
		text := f.createSealed("note")
		f.sealedMultipart("PUT", "/api/sealed/records/"+text, f.put(text, 1, map[string]any{"expectedVersion": 1}),
			"x.bin", sealedBlob(t, 3000)).Status(http.StatusBadRequest)
	})
}

func TestStopEncryptingAFileSignsItsContent(t *testing.T) {
	f := newSealedFixture(t)
	f.enroll()
	id := f.createSealedFile("payslip", sealedBlob(t, 3000))
	plain := []byte("%PDF-1.4 back in the clear")
	sum := sha256.Sum256(plain)

	unseal := func(signed []byte, value string) *httpexpect.Response {
		body := f.unsealBody(id, 1, "file:"+hex.EncodeToString(signed))
		body["value"] = value
		body["filename"] = "Abrechnung.pdf"
		return f.sealedMultipart("POST", "/api/sealed/records/"+id+"/unseal", body, "upload.pdf", plain)
	}

	t.Run("a signature over other content is refused", func(t *testing.T) {
		other := sha256.Sum256([]byte("something else"))
		unseal(other[:], "").Status(http.StatusForbidden)
	})
	t.Run("a value alongside the file is refused", func(t *testing.T) {
		unseal(sum[:], "text").Status(http.StatusBadRequest)
	})
	t.Run("a file needs its file", func(t *testing.T) {
		f.request("POST", "/api/sealed/records/"+id+"/unseal", f.party.token, f.unsealBody(id, 1, "text")).
			Expect().Status(http.StatusBadRequest)
	})
	t.Run("the signed content goes back in the clear", func(t *testing.T) {
		unseal(sum[:], "").Status(http.StatusOK)
		rec, _ := f.app.FindRecordById(util.Coll.Records, id)
		r := util.Fields.Record
		if rec.GetBool(r.Sealed) || rec.GetString(r.Filename) != "Abrechnung.pdf" ||
			rec.GetString(r.ContentHash) == "" || rec.GetString(r.SealedValue) != "" {
			t.Fatalf("not a plain file again: %v", rec.PublicExport())
		}
		if !bytes.Equal(f.storedBytes(id), plain) {
			t.Fatal("the blob is still stored")
		}
	})
}

func TestALinkHandsOutASealedFileAsItsBlob(t *testing.T) {
	f, _, _, slug, linkID := newSealedLinkFixture(t)
	blob := sealedBlob(t, 5000)
	id := f.createSealedFile("payslip", blob)
	f.sealOnLink(linkID, id, 1)

	records, raw := publicRecords(t, f.baseURL, slug)
	entry := sealedEntryOf(records, id)
	if entry == nil {
		t.Fatalf("the encrypted file is missing: %s", raw)
	}
	entry.Value("sealed").IsEqual(true)
	entry.NotContainsKey("filename")
	entry.NotContainsKey("mime")
	entry.NotContainsKey("value")
	token := entry.Value("downloadToken").String().NotEmpty().Raw()
	if strings.Contains(raw, "Lohnabrechnung") {
		t.Fatal("the upload's name reached the public read")
	}
	// Only plain files go into the server's zip; this link has none.
	resp := testutils.NewPBClient(t, f.baseURL).E.POST("/api/public/links/" + slug).
		WithJSON(map[string]any{}).Expect().Status(http.StatusOK).JSON().Object()
	resp.NotContainsKey("archiveToken")

	got := testutils.NewExpect(t, f.baseURL).GET("/api/public/links/"+slug+"/files/"+id).
		WithQuery("dl", token).Expect().Status(http.StatusOK)
	got.Header("Content-Type").IsEqual("application/octet-stream")
	got.Header("Content-Disposition").Contains(util.SealedFileName)
	if !bytes.Equal([]byte(got.Body().Raw()), blob) {
		t.Fatal("the download is not the blob")
	}
}

func TestStampedLinksTakeNoSealedFile(t *testing.T) {
	f, _, _, _, linkID := newSealedLinkFixture(t)
	id := f.createSealedFile("payslip", sealedBlob(t, 3000))
	api := testutils.NewPBClient(t, f.baseURL)

	t.Run("onto a stamped link", func(t *testing.T) {
		api.Update(util.Coll.Links, linkID, f.party.token, map[string]any{util.Fields.Link.Watermark: true}).
			Expect().Status(http.StatusOK)
		f.putLink(f.party.token, linkID, map[string]any{
			"seals": []any{map[string]any{
				"record": id, "version": 1, "viewerWrap": f.viewerWrap(), "writerWrap": f.writerWrap(),
			}},
			"keyWraps": f.ownerKeyWrap(),
		}).Status(http.StatusBadRequest).JSON().Object().Value("code").IsEqual(util.Errors.SealedFileWatermark.ErrorCode)
	})

	t.Run("nor stamping a link that has one", func(t *testing.T) {
		api.Update(util.Coll.Links, linkID, f.party.token, map[string]any{util.Fields.Link.Watermark: false}).
			Expect().Status(http.StatusOK)
		f.sealOnLink(linkID, id, 1)
		api.Update(util.Coll.Links, linkID, f.party.token, map[string]any{util.Fields.Link.Watermark: true}).
			Expect().Status(http.StatusBadRequest)
	})
}
