package tests

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"strings"
	"testing"

	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/google/uuid"
	"github.com/pdfcpu/pdfcpu/pkg/api"
)

func whitePNG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 400, 300))
	for y := 0; y < 300; y++ {
		for x := 0; x < 400; x++ {
			img.Set(x, y, color.White)
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

type watermarkFixture struct {
	api                  *testutils.PBClient
	userID, token, wsID  string
	pngID, pdfID, textID string
	pngBytes, pdfBytes   []byte
}

func newWatermarkFixture(t *testing.T) watermarkFixture {
	baseURL, _ := testutils.SetupTestApp(t)
	f := watermarkFixture{api: testutils.NewPBClient(t, baseURL)}
	var err error
	f.userID, f.token, err = testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	f.wsID = activeWorkspaceOf(t, f.api, f.userID, f.token)

	upload := func(key, name string, content []byte) string {
		return uploadFileRecord(f.api, f.token, fileRecordFields(f.userID, f.wsID, key), name, content).
			Status(http.StatusOK).JSON().Object().Value("id").String().Raw()
	}
	f.pngBytes = whitePNG(t)
	f.pdfBytes = testutils.MinimalPDF(1)
	f.pngID = upload("id_scan", "ausweis.png", f.pngBytes)
	f.pdfID = upload("payslip", "gehalt.pdf", f.pdfBytes)
	f.textID = upload("notes", "notes.txt", []byte("plain text cannot carry a stamp"))
	return f
}

func (f watermarkFixture) share(t *testing.T, extra map[string]any) (slug, id string) {
	t.Helper()
	slug = "wm-" + uuid.New().String()[:8]
	body := map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Wohnungsbewerbung Musterstr. 5",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      f.userID,
		util.Fields.Link.Workspace: f.wsID,
		util.Fields.Link.Records:   []string{f.pngID, f.pdfID, f.textID},
	}
	for k, v := range extra {
		body[k] = v
	}
	resp := f.api.Create(util.Coll.Links, f.token, body).Expect().Status(http.StatusOK).JSON().Object()
	return slug, resp.Value("id").String().Raw()
}

// resolve reveals the share and returns its body plus a download token per file.
func (f watermarkFixture) resolve(slug string) (map[string]any, map[string]string) {
	body := f.api.E.POST("/api/public/links/" + slug).Expect().Status(http.StatusOK).JSON().Object().Raw()
	tokens := map[string]string{}
	for _, r := range body["records"].([]any) {
		rec := r.(map[string]any)
		if tok, ok := rec["downloadToken"].(string); ok {
			tokens[rec["id"].(string)] = tok
		}
	}
	return body, tokens
}

func (f watermarkFixture) download(slug, recordID, token string) *http.Response {
	return f.api.E.GET("/api/public/links/"+slug+"/files/"+recordID).
		WithQuery("dl", token).Expect().Raw()
}

func TestWatermarkedShareStampsEveryFileItServes(t *testing.T) {
	f := newWatermarkFixture(t)
	slug, linkID := f.share(t, map[string]any{util.Fields.Link.Watermark: true})

	f.api.E.GET("/api/public/links/" + slug).Expect().Status(http.StatusOK).
		JSON().Object().Value("watermarked").Boolean().IsTrue()

	body, tokens := f.resolve(slug)
	line, _ := body["watermark"].(string)
	if !strings.Contains(line, "Wohnungsbewerbung Musterstr. 5") ||
		!strings.Contains(line, "#"+services.WatermarkTag(linkID)) {
		t.Fatalf("watermark line %q lacks the label or the share tag", line)
	}

	t.Run("an image comes back stamped, same size, never cached", func(t *testing.T) {
		api := f.api.T(t)
		resp := api.E.GET("/api/public/links/"+slug+"/files/"+f.pngID).
			WithQuery("dl", tokens[f.pngID]).Expect().Status(http.StatusOK)
		resp.Header("Content-Type").IsEqual("image/png")
		resp.Header("Cache-Control").IsEqual("no-store")
		resp.Header("Content-Disposition").Contains("ausweis.png")
		got := []byte(resp.Body().Raw())
		if bytes.Equal(got, f.pngBytes) {
			t.Fatal("the original image was served unstamped")
		}
		img, err := png.Decode(bytes.NewReader(got))
		if err != nil {
			t.Fatalf("stamped image does not decode: %v", err)
		}
		if b := img.Bounds(); b.Dx() != 400 || b.Dy() != 300 {
			t.Fatalf("stamped image is %v, want 400x300", b)
		}
	})

	t.Run("a PDF comes back stamped with its pages intact", func(t *testing.T) {
		api := f.api.T(t)
		resp := api.E.GET("/api/public/links/"+slug+"/files/"+f.pdfID).
			WithQuery("dl", tokens[f.pdfID]).Expect().Status(http.StatusOK)
		resp.Header("Content-Type").IsEqual("application/pdf")
		got := []byte(resp.Body().Raw())
		if bytes.Equal(got, f.pdfBytes) {
			t.Fatal("the original PDF was served unstamped")
		}
		pages, err := pdfPageCount(got)
		if err != nil || pages != 1 {
			t.Fatalf("stamped PDF: pages=%d err=%v", pages, err)
		}
	})

	t.Run("a file that cannot be stamped is refused, not served plain", func(t *testing.T) {
		api := f.api.T(t)
		api.E.GET("/api/public/links/"+slug+"/files/"+f.textID).
			WithQuery("dl", tokens[f.textID]).Expect().
			Status(http.StatusUnsupportedMediaType).JSON().Object().
			Value("code").String().IsEqual(util.Errors.FileNotWatermarkable.ErrorCode)
	})
}

func TestUnwatermarkedShareServesOriginals(t *testing.T) {
	f := newWatermarkFixture(t)
	slug, _ := f.share(t, nil)

	body, tokens := f.resolve(slug)
	if _, ok := body["watermark"]; ok {
		t.Fatal("an unwatermarked share must not carry a watermark line")
	}
	resp := f.download(slug, f.pngID, tokens[f.pngID])
	defer resp.Body.Close()
	var got bytes.Buffer
	got.ReadFrom(resp.Body)
	if resp.StatusCode != http.StatusOK || !bytes.Equal(got.Bytes(), f.pngBytes) {
		t.Fatalf("status %d, original served: %v", resp.StatusCode, bytes.Equal(got.Bytes(), f.pngBytes))
	}
}

func TestWatermarkTextReplacesTheLabelAndStaysOneLine(t *testing.T) {
	f := newWatermarkFixture(t)
	slug, _ := f.share(t, map[string]any{
		util.Fields.Link.Watermark:     true,
		util.Fields.Link.WatermarkText: "Nur für Hausverwaltung Schmidt",
	})
	body, _ := f.resolve(slug)
	if line, _ := body["watermark"].(string); !strings.HasPrefix(line, "Nur für Hausverwaltung Schmidt · ") {
		t.Fatalf("watermark line %q does not start with the custom text", line)
	}

	f.api.Create(util.Coll.Links, f.token, map[string]any{
		util.Fields.Link.Slug:          "wm-" + uuid.New().String()[:8],
		util.Fields.Link.Label:         "Two lines",
		util.Fields.Link.Status:        util.StatusActive,
		util.Fields.Link.User:          f.userID,
		util.Fields.Link.Workspace:     f.wsID,
		util.Fields.Link.Watermark:     true,
		util.Fields.Link.WatermarkText: "first\nsecond",
	}).Expect().Status(http.StatusBadRequest)
}

func pdfPageCount(pdf []byte) (int, error) {
	return api.PageCount(bytes.NewReader(pdf), nil)
}
