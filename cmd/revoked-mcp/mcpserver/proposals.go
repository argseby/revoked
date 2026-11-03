package mcpserver

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type ProposeRequestInput struct {
	Template string `json:"template" jsonschema:"the name of the owner's template saying what the request asks for"`
	Label    string `json:"label,omitempty" jsonschema:"the request's title, up to 120 characters; left out, the template's name"`
	Days     int    `json:"days,omitempty" jsonschema:"days until the request closes, 1-365; left out, it stays open"`
	Ref      string `json:"ref,omitempty" jsonschema:"your own reference, up to 80 characters, returned by list_requests"`
}

type ProposeAttestationInput struct {
	Type   string   `json:"type" jsonschema:"the kind of attestation, one word or a URI, e.g. membership"`
	Claims []string `json:"claims,omitempty" jsonschema:"claim names to fill in, letters, digits and underscores; the owner sets every value"`
	For    string   `json:"for" jsonschema:"the subject's identity fingerprint, 64 hex characters, e.g. a holder fingerprint from list_checks"`
	Ref    string   `json:"ref,omitempty" jsonschema:"your own reference, up to 80 characters, returned by list_attestations"`
}

type ProposeCheckInput struct {
	Type    string   `json:"type,omitempty" jsonschema:"the kind of attestation to ask for; left out, any"`
	Issuers []string `json:"issuers,omitempty" jsonschema:"attester domains accepted, up to 20"`
	Claims  []string `json:"claims,omitempty" jsonschema:"claims needed, up to 50; the other person chooses what to show"`
	Ref     string   `json:"ref,omitempty" jsonschema:"your own reference, up to 80 characters, returned by list_checks"`
}

type IDInput struct {
	ID string `json:"id" jsonschema:"the id from the matching list tool"`
}

type RequestList struct {
	Requests []Request `json:"requests"`
}

type AttestationList struct {
	Attestations []Attestation `json:"attestations"`
}

type CheckList struct {
	Checks []Check `json:"checks"`
}

var (
	attestationType = regexp.MustCompile(`^[\x21-\x7e]{1,255}$`)
	claimName       = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_]{0,63}$`)
	fingerprint     = regexp.MustCompile(`^[0-9a-f]{64}$`)
	attesterDomain  = regexp.MustCompile(`^[a-z0-9.-]+(:[0-9]{1,5})?$`)
)

func addProposalTools(s *mcp.Server, c *client) {
	readOnly := &mcp.ToolAnnotations{ReadOnlyHint: true}
	destructive := true

	propose := func(build func() (string, error), what, list string) (*mcp.CallToolResult, ProposeResult, error) {
		link, err := build()
		if err != nil {
			return nil, ProposeResult{}, err
		}
		opened := c.cfg.Open != nil && c.cfg.Open(link) == nil
		next := "The owner fills in and confirms the " + what + " in the Revoked app."
		if c.loadToken() != "" {
			next += " Call " + list + " to see it once they have."
		} else {
			next += " Connect first to be able to follow it."
		}
		return nil, ProposeResult{Link: link, Opened: opened, Next: next}, nil
	}

	mcp.AddTool(s, &mcp.Tool{
		Name: "propose_request",
		Description: "Propose a request that collects data from other people with one of the owner's templates. " +
			"The owner picks the identity and creates it in the Revoked app; its link and its answers go to them, not to you.",
	}, func(_ context.Context, _ *mcp.CallToolRequest, in ProposeRequestInput) (*mcp.CallToolResult, ProposeResult, error) {
		return propose(func() (string, error) { return requestLink(c.cfg, in) }, "request", "list_requests")
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "list_requests",
		Description: "The requests the owner created from your proposals: label, your ref, status and number of answers. Never the answers or the request's address.",
		Annotations: readOnly,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, RequestList, error) {
		conn, err := c.connection(ctx)
		if err != nil {
			return nil, RequestList{}, err
		}
		return nil, RequestList{Requests: conn.Requests}, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "close_request",
		Description: "Stop one of the requests from list_requests taking new answers. Answers already given stay. Needs the owner's permission, given when connecting.",
		Annotations: &mcp.ToolAnnotations{DestructiveHint: &destructive},
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in IDInput) (*mcp.CallToolResult, Request, error) {
		var r Request
		if err := actOn(ctx, c, "requests", in.ID, "close", &r); err != nil {
			return nil, Request{}, err
		}
		return nil, r, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name: "propose_attestation",
		Description: "Propose that the owner attest something about an identity in their domain's name, e.g. a membership. " +
			"You name the kind and the claims; the owner sets every value and makes the offer in the Revoked app. Needs attesting switched on for their server.",
	}, func(_ context.Context, _ *mcp.CallToolRequest, in ProposeAttestationInput) (*mcp.CallToolResult, ProposeResult, error) {
		return propose(func() (string, error) { return attestationLink(c.cfg, in) }, "attestation", "list_attestations")
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "list_attestations",
		Description: "The attestations the owner made from your proposals: kind, your ref, status and whom they were issued to. Never their values.",
		Annotations: readOnly,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, AttestationList, error) {
		conn, err := c.connection(ctx)
		if err != nil {
			return nil, AttestationList{}, err
		}
		return nil, AttestationList{Attestations: conn.Attestations}, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "revoke_attestation",
		Description: "Revoke one of the attestations from list_attestations, or withdraw its offer. Final: verifiers see it as revoked. Needs the owner's permission, given when connecting.",
		Annotations: &mcp.ToolAnnotations{DestructiveHint: &destructive},
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in IDInput) (*mcp.CallToolResult, Attestation, error) {
		var a Attestation
		if err := actOn(ctx, c, "attestations", in.ID, "revoke", &a); err != nil {
			return nil, Attestation{}, err
		}
		return nil, a, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name: "propose_check",
		Description: "Propose that the owner ask someone to show an attestation, e.g. a membership. " +
			"The owner makes the check in the Revoked app and shows its code to the person, who chooses what to show.",
	}, func(_ context.Context, _ *mcp.CallToolRequest, in ProposeCheckInput) (*mcp.CallToolResult, ProposeResult, error) {
		return propose(func() (string, error) { return checkLink(c.cfg, in) }, "check", "list_checks")
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "list_checks",
		Description: "The checks the owner made from your proposals and, once answered, the verdict with the claims the person chose to show.",
		Annotations: readOnly,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, CheckList, error) {
		conn, err := c.connection(ctx)
		if err != nil {
			return nil, CheckList{}, err
		}
		return nil, CheckList{Checks: conn.Checks}, nil
	})
}

func actOn(ctx context.Context, c *client, kind, id, verb string, out any) error {
	if strings.TrimSpace(id) == "" {
		return errors.New("id is required")
	}
	return c.act(ctx, kind, id, verb, out)
}

func requestLink(cfg Config, in ProposeRequestInput) (string, error) {
	template := strings.Join(strings.Fields(in.Template), " ")
	if template == "" || utf8.RuneCountInString(template) > 80 {
		return "", errors.New("template must be 1-80 characters")
	}
	label := strings.Join(strings.Fields(in.Label), " ")
	if utf8.RuneCountInString(label) > 120 {
		return "", errors.New("label must be at most 120 characters")
	}
	if in.Days < 0 || in.Days > 365 {
		return "", errors.New("days must be 1-365")
	}
	if err := checkRef(in.Ref); err != nil {
		return "", err
	}
	q := []string{"template=" + escape(template)}
	if label != "" {
		q = append(q, "label="+escape(label))
	}
	if in.Days > 0 {
		q = append(q, "days="+strconv.Itoa(in.Days))
	}
	q = append(q, toolQuery(cfg, "from", in.Ref)...)
	return "revoked://pr?" + strings.Join(q, "&"), nil
}

func attestationLink(cfg Config, in ProposeAttestationInput) (string, error) {
	if !attestationType.MatchString(in.Type) {
		return "", errors.New("type must be one word or a URI, up to 255 characters")
	}
	subject := strings.ToLower(strings.TrimSpace(in.For))
	if !fingerprint.MatchString(subject) {
		return "", errors.New("for must be an identity fingerprint: 64 characters, 0-9 and a-f")
	}
	claims, err := names(in.Claims, 50, claimName, "claim")
	if err != nil {
		return "", err
	}
	if err := checkRef(in.Ref); err != nil {
		return "", err
	}
	q := []string{"type=" + escape(in.Type), "for=" + subject}
	if len(claims) > 0 {
		q = append(q, "claims="+strings.Join(claims, ","))
	}
	q = append(q, toolQuery(cfg, "name", in.Ref)...)
	return "revoked://attest?" + strings.Join(q, "&"), nil
}

func checkLink(cfg Config, in ProposeCheckInput) (string, error) {
	if in.Type != "" && !attestationType.MatchString(in.Type) {
		return "", errors.New("type must be one word or a URI, up to 255 characters")
	}
	lowered := make([]string, len(in.Issuers))
	for i, d := range in.Issuers {
		lowered[i] = strings.ToLower(d)
	}
	issuers, err := names(lowered, 20, attesterDomain, "issuer")
	if err != nil {
		return "", err
	}
	claims, err := names(in.Claims, 50, claimName, "claim")
	if err != nil {
		return "", err
	}
	if err := checkRef(in.Ref); err != nil {
		return "", err
	}
	var q []string
	if in.Type != "" {
		q = append(q, "type="+escape(in.Type))
	}
	if len(issuers) > 0 {
		q = append(q, "issuers="+strings.Join(issuers, ","))
	}
	if len(claims) > 0 {
		q = append(q, "claims="+strings.Join(claims, ","))
	}
	q = append(q, toolQuery(cfg, "from", in.Ref)...)
	return "revoked://check?" + strings.Join(q, "&"), nil
}

// toolQuery names the assistant on a proposal, so the row joins its
// connection once the owner creates it.
func toolQuery(cfg Config, nameKey, ref string) []string {
	q := []string{nameKey + "=" + escape(cfg.Name), "client=" + escape(cfg.Client)}
	if ref != "" {
		q = append(q, "ref="+escape(ref))
	}
	return q
}

func checkRef(ref string) error {
	if utf8.RuneCountInString(ref) > 80 {
		return errors.New("ref must be at most 80 characters")
	}
	return nil
}

func names(in []string, max int, pattern *regexp.Regexp, what string) ([]string, error) {
	out := []string{}
	seen := map[string]bool{}
	for _, n := range in {
		n = strings.TrimSpace(n)
		if n == "" || seen[n] {
			continue
		}
		if !pattern.MatchString(n) {
			return nil, fmt.Errorf("%s %q is not valid", what, n)
		}
		seen[n] = true
		out = append(out, n)
	}
	if len(out) > max {
		return nil, fmt.Errorf("at most %d %ss", max, what)
	}
	return out, nil
}
