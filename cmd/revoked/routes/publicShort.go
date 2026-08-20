package routes

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/url"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"strings"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// PublicShortRoute exposes a short capability URL so any no-code consumer can pull a
// link's live value with zero credentials. The slug IS the credential; revocation is
// what makes that safe.
//
//	GET /s/{slug}[.json|.txt|.csv|.vcf|.ics]   whole link in the chosen format
//	GET /s/{slug}[.csv]?key=phone              one value
//	GET /s/{slug}?password=PW                  unlock a password-protected link
//
// Format is chosen by path suffix, else the Accept header, else JSON.
func PublicShortRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/s/{slug}", func(re *core.RequestEvent) error {
			slug, format := splitLinkFormat(re.Request.PathValue("slug"))
			return serveLinkData(app, re, slug, format)
		})
		return e.Next()
	})
}

// A single shared attribute, resolved to its current value.
type linkField struct {
	key, value, label, ftype string
	updated                  time.Time
}

// splitLinkFormat peels a known format suffix off the slug, for tools that cannot set
// an Accept header.
func splitLinkFormat(raw string) (slug, format string) {
	lower := strings.ToLower(raw)
	for _, ext := range []string{".json", ".csv", ".txt", ".vcf", ".ics"} {
		if strings.HasSuffix(lower, ext) {
			return raw[:len(raw)-len(ext)], ext[1:]
		}
	}
	return raw, ""
}

// resolveFormat still honors the legacy ?raw flag, ranked below an explicit suffix.
func resolveFormat(suffix string, q url.Values, accept string) string {
	if suffix != "" {
		return suffix
	}
	if q.Get("raw") != "" {
		return "txt"
	}
	a := strings.ToLower(accept)
	switch {
	case strings.Contains(a, "text/csv"):
		return "csv"
	case strings.Contains(a, "text/calendar"):
		return "ics"
	case strings.Contains(a, "text/vcard"), strings.Contains(a, "text/x-vcard"):
		return "vcf"
	case strings.Contains(a, "text/plain"):
		return "txt"
	default:
		return "json"
	}
}

func serveLinkData(app core.App, re *core.RequestEvent, slug, suffix string) error {
	if !allowRequest(re, probeLimiter, "") {
		return rateLimitedResponse(re)
	}
	link, err := app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:slug}", map[string]any{"slug": slug})
	if err != nil || link == nil {
		return re.NotFoundError(util.Errors.LinkNotFound.ErrorText, nil)
	}
	if appErr := services.RefreshLinkStatus(app, link); appErr != nil {
		return resourceErrorResponse(re, appErr)
	}

	q := re.Request.URL.Query()
	format := resolveFormat(suffix, q, re.Request.Header.Get("Accept"))

	// Handshake-gated links can't be unlocked from a plain URL.
	if link.GetBool(util.Fields.Link.RequireHandshake) {
		return re.JSON(http.StatusForbidden, map[string]any{
			"slug": slug, "protected": true, "requireHandshake": true,
			"message": "This link requires a verified identity. Open it in the Revoked app.",
		})
	}
	// Password gate; ?password= is accepted for browser use.
	if hash := link.GetString(util.Fields.Link.Password); hash != "" {
		if !allowRequest(re, gatePasswordLimiter, slug) {
			return rateLimitedResponse(re)
		}
		if pw := q.Get("password"); pw == "" || !util.VerifyPassword(hash, pw) {
			return re.JSON(http.StatusForbidden, map[string]any{
				"slug": slug, "protected": true, "requiresPassword": true,
				"message": "This link is password-protected. Add ?password=YOUR_PASSWORD to view it.",
			})
		}
		gatePasswordLimiter.Reset(rateLimitKey(re, slug))
	}

	fields := collectLinkFields(app, link)
	updatedAt := linkUpdatedAt(link, fields)
	verified := link.GetString(util.Fields.Link.Identity) != ""
	key := q.Get("key")

	// A stable ETag (values + updated_at + selection + format) lets pollers
	// revalidate to a cheap 304 until the value actually changes.
	etag := linkETag(slug, format, key, fields, updatedAt)
	h := re.Response.Header()
	h.Set("ETag", etag)
	h.Set("Cache-Control", "max-age=60")
	if !updatedAt.IsZero() {
		h.Set("Last-Modified", updatedAt.UTC().Format(http.TimeFormat))
	}
	if inm := re.Request.Header.Get("If-None-Match"); inm != "" &&
		(strings.Contains(inm, etag) || strings.TrimSpace(inm) == "*") {
		re.Response.WriteHeader(http.StatusNotModified)
		return nil
	}

	// A served value counts against the view cap (304s above don't); losing the
	// claim means a concurrent reader took the last view.
	if !countLinkView(app, link) {
		return resourceErrorResponse(re, &util.Errors.LinkMaxViewsReached)
	}

	if key != "" {
		idx := indexOfField(fields, key)
		if idx < 0 {
			if format == "json" {
				return re.JSON(http.StatusNotFound, map[string]any{
					"slug": slug, "key": key,
					"message": "This link has no shared value with that key.",
				})
			}
			return re.NotFoundError("No shared value with that key.", nil)
		}
		f := fields[idx]
		switch format {
		case "txt":
			return writePlain(re, f.value)
		case "csv":
			return writeText(re, "text/csv", csvRow([]string{f.key})+csvRow([]string{f.value}))
		case "vcf":
			return writeText(re, "text/vcard", vCard(link, []linkField{f}, updatedAt))
		case "ics":
			return writeText(re, "text/calendar", iCalendar(link, []linkField{f}))
		default:
			return re.JSON(http.StatusOK, map[string]any{
				"slug": slug, "key": f.key, "value": f.value,
				"updated_at": iso(updatedAt), "verified": verified,
			})
		}
	}

	// A file has no text projection, but it stays in `fields` above so the
	// ETag and Last-Modified still move when a file is replaced.
	textFields := withoutFiles(fields)

	switch format {
	case "txt":
		var b strings.Builder
		for _, f := range textFields {
			b.WriteString(f.key + ": " + f.value + "\n")
		}
		return writePlain(re, b.String())
	case "csv":
		keys := make([]string, len(textFields))
		vals := make([]string, len(textFields))
		for i, f := range textFields {
			keys[i] = f.key
			vals[i] = f.value
		}
		return writeText(re, "text/csv", csvRow(keys)+csvRow(vals))
	case "vcf":
		return writeText(re, "text/vcard", vCard(link, textFields, updatedAt))
	case "ics":
		return writeText(re, "text/calendar", iCalendar(link, textFields))
	default:
		records := []map[string]any{}
		for _, id := range link.GetStringSlice(util.Fields.Link.Records) {
			if rec, err := app.FindRecordById(util.Coll.Records, id); err == nil {
				entry := sanitizeRecord(rec)
				if rec.GetString(util.Fields.Record.Type) == util.TypeFile {
					if token, tokenErr := issueDownloadToken(slug, rec.Id); tokenErr == nil {
						entry["downloadToken"] = token
					}
				}
				records = append(records, entry)
			}
		}
		sections := []map[string]any{}
		for _, id := range link.GetStringSlice(util.Fields.Link.Sections) {
			if rec, err := app.FindRecordById(util.Coll.Sections, id); err == nil {
				sections = append(sections, sanitizeRecord(rec))
			}
		}
		return re.JSON(http.StatusOK, map[string]any{
			"slug": slug, "label": link.GetString(util.Fields.Link.Label),
			"records": records, "sections": sections,
			"updated_at": iso(updatedAt), "verified": verified,
			"viewCount": link.GetInt(util.Fields.Link.ViewCount),
		})
	}
}

// collectLinkFields resolves the link's top-level records and the records inside
// any shared section into a flat, ordered list of current values.
func collectLinkFields(app core.App, link *core.Record) []linkField {
	out := []linkField{}
	add := func(rec *core.Record) {
		out = append(out, linkField{
			key:     rec.GetString("key"),
			value:   rec.GetString("value"),
			label:   rec.GetString("label"),
			ftype:   rec.GetString("type"),
			updated: rec.GetDateTime("updated").Time(),
		})
	}
	for _, id := range link.GetStringSlice(util.Fields.Link.Records) {
		if rec, err := app.FindRecordById(util.Coll.Records, id); err == nil && rec != nil {
			add(rec)
		}
	}
	for _, sid := range link.GetStringSlice(util.Fields.Link.Sections) {
		if sec, err := app.FindRecordById(util.Coll.Sections, sid); err == nil && sec != nil {
			for _, rid := range sec.GetStringSlice("records") {
				if rec, err := app.FindRecordById(util.Coll.Records, rid); err == nil && rec != nil {
					add(rec)
				}
			}
		}
	}
	return out
}

// withoutFiles drops file records from a text projection; bytes travel only
// through the claimed download endpoint.
func withoutFiles(fields []linkField) []linkField {
	out := make([]linkField, 0, len(fields))
	for _, f := range fields {
		if f.ftype != util.TypeFile {
			out = append(out, f)
		}
	}
	return out
}

func indexOfField(fields []linkField, key string) int {
	for i, f := range fields {
		if f.key == key {
			return i
		}
	}
	return -1
}

// linkUpdatedAt reflects when the shared values last changed, deliberately not the
// link's own `updated` — that bumps on every view-count save and would break ETag
// stability across reads.
func linkUpdatedAt(_ *core.Record, fields []linkField) time.Time {
	var t time.Time
	for _, f := range fields {
		if f.updated.After(t) {
			t = f.updated
		}
	}
	return t
}

func iso(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format(time.RFC3339)
}

func linkETag(slug, format, key string, fields []linkField, updatedAt time.Time) string {
	h := sha256.New()
	h.Write([]byte(slug + "|" + format + "|" + key + "|" + updatedAt.UTC().String()))
	for _, f := range fields {
		h.Write([]byte("\x1f" + f.key + "=" + f.value))
	}
	return `"` + hex.EncodeToString(h.Sum(nil)[:16]) + `"`
}

func writePlain(re *core.RequestEvent, body string) error {
	return writeText(re, "text/plain", body)
}

func writeText(re *core.RequestEvent, mime, body string) error {
	re.Response.Header().Set("Content-Type", mime+"; charset=utf-8")
	re.Response.WriteHeader(http.StatusOK)
	_, _ = re.Response.Write([]byte(body))
	return nil
}

func csvRow(cols []string) string {
	out := make([]string, len(cols))
	for i, c := range cols {
		if strings.ContainsAny(c, ",\"\n\r") {
			out[i] = `"` + strings.ReplaceAll(c, `"`, `""`) + `"`
		} else {
			out[i] = c
		}
	}
	return strings.Join(out, ",") + "\n"
}

// vCard builds a VERSION:3.0 card, mapping recognized keys to standard fields
// and dropping anything else into NOTE so no data is lost.
func vCard(link *core.Record, fields []linkField, updatedAt time.Time) string {
	var fn, given, family, email, tel, org, adr string
	var notes []string
	for _, f := range fields {
		switch normKey(f.key) {
		case "name", "fullname", "full_name", "fn", "displayname", "display_name":
			fn = f.value
		case "firstname", "first_name", "givenname", "given_name", "given":
			given = f.value
		case "lastname", "last_name", "surname", "familyname", "family_name", "family":
			family = f.value
		case "email", "mail", "emailaddress", "email_address":
			email = f.value
		case "phone", "tel", "telephone", "mobile", "phonenumber", "phone_number", "number":
			tel = f.value
		case "org", "organization", "organisation", "company":
			org = f.value
		case "address", "adr":
			adr = f.value
		default:
			if f.value != "" {
				notes = append(notes, (firstNonEmpty(f.label, f.key))+": "+f.value)
			}
		}
	}
	if fn == "" {
		fn = strings.TrimSpace(given + " " + family)
	}
	if fn == "" {
		fn = firstNonEmpty(link.GetString(util.Fields.Link.Label), "Revoked contact")
	}
	var b strings.Builder
	b.WriteString("BEGIN:VCARD\r\nVERSION:3.0\r\n")
	b.WriteString("UID:" + link.GetString(util.Fields.Link.Slug) + "\r\n")
	b.WriteString("FN:" + vEscape(fn) + "\r\n")
	b.WriteString("N:" + vEscape(family) + ";" + vEscape(given) + ";;;\r\n")
	if email != "" {
		b.WriteString("EMAIL:" + vEscape(email) + "\r\n")
	}
	if tel != "" {
		b.WriteString("TEL:" + vEscape(tel) + "\r\n")
	}
	if org != "" {
		b.WriteString("ORG:" + vEscape(org) + "\r\n")
	}
	if adr != "" {
		b.WriteString("ADR:;;" + vEscape(adr) + ";;;;\r\n")
	}
	if len(notes) > 0 {
		b.WriteString("NOTE:" + vEscape(strings.Join(notes, "\n")) + "\r\n")
	}
	if !updatedAt.IsZero() {
		b.WriteString("REV:" + updatedAt.UTC().Format("20060102T150405Z") + "\r\n")
	}
	b.WriteString("END:VCARD\r\n")
	return b.String()
}

// iCalendar emits an all-day VEVENT for each field whose value parses as a date.
func iCalendar(link *core.Record, fields []linkField) string {
	var b strings.Builder
	b.WriteString("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Revoked//Live Value//EN\r\nMETHOD:PUBLISH\r\n")
	for _, f := range fields {
		d := parseDate(f.value)
		if d.IsZero() {
			continue
		}
		next := d.AddDate(0, 0, 1)
		b.WriteString("BEGIN:VEVENT\r\n")
		b.WriteString("UID:" + link.GetString(util.Fields.Link.Slug) + "-" + f.key + "@revoked\r\n")
		b.WriteString("SUMMARY:" + vEscape(firstNonEmpty(f.label, f.key)) + "\r\n")
		b.WriteString("DTSTART;VALUE=DATE:" + d.Format("20060102") + "\r\n")
		b.WriteString("DTEND;VALUE=DATE:" + next.Format("20060102") + "\r\n")
		b.WriteString("END:VEVENT\r\n")
	}
	b.WriteString("END:VCALENDAR\r\n")
	return b.String()
}

func parseDate(v string) time.Time {
	for _, layout := range []string{"2006-01-02", "2006/01/02", "02.01.2006", "01/02/2006", time.RFC3339} {
		if t, err := time.Parse(layout, strings.TrimSpace(v)); err == nil {
			return t
		}
	}
	return time.Time{}
}

func normKey(k string) string {
	return strings.ReplaceAll(strings.ToLower(strings.TrimSpace(k)), " ", "")
}

func firstNonEmpty(a, b string) string {
	if strings.TrimSpace(a) != "" {
		return a
	}
	return b
}

func vEscape(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, ";", `\;`)
	s = strings.ReplaceAll(s, ",", `\,`)
	s = strings.ReplaceAll(s, "\r\n", `\n`)
	s = strings.ReplaceAll(s, "\n", `\n`)
	return s
}

// countLinkView atomically claims one access against the link's view cap, auto-revoking
// at the cap. Returns false when the cap was already consumed — the caller must then
// withhold the data.
func countLinkView(app core.App, link *core.Record) bool {
	_, revokedByLimit, err := services.ClaimLinkView(app, link)
	if err != nil {
		return false
	}
	if revokedByLimit {
		services.EmitNotification(app, link.GetString(util.Fields.Link.User),
			link.GetString(util.Fields.Link.Workspace),
			util.NotificationLinkMaxViews,
			"Link reached max views",
			"Link "+link.GetString(util.Fields.Link.Slug)+" was auto-revoked after reaching its max views.",
			util.Coll.Links, link.Id)
	}
	return true
}
