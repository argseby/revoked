package testutils

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime"
	"net/http"
	"regexp"
	"sort"
	"strings"
	"sync"

	"github.com/getkin/kin-openapi/openapi3"
	"github.com/getkin/kin-openapi/openapi3filter"
	"github.com/getkin/kin-openapi/routers"
	"github.com/getkin/kin-openapi/routers/legacy"
)

// SpecPath is docs/api/openapi.yaml as seen from the tests package.
const SpecPath = "../docs/api/openapi.yaml"

// conformance checks every response the test server sends against the spec,
// so the suite as a whole proves the document describes what the code does.
type conformance struct {
	router   routers.Router
	appError *openapi3.Schema

	mu         sync.Mutex
	violations map[string]string
	checked    int
}

var specCheck *conformance

// LoadSpec parses the OpenAPI document and makes every object that lists its
// properties closed, so a field the server sends but the spec does not name
// is a violation rather than silently allowed.
func LoadSpec(path string) (*openapi3.T, error) {
	loader := openapi3.NewLoader()
	doc, err := loader.LoadFromFile(path)
	if err != nil {
		return nil, err
	}
	if err := doc.Validate(context.Background()); err != nil {
		return nil, fmt.Errorf("invalid spec: %w", err)
	}
	seen := map[*openapi3.Schema]bool{}
	for _, item := range doc.Paths.Map() {
		for _, op := range item.Operations() {
			for _, resp := range op.Responses.Map() {
				if resp.Value == nil {
					continue
				}
				for _, mt := range resp.Value.Content {
					closeObjects(mt.Schema, seen)
				}
			}
		}
	}
	return doc, nil
}

func closeObjects(ref *openapi3.SchemaRef, seen map[*openapi3.Schema]bool) {
	if ref == nil || ref.Value == nil || seen[ref.Value] {
		return
	}
	s := ref.Value
	seen[s] = true
	composed := len(s.AllOf)+len(s.AnyOf)+len(s.OneOf) > 0
	if len(s.Properties) > 0 && !composed && s.AdditionalProperties.Has == nil && s.AdditionalProperties.Schema == nil {
		closed := false
		s.AdditionalProperties.Has = &closed
	}
	for _, p := range s.Properties {
		closeObjects(p, seen)
	}
	closeObjects(s.Items, seen)
	closeObjects(s.AdditionalProperties.Schema, seen)
	for _, list := range [][]*openapi3.SchemaRef{s.AllOf, s.AnyOf, s.OneOf} {
		for _, sub := range list {
			closeObjects(sub, seen)
		}
	}
}

func enableConformance() error {
	doc, err := LoadSpec(SpecPath)
	if err != nil {
		return err
	}
	doc.Servers = nil
	router, err := legacy.NewRouter(doc)
	if err != nil {
		return err
	}
	for _, ct := range []string{"text/html", "text/calendar", "text/vcard", "text/x-vcard", "image/png", "image/jpeg", "image/svg+xml", "application/pdf", "application/zip", "application/xml", "text/xml", "application/jwk-set+json", "application/statuslist+jwt", "application/javascript", "text/javascript", "text/css", "application/vnd.apple.pkpass"} {
		if openapi3filter.RegisteredBodyDecoder(ct) == nil {
			openapi3filter.RegisterBodyDecoder(ct, openapi3filter.FileBodyDecoder)
		}
	}
	specCheck = &conformance{
		router:     router,
		appError:   doc.Components.Schemas["AppError"].Value,
		violations: map[string]string{},
	}
	return nil
}

// ConformanceViolations returns each distinct way a response departed from
// the spec, and how many responses were checked.
func ConformanceViolations() ([]string, int) {
	if specCheck == nil {
		return nil, 0
	}
	specCheck.mu.Lock()
	defer specCheck.mu.Unlock()
	out := make([]string, 0, len(specCheck.violations))
	for k, example := range specCheck.violations {
		out = append(out, k+"\n      e.g. "+example)
	}
	sort.Strings(out)
	return out, specCheck.checked
}

type recorder struct {
	http.ResponseWriter
	status int
	body   bytes.Buffer
}

func (r *recorder) WriteHeader(status int) {
	if r.status == 0 {
		r.status = status
	}
	r.ResponseWriter.WriteHeader(status)
}

func (r *recorder) Write(b []byte) (int, error) {
	if r.status == 0 {
		r.status = http.StatusOK
	}
	r.body.Write(b)
	return r.ResponseWriter.Write(b)
}

func (r *recorder) Flush() {
	if f, ok := r.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

func (r *recorder) Unwrap() http.ResponseWriter { return r.ResponseWriter }

func (c *conformance) wrap(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if skipConformance(req.URL.Path) {
			next.ServeHTTP(w, req)
			return
		}
		rec := &recorder{ResponseWriter: w}
		probe := req.Clone(req.Context())
		next.ServeHTTP(rec, req)
		c.check(probe, rec)
	})
}

// skipConformance leaves out what is not API: the admin dashboard and
// PocketBase's realtime stream.
func skipConformance(path string) bool {
	return strings.HasPrefix(path, "/_/") || path == "/_" || path == "/api/realtime"
}

func (c *conformance) check(req *http.Request, rec *recorder) {
	status := rec.status
	if status == 0 {
		status = http.StatusOK
	}
	route, params, err := c.router.FindRoute(req)
	if err != nil {
		// Refusing a route the spec does not name is what a test probing
		// that it is gone expects; answering one is a gap.
		if status < 400 {
			c.record(fmt.Sprintf("%s %s: not in the spec", req.Method, req.URL.Path), req, status, "")
		}
		return
	}
	c.count()
	key := fmt.Sprintf("%s %s %d", req.Method, route.Path, status)
	responses := route.Operation.Responses
	if responses == nil || (responses.Status(status) == nil && responses.Default() == nil) {
		if !undocumentedStatusAllowed(status) {
			c.record(key+": status not documented", req, status, "")
			return
		}
		// Any operation may refuse; the refusal still has the one envelope.
		if mt, _, _ := mime.ParseMediaType(rec.Header().Get("Content-Type")); mt == "application/json" {
			var body any
			if err := json.Unmarshal(rec.body.Bytes(), &body); err != nil {
				c.record(key+": body is not JSON", req, status, rec.body.String())
			} else if err := c.appError.VisitJSON(body, openapi3.EnableJSONSchema2020()); err != nil {
				c.record(key+": not an AppError: "+trimSchemaError(err), req, status, rec.body.String())
			}
		}
		return
	}
	header := rec.Header().Clone()
	input := &openapi3filter.ResponseValidationInput{
		RequestValidationInput: &openapi3filter.RequestValidationInput{
			Request:    req,
			PathParams: params,
			Route:      route,
		},
		Status: status,
		Header: header,
		Body:   io.NopCloser(bytes.NewReader(rec.body.Bytes())),
		Options: &openapi3filter.Options{
			IncludeResponseStatus: true,
			MultiError:            false,
		},
	}
	if err := openapi3filter.ValidateResponse(context.Background(), input); err != nil {
		c.record(key+": "+trimSchemaError(err), req, status, rec.body.String())
	}
}

// undocumentedStatusAllowed names the answers any operation may give without
// listing them: the generic refusals every route shares.
func undocumentedStatusAllowed(status int) bool {
	switch status {
	case http.StatusBadRequest, http.StatusUnauthorized, http.StatusForbidden, http.StatusNotFound,
		http.StatusMethodNotAllowed, http.StatusConflict, http.StatusGone, http.StatusRequestEntityTooLarge,
		http.StatusTooManyRequests, http.StatusInternalServerError, http.StatusBadGateway,
		http.StatusServiceUnavailable, http.StatusNotModified, http.StatusPreconditionFailed:
		return true
	}
	return false
}

var quotedNames = regexp.MustCompile(`'[^']*'(?:, '[^']*')+`)

func trimSchemaError(err error) string {
	msg := err.Error()
	// The validator lists unknown properties in map order; sorted, one
	// departure is reported once.
	msg = quotedNames.ReplaceAllStringFunc(msg, func(list string) string {
		names := strings.Split(list, ", ")
		sort.Strings(names)
		return strings.Join(names, ", ")
	})
	if i := strings.Index(msg, "\nSchema:"); i >= 0 {
		msg = msg[:i]
	}
	msg = strings.ReplaceAll(msg, "\n", " ")
	if len(msg) > 400 {
		msg = msg[:400] + "…"
	}
	return msg
}

func (c *conformance) count() {
	c.mu.Lock()
	c.checked++
	c.mu.Unlock()
}

func (c *conformance) record(key string, req *http.Request, status int, body string) {
	if len(body) > 300 {
		body = body[:300] + "…"
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, ok := c.violations[key]; !ok {
		c.violations[key] = fmt.Sprintf("%s %s → %d %s", req.Method, req.URL.RequestURI(), status, body)
	}
}
