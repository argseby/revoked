package tests

import (
	"archive/zip"
	"bytes"
	"image/png"
	"io"
	"net/http"
	"sort"
	"strings"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
	"github.com/google/uuid"
)

func (f watermarkFixture) preview(token string, body map[string]any) *httpexpect.Response {
	req := f.api.E.POST("/api/stamp-preview").WithJSON(body)
	if token != "" {
		req = req.WithHeader("Authorization", token)
	}
	return req.Expect()
}

func (f watermarkFixture) section(t *testing.T, records ...string) string {
	t.Helper()
	return f.api.Create(util.Coll.Sections, f.token, map[string]any{
		util.Fields.Section.Key:       "docs_" + uuid.New().String()[:6],
		util.Fields.Section.Name:      "Documents",
		util.Fields.Section.Workspace: f.wsID,
		util.Fields.Section.User:      f.userID,
		util.Fields.Section.Records:   records,
	}).Expect().Status(http.StatusOK).JSON().Object().Value("id").String().Raw()
}

// unzip returns the archive's entries by name.
func unzip(t *testing.T, data []byte) map[string][]byte {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		t.Fatalf("response is not a zip: %v", err)
	}
	out := map[string][]byte{}
	for _, f := range zr.File {
		if f.Method != zip.Deflate {
			t.Fatalf("entry %q is not deflated", f.Name)
		}
		r, err := f.Open()
		if err != nil {
			t.Fatal(err)
		}
		b, err := io.ReadAll(r)
		r.Close()
		if err != nil {
			t.Fatal(err)
		}
		out[f.Name] = b
	}
	return out
}

func entryNames(entries map[string][]byte) []string {
	names := make([]string, 0, len(entries))
	for n := range entries {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

func TestStampPreviewWithText(t *testing.T) {
	f := newWatermarkFixture(t)

	t.Run("an image comes back stamped under a preview name", func(t *testing.T) {
		resp := f.preview(f.token, map[string]any{"record": f.pngID, "text": "Nur für Hausverwaltung Schmidt"}).
			Status(http.StatusOK)
		resp.Header("Content-Type").IsEqual("image/png")
		resp.Header("Content-Disposition").IsEqual(`attachment; filename="ausweis-preview.png"; filename*=UTF-8''ausweis-preview.png`)
		resp.Header("Cache-Control").IsEqual("no-store")
		resp.Header("X-Content-Type-Options").IsEqual("nosniff")
		got := []byte(resp.Body().Raw())
		if bytes.Equal(got, f.pngBytes) {
			t.Fatal("the preview is the unstamped original")
		}
		if _, err := png.Decode(bytes.NewReader(got)); err != nil {
			t.Fatalf("stamped preview does not decode: %v", err)
		}
	})

	t.Run("a PDF comes back stamped", func(t *testing.T) {
		resp := f.preview(f.token, map[string]any{"record": f.pdfID, "text": "Preview"}).Status(http.StatusOK)
		resp.Header("Content-Type").IsEqual("application/pdf")
		resp.Header("Content-Disposition").Contains("gehalt-preview.pdf")
		got := []byte(resp.Body().Raw())
		if bytes.Equal(got, f.pdfBytes) {
			t.Fatal("the preview is the unstamped original")
		}
		if pages, err := pdfPageCount(got); err != nil || pages != 1 {
			t.Fatalf("stamped PDF: pages=%d err=%v", pages, err)
		}
	})

	t.Run("a file that cannot be stamped is refused", func(t *testing.T) {
		f.preview(f.token, map[string]any{"record": f.textID, "text": "Preview"}).
			Status(http.StatusUnsupportedMediaType).JSON().Object().
			Value("code").String().IsEqual(util.Errors.FileNotWatermarkable.ErrorCode)
	})

	t.Run("text that is not one short line is rejected", func(t *testing.T) {
		for _, text := range []string{"", "   ", "first\nsecond", "tab\there", strings.Repeat("x", 121)} {
			f.preview(f.token, map[string]any{"record": f.pngID, "text": text}).
				Status(http.StatusBadRequest).JSON().Object().
				Value("code").String().IsEqual(util.Errors.WatermarkTextInvalid.ErrorCode)
		}
		f.preview(f.token, map[string]any{"record": f.pngID, "text": strings.Repeat("ü", 120)}).
			Status(http.StatusOK)
	})

	t.Run("someone else's record is not found", func(t *testing.T) {
		baseURL, _ := testutils.SetupTestApp(t)
		_, otherToken, err := testutils.CreateRandomUser(baseURL)
		if err != nil {
			t.Fatal(err)
		}
		f.preview(otherToken, map[string]any{"record": f.pngID, "text": "Preview"}).
			Status(http.StatusNotFound).JSON().Object().
			Value("code").String().IsEqual(util.Errors.RecordNotFound.ErrorCode)
		f.preview(f.token, map[string]any{"record": "doesnotexist123", "text": "Preview"}).
			Status(http.StatusNotFound).JSON().Object().
			Value("code").String().IsEqual(util.Errors.RecordNotFound.ErrorCode)
	})

	t.Run("a record that is not a file is not found", func(t *testing.T) {
		baseURL, _ := testutils.SetupTestApp(t)
		textRecord := extractID(t, baseURL, util.Coll.Records, f.token, map[string]any{
			util.Fields.Record.Key:       "plain_" + uuid.New().String()[:6],
			util.Fields.Record.Value:     "value",
			util.Fields.Record.Label:     "Plain",
			util.Fields.Record.Type:      util.TypeText,
			util.Fields.Record.Format:    util.FormatDefault,
			util.Fields.Record.User:      f.userID,
			util.Fields.Record.Workspace: f.wsID,
		})
		f.preview(f.token, map[string]any{"record": textRecord, "text": "Preview"}).
			Status(http.StatusNotFound)
	})

	t.Run("without a session", func(t *testing.T) {
		f.preview("", map[string]any{"record": f.pngID, "text": "Preview"}).
			Status(http.StatusUnauthorized).JSON().Object().
			Value("code").String().IsEqual(util.Errors.NotAuthenticated.ErrorCode)
	})
}

func TestStampPreviewWithLink(t *testing.T) {
	f := newWatermarkFixture(t)
	_, pngOnly := f.share(t, map[string]any{
		util.Fields.Link.Watermark: true,
		util.Fields.Link.Records:   []string{f.pngID},
	})

	t.Run("a record the link grants is stamped with the link's line", func(t *testing.T) {
		f.preview(f.token, map[string]any{"record": f.pngID, "link": pngOnly}).
			Status(http.StatusOK).Header("Content-Type").IsEqual("image/png")
	})

	t.Run("a record the link does not grant is not found", func(t *testing.T) {
		f.preview(f.token, map[string]any{"record": f.pdfID, "link": pngOnly}).
			Status(http.StatusNotFound).JSON().Object().
			Value("code").String().IsEqual(util.Errors.RecordNotFound.ErrorCode)
	})

	t.Run("a record only in one of the link's sections is not granted", func(t *testing.T) {
		_, viaSection := f.share(t, map[string]any{
			util.Fields.Link.Records:  []string{},
			util.Fields.Link.Sections: []string{f.section(t, f.pdfID)},
		})
		f.preview(f.token, map[string]any{"record": f.pdfID, "link": viaSection}).
			Status(http.StatusNotFound).JSON().Object().
			Value("code").String().IsEqual(util.Errors.RecordNotFound.ErrorCode)
	})

	t.Run("someone else's link is not found", func(t *testing.T) {
		other := newWatermarkFixture(t)
		_, foreign := other.share(t, nil)
		f.preview(f.token, map[string]any{"record": f.pngID, "link": foreign}).
			Status(http.StatusNotFound).JSON().Object().
			Value("code").String().IsEqual(util.Errors.LinkNotFound.ErrorCode)
	})
}

func (f watermarkFixture) ownerArchive(token, linkID string) *httpexpect.Response {
	req := f.api.E.GET("/api/links/" + linkID + "/archive")
	if token != "" {
		req = req.WithHeader("Authorization", token)
	}
	return req.Expect()
}

func TestOwnerArchive(t *testing.T) {
	f := newWatermarkFixture(t)

	t.Run("a watermarked link zips stamped copies and skips what cannot be stamped", func(t *testing.T) {
		_, linkID := f.share(t, map[string]any{util.Fields.Link.Watermark: true})
		resp := f.ownerArchive(f.token, linkID).Status(http.StatusOK)
		resp.Header("Content-Type").IsEqual("application/zip")
		resp.Header("Content-Disposition").IsEqual(`attachment; filename="Wohnungsbewerbung Musterstr. 5.zip"; filename*=UTF-8''Wohnungsbewerbung%20Musterstr.%205.zip`)
		resp.Header("Cache-Control").IsEqual("no-store")
		resp.Header("X-Content-Type-Options").IsEqual("nosniff")

		entries := unzip(t, []byte(resp.Body().Raw()))
		if names := entryNames(entries); strings.Join(names, ",") != "ausweis.png,gehalt.pdf" {
			t.Fatalf("entries = %v, want the image and the PDF only", names)
		}
		if bytes.Equal(entries["gehalt.pdf"], f.pdfBytes) || bytes.Equal(entries["ausweis.png"], f.pngBytes) {
			t.Fatal("an original went into a watermarked archive")
		}
		if pages, err := pdfPageCount(entries["gehalt.pdf"]); err != nil || pages != 1 {
			t.Fatalf("stamped PDF entry: pages=%d err=%v", pages, err)
		}

		f.api.Get(util.Coll.Links, linkID, f.token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Link.ViewCount).Number().IsEqual(0)
	})

	// A section only groups records on the page; the zip must not reach a file
	// the resolve itself would not serve.
	t.Run("an unwatermarked link zips its own originals, names deduplicated", func(t *testing.T) {
		twin := uploadFileRecord(f.api, f.token, fileRecordFields(f.userID, f.wsID, "payslip_2"), "gehalt.pdf", testutils.MinimalPDF(2)).
			Status(http.StatusOK).JSON().Object().Value("id").String().Raw()
		hidden := uploadFileRecord(f.api, f.token, fileRecordFields(f.userID, f.wsID, "payslip_3"), "hidden.pdf", testutils.MinimalPDF(1)).
			Status(http.StatusOK).JSON().Object().Value("id").String().Raw()
		_, linkID := f.share(t, map[string]any{
			util.Fields.Link.Records:  []string{f.pngID, f.pdfID, f.textID, twin},
			util.Fields.Link.Sections: []string{f.section(t, hidden, f.pdfID)},
		})
		entries := unzip(t, []byte(f.ownerArchive(f.token, linkID).Status(http.StatusOK).Body().Raw()))
		if names := entryNames(entries); strings.Join(names, ",") != "ausweis.png,gehalt (2).pdf,gehalt.pdf,notes.txt" {
			t.Fatalf("entries = %v", names)
		}
		if !bytes.Equal(entries["gehalt.pdf"], f.pdfBytes) || !bytes.Equal(entries["ausweis.png"], f.pngBytes) {
			t.Fatal("an unwatermarked archive altered a file")
		}
	})

	t.Run("a watermarked link with nothing stampable has no archive", func(t *testing.T) {
		_, linkID := f.share(t, map[string]any{
			util.Fields.Link.Watermark: true,
			util.Fields.Link.Records:   []string{f.textID},
		})
		f.ownerArchive(f.token, linkID).Status(http.StatusNotFound).JSON().Object().
			Value("code").String().IsEqual(util.Errors.ArchiveEmpty.ErrorCode)
	})

	t.Run("someone else's link is not found", func(t *testing.T) {
		_, linkID := f.share(t, nil)
		other := newWatermarkFixture(t)
		f.ownerArchive(other.token, linkID).Status(http.StatusNotFound).JSON().Object().
			Value("code").String().IsEqual(util.Errors.LinkNotFound.ErrorCode)
		f.ownerArchive("", linkID).Status(http.StatusUnauthorized)
	})
}

func (f watermarkFixture) publicArchive(slug, token string) *httpexpect.Response {
	return f.api.E.GET("/api/public/links/"+slug+"/archive").WithQuery("dl", token).Expect()
}

func TestLandlordArchive(t *testing.T) {
	f := newWatermarkFixture(t)

	t.Run("the resolve's archive token opens a stamped zip once", func(t *testing.T) {
		slug, _ := f.share(t, applicationFields())
		body, _ := f.resolve(slug)
		token, _ := body["archiveToken"].(string)
		if token == "" {
			t.Fatal("a share with files resolved without an archiveToken")
		}

		resp := f.publicArchive(slug, token).Status(http.StatusOK)
		resp.Header("Content-Type").IsEqual("application/zip")
		resp.Header("Cache-Control").IsEqual("no-store")
		entries := unzip(t, []byte(resp.Body().Raw()))
		if names := entryNames(entries); strings.Join(names, ",") != "ausweis.png,gehalt.pdf" {
			t.Fatalf("entries = %v, want the unstampable file left out", names)
		}
		if bytes.Equal(entries["gehalt.pdf"], f.pdfBytes) {
			t.Fatal("the landlord archive carried the unstamped PDF")
		}

		f.publicArchive(slug, token).Status(http.StatusUnauthorized).JSON().Object().
			Value("code").String().IsEqual(util.Errors.FileDownloadInvalid.ErrorCode)
	})

	t.Run("a token is bound to its share and is no file token", func(t *testing.T) {
		slug, _ := f.share(t, nil)
		other, _ := f.share(t, nil)
		body, fileTokens := f.resolve(slug)
		f.publicArchive(other, body["archiveToken"].(string)).Status(http.StatusUnauthorized)
		f.publicArchive(slug, fileTokens[f.pngID]).Status(http.StatusUnauthorized)
		f.publicArchive(slug, "").Status(http.StatusUnauthorized)
	})

	t.Run("an unwatermarked share zips originals", func(t *testing.T) {
		slug, _ := f.share(t, nil)
		body, _ := f.resolve(slug)
		entries := unzip(t, []byte(f.publicArchive(slug, body["archiveToken"].(string)).Status(http.StatusOK).Body().Raw()))
		if len(entries) != 3 || !bytes.Equal(entries["gehalt.pdf"], f.pdfBytes) {
			t.Fatalf("entries = %v, want all three originals", entryNames(entries))
		}
	})

	t.Run("a share without files gets no archive token", func(t *testing.T) {
		baseURL, _ := testutils.SetupTestApp(t)
		slug, _ := pageShare(t, baseURL, f.token, f.userID, f.wsID, nil)
		body := f.api.E.POST("/api/public/links/" + slug).Expect().Status(http.StatusOK).JSON().Object().Raw()
		if _, ok := body["archiveToken"]; ok {
			t.Fatal("a share without files carried an archiveToken")
		}
	})

	t.Run("the page offers the download", func(t *testing.T) {
		slug, _ := f.share(t, applicationFields())
		page := f.api.E.GET("/s/"+slug).WithHeader("Accept", browserAccept).
			Expect().Status(http.StatusOK).Body().Raw()
		for _, hook := range []string{"data.archiveToken", "Download all", "/archive?dl="} {
			if !strings.Contains(page, hook) {
				t.Fatalf("the page lacks %q", hook)
			}
		}
	})
}
