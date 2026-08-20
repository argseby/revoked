package routes

import (
	"net/http"
	"revoked/util"
	"strings"
	"sync"
	"time"

	"github.com/pocketbase/pocketbase/core"
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

			// Always an attachment, never sniffed: an uploaded HTML file served
			// inline from this origin would be stored XSS on the operator's
			// domain. Serve only fills headers that are not already set.
			re.Response.Header().Set("Content-Disposition", `attachment; filename="`+sanitizeFilename(filename)+`"`)
			re.Response.Header().Set("X-Content-Type-Options", "nosniff")
			if mime := rec.GetString(util.Fields.Record.Mime); mime != "" {
				re.Response.Header().Set("Content-Type", mime)
			}
			return fsys.Serve(re.Response, re.Request, rec.BaseFilesPath()+"/"+filename, filename)
		})

		return e.Next()
	})
}

// sanitizeFilename keeps a stored filename safe inside a quoted
// Content-Disposition value.
func sanitizeFilename(name string) string {
	name = strings.ReplaceAll(name, `"`, "")
	name = strings.ReplaceAll(name, "\r", "")
	name = strings.ReplaceAll(name, "\n", "")
	return name
}
