package routes

import (
	"net/http"
	"regexp"
	"revoked/util"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/security"
)

// Suggested values a connected tool hands over with a share proposal.
//
// A tool that already heard a value from the owner — an assistant they told
// their phone number in chat — can pass it on with its proposal instead of
// making the owner type it again. The value is a suggestion, nothing more:
//
//	POST   /api/connection/drafts          (the tool)  {"values": {key: text}}
//	    holds the values and returns a draft id, which the proposal link
//	    carries as draft=<id>. The link itself never carries a value.
//	GET    /api/connections/drafts/{id}    (the owner, signed in — from the app)
//	    the values, for the proposal screen to offer as prefilled answers.
//	DELETE /api/connections/drafts/{id}    (the owner)
//	    discards them once the proposal is done with, created or not.
//
// Drafts live in this process's memory only, for draftTTL: never on disk,
// never in a backup, gone on restart. Nothing is saved to the vault from a
// draft; the app offers a value only for a key the vault does not hold yet,
// and the owner saves it the way they would save one they typed. The audit
// log names the keys a tool suggested, never the values.
const (
	draftTTL           = time.Hour
	draftMaxKeys       = 50
	draftMaxValue      = 4000
	draftMaxPerConnect = 20
	draftIDLength      = 24
)

var (
	draftKeyPattern = regexp.MustCompile(`^[a-z0-9_-]{1,64}$`)
	draftIDPattern  = regexp.MustCompile(`^[a-z0-9]{24}$`)
)

const draftIDAlphabet = "abcdefghijklmnopqrstuvwxyz0123456789"

const auditToolDraftedValues = "tool_drafted_values" // it suggested values for a proposal

type proposalDraft struct {
	connection string
	user       string
	clientName string
	values     map[string]string
	expires    time.Time
}

// draftStore holds drafts until they are discarded or expire.
type draftStore struct {
	mu     sync.Mutex
	drafts map[string]*proposalDraft
	now    func() time.Time
}

var proposalDrafts = &draftStore{drafts: map[string]*proposalDraft{}, now: time.Now}

// sweep drops expired drafts; the caller holds mu.
func (s *draftStore) sweep() {
	now := s.now()
	for id, d := range s.drafts {
		if !now.Before(d.expires) {
			delete(s.drafts, id)
		}
	}
}

func (s *draftStore) put(d *proposalDraft) (string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sweep()
	n := 0
	for _, other := range s.drafts {
		if other.connection == d.connection {
			n++
		}
	}
	if n >= draftMaxPerConnect {
		return "", false
	}
	id := security.RandomStringWithAlphabet(draftIDLength, draftIDAlphabet)
	s.drafts[id] = d
	return id, true
}

// get returns the draft when it belongs to user and has not expired.
func (s *draftStore) get(id, user string) *proposalDraft {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sweep()
	d := s.drafts[id]
	if d == nil || d.user != user {
		return nil
	}
	return d
}

func (s *draftStore) drop(id, user string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	d := s.drafts[id]
	if d == nil || d.user != user {
		return false
	}
	delete(s.drafts, id)
	return true
}

// dropConnection forgets every draft of a connection, when it ends.
func (s *draftStore) dropConnection(conn string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for id, d := range s.drafts {
		if d.connection == conn {
			delete(s.drafts, id)
		}
	}
}

// draftValues checks what a tool sent: 1-50 keys of [a-z0-9_-], each with one
// line or paragraph of text, at most draftMaxValue characters, no control
// characters but line breaks and tabs. Refused whole when any part is not.
func draftValues(in map[string]string) (map[string]string, string) {
	if len(in) == 0 || len(in) > draftMaxKeys {
		return nil, "values must hold 1-50 keys"
	}
	out := make(map[string]string, len(in))
	for k, v := range in {
		if !draftKeyPattern.MatchString(k) {
			return nil, "key " + k + " is not [a-z0-9_-]{1,64}"
		}
		v = strings.TrimSpace(v)
		if v == "" {
			return nil, "value for " + k + " is empty"
		}
		if !utf8.ValidString(v) || utf8.RuneCountInString(v) > draftMaxValue {
			return nil, "value for " + k + " must be valid text of at most 4000 characters"
		}
		for _, r := range v {
			if r < 0x20 && r != '\n' && r != '\t' || r == 0x7f {
				return nil, "value for " + k + " holds control characters"
			}
		}
		out[k] = v
	}
	return out, ""
}

// ConnectionDraftsRoute lets a connected tool suggest values for a proposal
// and the owner's app fetch and discard them.
func ConnectionDraftsRoute(app core.App) {
	// A connection that ends takes its drafts with it.
	app.OnRecordAfterDeleteSuccess(util.Coll.Connections).BindFunc(func(ev *core.RecordEvent) error {
		proposalDrafts.dropConnection(ev.Record.Id)
		return ev.Next()
	})

	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.POST("/api/connection/drafts", func(re *core.RequestEvent) error {
			conn, _, ok := connectionFromRequest(app, re)
			if !ok {
				return nil
			}
			var body struct {
				Values map[string]string `json:"values"`
			}
			if err := re.BindBody(&body); err != nil {
				return re.BadRequestError("Invalid body", err)
			}
			values, problem := draftValues(body.Values)
			if problem != "" {
				return re.BadRequestError(problem, nil)
			}
			expires := proposalDrafts.now().Add(draftTTL)
			id, ok := proposalDrafts.put(&proposalDraft{
				connection: conn.Id,
				user:       conn.GetString(util.Fields.Connection.User),
				clientName: conn.GetString(util.Fields.Connection.ClientName),
				values:     values,
				expires:    expires,
			})
			if !ok {
				return re.TooManyRequestsError("Too many open drafts; wait until the owner has answered", nil)
			}
			keys := make([]string, 0, len(values))
			for k := range values {
				keys = append(keys, k)
			}
			auditConnection(app, re, conn, auditToolDraftedValues, map[string]any{"draftKeys": keys})
			return re.JSON(http.StatusOK, map[string]any{
				"id":        id,
				"expiresAt": expires.UTC().Format(time.RFC3339),
			})
		})

		e.Router.GET("/api/connections/drafts/{id}", func(re *core.RequestEvent) error {
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return re.UnauthorizedError(util.Errors.NotAuthenticated.ErrorCode, nil)
			}
			id := re.Request.PathValue("id")
			var d *proposalDraft
			if draftIDPattern.MatchString(id) {
				d = proposalDrafts.get(id, re.Auth.Id)
			}
			if d == nil {
				return re.NotFoundError("Draft not found or expired", nil)
			}
			// A tool the owner paused or that expired suggests nothing.
			conn, err := app.FindRecordById(util.Coll.Connections, d.connection)
			if err != nil || conn == nil || conn.GetBool(util.Fields.Connection.Paused) ||
				util.ConnectionExpired(conn.GetDateTime(util.Fields.Connection.ExpiresAt).Time()) {
				proposalDrafts.drop(id, re.Auth.Id)
				return re.NotFoundError("Draft not found or expired", nil)
			}
			return re.JSON(http.StatusOK, map[string]any{
				"id":         id,
				"connection": d.connection,
				"clientName": d.clientName,
				"values":     d.values,
				"expiresAt":  d.expires.UTC().Format(time.RFC3339),
			})
		})

		e.Router.DELETE("/api/connections/drafts/{id}", func(re *core.RequestEvent) error {
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return re.UnauthorizedError(util.Errors.NotAuthenticated.ErrorCode, nil)
			}
			// Discarding is idempotent: an expired draft is already gone.
			proposalDrafts.drop(re.Request.PathValue("id"), re.Auth.Id)
			return re.NoContent(http.StatusNoContent)
		})
		return e.Next()
	})
}
