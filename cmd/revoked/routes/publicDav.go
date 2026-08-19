package routes

import (
	"net/http"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"strings"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/hook"
)

// PublicDavRoute exposes a read-only, single-card CardDAV addressbook per link at
// /dav/s/{slug}/ (card at contact.vcf), so a contacts app can subscribe and stay in
// sync. The collection is its own principal and home so a client resolves it without
// wandering; gated links (password or handshake) are never exposed over DAV.
func PublicDavRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		// PocketBase's CORS middleware answers OPTIONS with 204 before routing,
		// hiding the DAV capability header clients probe for, so this must run
		// ahead of it.
		e.Router.Bind(&hook.Handler[*core.RequestEvent]{
			Id:       "davOptions",
			Priority: -1000000,
			Func: func(re *core.RequestEvent) error {
				if re.Request.Method == http.MethodOptions &&
					strings.HasPrefix(re.Request.URL.Path, "/dav/") {
					re.Response.Header().Set("DAV", "1, 2, 3, addressbook")
					re.Response.Header().Set("Allow", "OPTIONS, GET, HEAD, PROPFIND, REPORT")
					re.Response.WriteHeader(http.StatusOK)
					return nil
				}
				return re.Next()
			},
		})
		e.Router.Any("/dav/s/{slug}", func(re *core.RequestEvent) error {
			return davHandler(app, re, re.Request.PathValue("slug"), "")
		})
		e.Router.Any("/dav/s/{slug}/{file...}", func(re *core.RequestEvent) error {
			return davHandler(app, re, re.Request.PathValue("slug"), re.Request.PathValue("file"))
		})
		return e.Next()
	})
}

const (
	davNS    = `xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav" xmlns:cs="http://calendarserver.org/ns/"`
	cardFile = "contact.vcf"
)

func davHandler(app core.App, re *core.RequestEvent, slug, file string) error {
	link, err := app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:slug}", map[string]any{"slug": slug})
	if err != nil || link == nil {
		return re.NotFoundError("Address book not found.", nil)
	}
	if appErr := services.RefreshLinkStatus(app, link); appErr != nil {
		return re.NotFoundError("This address book is no longer available.", nil)
	}
	// DAV can't unlock gated links — only open links are exposed.
	if link.GetString(util.Fields.Link.Password) != "" || link.GetBool(util.Fields.Link.RequireHandshake) {
		return re.ForbiddenError("This link is protected and not available over CardDAV.", nil)
	}

	isCard := file != "" && file != "/"
	collectionHref := "/dav/s/" + slug + "/"
	cardHref := collectionHref + cardFile

	fields := collectLinkFields(app, link)
	updatedAt := linkUpdatedAt(link, fields)
	etag := linkETag(slug, "vcf", "", fields, updatedAt)
	ctag := etag

	switch re.Request.Method {
	case http.MethodOptions:
		re.Response.Header().Set("DAV", "1, 2, 3, addressbook")
		re.Response.Header().Set("Allow", "OPTIONS, GET, HEAD, PROPFIND, REPORT")
		re.Response.WriteHeader(http.StatusOK)
		return nil

	case http.MethodGet, http.MethodHead:
		if !isCard {
			return re.NotFoundError("Not a card.", nil)
		}
		re.Response.Header().Set("ETag", etag)
		re.Response.Header().Set("DAV", "1, 2, 3, addressbook")
		re.Response.Header().Set("Content-Type", "text/vcard; charset=utf-8")
		re.Response.WriteHeader(http.StatusOK)
		if re.Request.Method == http.MethodGet {
			_, _ = re.Response.Write([]byte(vCard(link, fields, updatedAt)))
		}
		return nil

	case "PROPFIND":
		depth := re.Request.Header.Get("Depth")
		var b strings.Builder
		if isCard {
			b.WriteString(davCardResponse(cardHref, etag, "", false))
		} else {
			b.WriteString(davCollectionResponse(collectionHref, link.GetString(util.Fields.Link.Label), ctag))
			if depth == "1" || depth == "infinity" {
				b.WriteString(davCardResponse(cardHref, etag, "", false))
			}
		}
		return writeMultistatus(re, b.String())

	case "REPORT":
		// addressbook-query / addressbook-multiget.
		return writeMultistatus(re, davCardResponse(cardHref, etag, vCard(link, fields, updatedAt), true))

	case http.MethodPut, http.MethodDelete, "PROPPATCH", "MKCOL", "MKCALENDAR", "COPY", "MOVE":
		return re.ForbiddenError("This address book is read-only.", nil)

	default:
		re.Response.Header().Set("Allow", "OPTIONS, GET, HEAD, PROPFIND, REPORT")
		re.Response.WriteHeader(http.StatusMethodNotAllowed)
		return nil
	}
}

func writeMultistatus(re *core.RequestEvent, body string) error {
	re.Response.Header().Set("Content-Type", "application/xml; charset=utf-8")
	re.Response.Header().Set("DAV", "1, 2, 3, addressbook")
	re.Response.WriteHeader(http.StatusMultiStatus)
	_, _ = re.Response.Write([]byte(
		`<?xml version="1.0" encoding="utf-8"?>` + "\n" +
			`<d:multistatus ` + davNS + `>` + body + `</d:multistatus>`,
	))
	return nil
}

func davCollectionResponse(href, displayName, ctag string) string {
	return `<d:response><d:href>` + xmlEscape(href) + `</d:href><d:propstat><d:prop>` +
		`<d:resourcetype><d:collection/><card:addressbook/></d:resourcetype>` +
		`<d:displayname>` + xmlEscape(firstNonEmpty(displayName, "Revoked")) + `</d:displayname>` +
		`<d:current-user-principal><d:href>` + xmlEscape(href) + `</d:href></d:current-user-principal>` +
		`<card:addressbook-home-set><d:href>` + xmlEscape(href) + `</d:href></card:addressbook-home-set>` +
		`<cs:getctag>` + xmlEscape(ctag) + `</cs:getctag>` +
		`<d:supported-report-set>` +
		`<d:supported-report><d:report><card:addressbook-query/></d:report></d:supported-report>` +
		`<d:supported-report><d:report><card:addressbook-multiget/></d:report></d:supported-report>` +
		`</d:supported-report-set>` +
		`</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>`
}

func davCardResponse(href, etag, vcardData string, includeData bool) string {
	prop := `<d:getetag>` + xmlEscape(etag) + `</d:getetag>` +
		`<d:getcontenttype>text/vcard; charset=utf-8</d:getcontenttype>` +
		`<d:resourcetype/>`
	if includeData {
		prop += `<card:address-data>` + xmlEscape(vcardData) + `</card:address-data>`
	}
	return `<d:response><d:href>` + xmlEscape(href) + `</d:href><d:propstat><d:prop>` +
		prop + `</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>`
}

func xmlEscape(s string) string {
	s = strings.ReplaceAll(s, "&", "&amp;")
	s = strings.ReplaceAll(s, "<", "&lt;")
	s = strings.ReplaceAll(s, ">", "&gt;")
	s = strings.ReplaceAll(s, `"`, "&quot;")
	return s
}
