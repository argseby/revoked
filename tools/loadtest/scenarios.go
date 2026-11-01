package main

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"net/http"
	"sort"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/google/uuid"
)

// Scenario is one kind of traffic. Do performs a single operation and reports
// the status the server answered with, so a stage can tell a refusal from a
// collapse.
//
// Worker runs once per worker before the clock starts, for state a worker must
// not share — a passkey device is one authenticator, and signing in with it
// from several goroutines at once is the generator racing itself, not load.
type Scenario struct {
	Name   string
	Help   string
	Needs  needs
	Worker func(ctx context.Context, c *Caller, fx *Fixtures, index int) (any, error)
	Do     func(ctx context.Context, c *Caller, fx *Fixtures, state any, r *rand.Rand) (int, int64, error)
	Accept func(status int) bool
}

type needs uint8

const (
	needsNothing needs = 0
	needsUsers   needs = 1 << iota
	needsLinks
	needsRequests
)

func (s *Scenario) accepts(status int) bool {
	if s.Accept != nil {
		return s.Accept(status)
	}
	return status >= 200 && status <= 299
}

var scenarios = map[string]*Scenario{}

func register(s *Scenario) { scenarios[s.Name] = s }

func scenarioNames() []string {
	names := make([]string, 0, len(scenarios))
	for name := range scenarios {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

func init() {
	register(&Scenario{
		Name:  "health",
		Help:  "GET /healthz — the floor: routing and nothing else",
		Needs: needsNothing,
		Do: func(ctx context.Context, c *Caller, _ *Fixtures, _ any, _ *rand.Rand) (int, int64, error) {
			return c.GET(ctx, "/healthz", "")
		},
	})

	register(&Scenario{
		Name:  "probe",
		Help:  "GET /api/public/links/{slug} — unauthenticated metadata read",
		Needs: needsLinks,
		Do: func(ctx context.Context, c *Caller, fx *Fixtures, _ any, r *rand.Rand) (int, int64, error) {
			return c.GET(ctx, "/api/public/links/"+pick(fx.Links, r).Slug, "")
		},
	})

	register(&Scenario{
		Name:  "page",
		Help:  "GET /s/{slug} — the server-rendered share page",
		Needs: needsLinks,
		Do: func(ctx context.Context, c *Caller, fx *Fixtures, _ any, r *rand.Rand) (int, int64, error) {
			return c.GET(ctx, "/s/"+pick(fx.Links, r).Slug, "")
		},
	})

	register(&Scenario{
		Name:  "view",
		Help:  "POST /api/public/links/{slug} — resolve a share and claim a view (reads and writes)",
		Needs: needsLinks,
		Do: func(ctx context.Context, c *Caller, fx *Fixtures, _ any, r *rand.Rand) (int, int64, error) {
			return c.POST(ctx, "/api/public/links/"+pick(fx.Links, r).Slug, "", map[string]any{})
		},
	})

	register(&Scenario{
		Name:  "vault-list",
		Help:  "GET records — an authenticated, rule-filtered list query",
		Needs: needsUsers,
		Do: func(ctx context.Context, c *Caller, fx *Fixtures, _ any, r *rand.Rand) (int, int64, error) {
			u := fx.Users[r.Intn(len(fx.Users))]
			return c.GET(ctx, "/api/collections/"+util.Coll.Records+"/records?page=1&perPage=50", u.Token)
		},
	})

	register(&Scenario{
		Name:  "vault-write",
		Help:  "POST records — an authenticated write, with its hooks and audit row",
		Needs: needsUsers,
		Do: func(ctx context.Context, c *Caller, fx *Fixtures, _ any, r *rand.Rand) (int, int64, error) {
			u := fx.Users[r.Intn(len(fx.Users))]
			return c.POST(ctx, "/api/collections/"+util.Coll.Records+"/records", u.Token, map[string]any{
				util.Fields.Record.Key:       "lt_" + uuid.NewString(),
				util.Fields.Record.Value:     uuid.NewString(),
				util.Fields.Record.Label:     "Load test write",
				util.Fields.Record.Type:      util.TypeText,
				util.Fields.Record.Format:    util.FormatDefault,
				util.Fields.Record.User:      u.ID,
				util.Fields.Record.Workspace: u.WorkspaceID,
			})
		},
	})

	register(&Scenario{
		Name:  "respond",
		Help:  "POST /api/public/requests/{slug} — answer somebody else's request (the heaviest write)",
		Needs: needsUsers | needsRequests,
		Do: func(ctx context.Context, c *Caller, fx *Fixtures, _ any, r *rand.Rand) (int, int64, error) {
			req := pick(fx.Requests, r)
			responder := fx.Users[otherThan(req.Owner, len(fx.Users), r)]
			return c.POST(ctx, "/api/public/requests/"+req.Slug, responder.Token, map[string]any{
				"senderName": "Load test",
				"data":       map[string]any{"answer": uuid.NewString()},
			})
		},
	})

	register(&Scenario{
		Name:  "signup",
		Help:  "the whole passkey registration ceremony — a new account per operation",
		Needs: needsNothing,
		Do: func(ctx context.Context, c *Caller, _ *Fixtures, _ any, _ *rand.Rand) (int, int64, error) {
			device := testutils.NewPasskeyDevice(c.base)
			_, err := device.Register(map[string]any{
				"email": fmt.Sprintf("lt-%s@example.com", uuid.NewString()),
			})
			return ceremonyResult(err)
		},
	})

	register(&Scenario{
		Name:  "signin",
		Help:  "the whole passkey sign-in ceremony on an existing device",
		Needs: needsNothing,
		Worker: func(_ context.Context, c *Caller, _ *Fixtures, _ int) (any, error) {
			// Not a seeded account: a device is an authenticator with one
			// signature counter, so each worker needs its own.
			device := testutils.NewPasskeyDevice(c.base)
			if _, err := device.Register(map[string]any{
				"email": fmt.Sprintf("lt-signin-%s@example.com", uuid.NewString()),
			}); err != nil {
				return nil, err
			}
			return device, nil
		},
		Do: func(_ context.Context, _ *Caller, _ *Fixtures, state any, _ *rand.Rand) (int, int64, error) {
			_, err := state.(*testutils.PasskeyDevice).SignIn()
			return ceremonyResult(err)
		},
	})

	register(&Scenario{
		Name:  "mixed",
		Help:  "a weighted blend: mostly share reads, some authenticated traffic",
		Needs: needsUsers | needsLinks | needsRequests,
		Do: func(ctx context.Context, c *Caller, fx *Fixtures, state any, r *rand.Rand) (int, int64, error) {
			switch n := r.Intn(100); {
			case n < 40:
				return scenarios["probe"].Do(ctx, c, fx, state, r)
			case n < 65:
				return scenarios["view"].Do(ctx, c, fx, state, r)
			case n < 80:
				return scenarios["page"].Do(ctx, c, fx, state, r)
			case n < 93:
				return scenarios["vault-list"].Do(ctx, c, fx, state, r)
			default:
				return scenarios["vault-write"].Do(ctx, c, fx, state, r)
			}
		},
	})
}

func pick(slugs []SeedSlug, r *rand.Rand) SeedSlug {
	return slugs[r.Intn(len(slugs))]
}

// otherThan returns an index that is not avoid, when there is one to return.
func otherThan(avoid, n int, r *rand.Rand) int {
	if n <= 1 {
		return 0
	}
	i := r.Intn(n - 1)
	if i >= avoid {
		i++
	}
	return i
}

// ceremonyResult reports a multi-request ceremony as one operation. A refusal
// carries its status so the stage's tally separates a throttled run from a
// broken one.
func ceremonyResult(err error) (int, int64, error) {
	if err == nil {
		return http.StatusOK, 0, nil
	}
	var refusal *testutils.PasskeyError
	if errors.As(err, &refusal) {
		return refusal.Status, 0, nil
	}
	return 0, 0, err
}

// missingFixtures names what a scenario cannot run without.
func (s *Scenario) missingFixtures(fx *Fixtures) string {
	if s.Needs&needsUsers != 0 && len(fx.Users) == 0 {
		return "seeded accounts"
	}
	if s.Needs&needsLinks != 0 && len(fx.Links) == 0 {
		return "seeded links"
	}
	if s.Needs&needsRequests != 0 && len(fx.Requests) == 0 {
		return "seeded requests"
	}
	if s.Needs&needsRequests != 0 && len(fx.Users) < 2 {
		return "at least two seeded accounts"
	}
	return ""
}
