package routes

import (
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"strings"
	"sync"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/filesystem"
)

// downloadTTL bounds how long a minted token stays redeemable. The view claim
// was already spent at resolve, so the window only covers the client turning
// around to fetch the bytes.
const downloadTTL = 2 * time.Minute

// downloadStore is deliberately in-process, like the challenge registry: tokens
// are single-use and short-lived, so losing them on restart only costs the
// viewer a fresh resolve. Horizontal scaling requires a shared store.
var downloadStore = &downloadRegistry{entries: make(map[string]downloadEntry)}

type downloadEntry struct {
	Slug      string
	RecordId  string
	ExpiresAt time.Time
}

type downloadRegistry struct {
	mu      sync.Mutex
	entries map[string]downloadEntry
}

func (r *downloadRegistry) issue(slug, recordId string) (string, error) {
	token, err := util.GenerateToken(32)
	if err != nil {
		return "", err
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	r.gcLocked()
	r.entries[token] = downloadEntry{Slug: slug, RecordId: recordId, ExpiresAt: time.Now().Add(downloadTTL)}
	return token, nil
}

// consume removes the token as it checks it, so one is never redeemed twice.
func (r *downloadRegistry) consume(token, slug, recordId string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	entry, ok := r.entries[token]
	if !ok {
		return false
	}
	delete(r.entries, token)
	if time.Now().After(entry.ExpiresAt) {
		return false
	}
	return entry.Slug == slug && entry.RecordId == recordId
}

func (r *downloadRegistry) gcLocked() {
	now := time.Now()
	for t, e := range r.entries {
		if now.After(e.ExpiresAt) {
			delete(r.entries, t)
		}
	}
}

// issueDownloadToken is called by the resolve handler after its atomic view
// claim; the token is the only public path to the bytes.
func issueDownloadToken(slug, recordId string) (string, error) {
	return downloadStore.issue(slug, recordId)
}

// archiveTokenTarget stands in for a record id on a token that opens the
// link's whole archive. Record ids are alphanumeric, so it names none of them.
const archiveTokenTarget = "*archive"

func issueArchiveToken(slug string) (string, error) {
	return downloadStore.issue(slug, archiveTokenTarget)
}

// PublicFilesRoute streams a file record's bytes against a single-use token
// minted at resolve time. The resolve is where every gate and the view claim
// ran; the download is the tail of that same, already-granted read — a text
// value delivered in the resolve body cannot be recalled either, so the bytes
// follow the same rule. Revocation gates the next resolve, and a link that
// auto-revoked by reaching its cap must not strangle the claim that spent it.
func PublicFilesRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/public/links/{slug}/files/{recordId}", func(re *core.RequestEvent) error {
			if !allowRequest(re, probeLimiter, "") {
				return rateLimitedResponse(re)
			}
			slug := re.Request.PathValue("slug")
			recordId := re.Request.PathValue("recordId")

			if token := re.Request.URL.Query().Get("dl"); token == "" || !downloadStore.consume(token, slug, recordId) {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.FileDownloadInvalid)
			}

			rec, err := app.FindRecordById(util.Coll.Records, recordId)
			if err != nil || rec == nil || rec.GetString(util.Fields.Record.Type) != util.TypeFile {
				return re.NotFoundError(util.Errors.LinkNotFound.ErrorText, nil)
			}
			filename := rec.GetString(util.Fields.Record.File)
			if filename == "" {
				return re.NotFoundError(util.Errors.LinkNotFound.ErrorText, nil)
			}

			fsys, err := app.NewFilesystem()
			if err != nil {
				return re.InternalServerError("Failed to open storage.", err)
			}
			defer fsys.Close()

			// The reader gets the name the owner gave the record, not the
			// snakecased and suffixed one PocketBase stores it under.
			downloadName := rec.GetString(util.Fields.Record.Filename)
			if downloadName == "" {
				downloadName = filename
			}

			link, err := app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:slug}", dbx.Params{"slug": slug})
			if err != nil || link == nil {
				return re.NotFoundError(util.Errors.LinkNotFound.ErrorText, nil)
			}
			if link.GetBool(util.Fields.Link.Watermark) {
				return serveWatermarked(re, fsys, rec.BaseFilesPath()+"/"+filename, downloadName,
					services.WatermarkLine(link, time.Now()))
			}

			// Always an attachment, never sniffed: an uploaded HTML file served
			// inline from this origin would be stored XSS on the operator's
			// domain. Serve only fills headers that are not already set.
			re.Response.Header().Set("Content-Disposition", attachmentDisposition(downloadName))
			re.Response.Header().Set("X-Content-Type-Options", "nosniff")
			if mime := rec.GetString(util.Fields.Record.Mime); mime != "" {
				re.Response.Header().Set("Content-Type", mime)
			}
			return fsys.Serve(re.Response, re.Request, rec.BaseFilesPath()+"/"+filename, filename)
		})

		// Every file the share grants in one download, under the same
		// single-use token rule as a single file.
		e.Router.GET("/api/public/links/{slug}/archive", func(re *core.RequestEvent) error {
			if !allowRequest(re, probeLimiter, "") {
				return rateLimitedResponse(re)
			}
			slug := re.Request.PathValue("slug")
			if token := re.Request.URL.Query().Get("dl"); token == "" || !downloadStore.consume(token, slug, archiveTokenTarget) {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.FileDownloadInvalid)
			}
			link, err := app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:slug}", dbx.Params{"slug": slug})
			if err != nil || link == nil {
				return re.NotFoundError(util.Errors.LinkNotFound.ErrorText, nil)
			}
			return serveLinkArchive(re, app, link, services.LinkFileRecords(app, link))
		})

		return e.Next()
	})
}

// serveWatermarked sends a stamped copy of a stored file. Any file that cannot
// be stamped is refused: a watermarked share never falls back to handing out
// the unmarked original.
func serveWatermarked(re *core.RequestEvent, fsys *filesystem.System, key, downloadName, line string) error {
	refuse := func() error {
		return appErrorResponse(re, http.StatusUnsupportedMediaType, &util.Errors.FileNotWatermarkable)
	}
	r, err := fsys.GetReader(key)
	if err != nil {
		return re.NotFoundError(util.Errors.LinkNotFound.ErrorText, nil)
	}
	defer r.Close()
	data, err := io.ReadAll(io.LimitReader(r, services.MaxWatermarkInputBytes+1))
	if err != nil || len(data) > services.MaxWatermarkInputBytes {
		return refuse()
	}
	stamped, err := services.WatermarkFile(data, line)
	if err != nil {
		return refuse()
	}

	name := strings.TrimSuffix(downloadName, filepath.Ext(downloadName)) + stamped.Ext
	h := re.Response.Header()
	h.Set("Content-Disposition", attachmentDisposition(name))
	h.Set("X-Content-Type-Options", "nosniff")
	// Each copy carries the day it was read, so no cache may hand it out again.
	h.Set("Cache-Control", "no-store")
	return re.Blob(http.StatusOK, stamped.Mime, stamped.Bytes)
}

// sanitizeFilename keeps a stored filename safe inside a quoted
// Content-Disposition value.
func sanitizeFilename(name string) string {
	name = strings.ReplaceAll(name, `"`, "")
	name = strings.ReplaceAll(name, "\r", "")
	name = strings.ReplaceAll(name, "\n", "")
	return name
}

// attachmentDisposition names a download so every browser gets it right. A
// browser reads a quoted filename's raw bytes as Latin-1, which turns "Köln"
// into "KÃ¶ln"; the RFC 6266 filename* carries the real UTF-8 name, and the
// quoted value is an ASCII fallback for clients that ignore it.
func attachmentDisposition(name string) string {
	name = sanitizeFilename(name)
	return `attachment; filename="` + asciiFilename(name) + `"; filename*=UTF-8''` + encodeExtValue(name)
}

var germanASCII = strings.NewReplacer("ä", "ae", "ö", "oe", "ü", "ue", "Ä", "Ae", "Ö", "Oe", "Ü", "Ue", "ß", "ss")

func asciiFilename(name string) string {
	return strings.Map(func(r rune) rune {
		if r < 0x20 || r > 0x7e || r == '\\' {
			return '_'
		}
		return r
	}, germanASCII.Replace(name))
}

// encodeExtValue percent-encodes everything outside RFC 5987's attr-char.
func encodeExtValue(s string) string {
	var b strings.Builder
	for _, c := range []byte(s) {
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9',
			strings.IndexByte("!#$&+-.^_`|~", c) >= 0:
			b.WriteByte(c)
		default:
			fmt.Fprintf(&b, "%%%02X", c)
		}
	}
	return b.String()
}

// serveLinkArchive streams files as the link's zip, stamped when the link is
// watermarked.
func serveLinkArchive(re *core.RequestEvent, app core.App, link *core.Record, files []*core.Record) error {
	line := ""
	if link.GetBool(util.Fields.Link.Watermark) {
		line = services.WatermarkLine(link, time.Now())
	}
	name := link.GetString(util.Fields.Link.Label)
	if strings.TrimSpace(name) == "" {
		name = link.GetString(util.Fields.Link.Slug)
	}
	out := &archiveResponse{re: re, name: sanitizeFilename(services.SafeFileName(name)) + ".zip"}

	written, err := services.WriteLinkArchive(app, files, line, out)
	if err != nil {
		app.Logger().Error("Failed to write link archive", "error", err, "link", link.Id)
		if !out.started {
			return re.InternalServerError("Failed to build the archive.", nil)
		}
		return nil
	}
	if written == 0 {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.ArchiveEmpty)
	}
	return nil
}

// archiveResponse sends the headers with the first byte of the zip, so an
// archive that ends up empty can still be answered with an error.
type archiveResponse struct {
	re      *core.RequestEvent
	name    string
	started bool
}

func (a *archiveResponse) Write(p []byte) (int, error) {
	if !a.started {
		a.started = true
		h := a.re.Response.Header()
		h.Set("Content-Type", "application/zip")
		h.Set("Content-Disposition", attachmentDisposition(a.name))
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Cache-Control", "no-store")
		a.re.Response.WriteHeader(http.StatusOK)
	}
	return a.re.Response.Write(p)
}
