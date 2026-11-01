package services

import (
	"strings"
	"time"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// Why an address was not mailed. Short stable tokens: they go in the audit
// row, never to the person who was not reached.
const (
	emailRefusedPolicy     = "policy"
	emailRefusedAddress    = "address"
	emailRefusedRate       = "rate"
	emailRefusedSuppressed = "suppressed"
	emailRefusedSignups    = "signups-closed"
)

// MayEmailGrant settles whether this server may mail address at all.
//
// Mail is the one feature where a person's action makes this server contact a
// stranger, so the operator's policy decides the reach and the checks run
// cheapest first. The `trusted` policy is deliberately NOT settled here: it
// costs a DNS lookup and an outbound HTTPS GET with no negative caching, so
// hanging it off a user-triggered POST would make this an outbound-request
// amplifier and a reachability oracle. The worker settles it instead.
func MayEmailGrant(app core.App, serverDomain, address string) (bool, string) {
	policy := util.GrantEmailRecipients()
	if policy == util.MailRecipientsOff {
		return false, emailRefusedPolicy
	}
	address = NormalizeEmail(address)
	domain := MailableEmailDomain(address)
	if domain == "" {
		return false, emailRefusedAddress
	}
	if policy == util.MailRecipientsSameDomain && !strings.EqualFold(domain, serverDomain) {
		return false, emailRefusedPolicy
	}
	if GrantEmailSuppressed(app, address) {
		return false, emailRefusedSuppressed
	}
	if GrantEmailsSentTo(app, address, time.Hour) >= util.LimitFromEnv(
		util.GrantEmailsPerHourEnv, util.DefaultGrantEmailsPerHour) {
		return false, emailRefusedRate
	}
	return true, ""
}

// NormalizeEmail lowercases and trims an address, so a cap and a suppression
// entry cannot be stepped around by changing its case.
func NormalizeEmail(address string) string {
	return strings.ToLower(strings.TrimSpace(address))
}

// EmailDomain is the lowercased part after the last @, or "" when the address
// has no single plausible one.
//
// For the mail policy the domain is read out of the address and never from
// `contacts.peerDomain`, which a client sets freely: letting that field vouch
// for the address would be a one-line bypass of the whole policy.
func EmailDomain(address string) string {
	at := strings.LastIndex(address, "@")
	if at <= 0 || at == len(address)-1 {
		return ""
	}
	domain := strings.ToLower(address[at+1:])
	if strings.ContainsAny(domain, "@ \t") {
		return ""
	}
	return domain
}

// MailableEmailDomain is [EmailDomain] held to what may be mailed: a domain
// with no dot is not a destination this server will contact.
func MailableEmailDomain(address string) string {
	domain := EmailDomain(address)
	if !strings.Contains(domain, ".") {
		return ""
	}
	return domain
}

// GrantEmailsSentTo counts the grant emails attempted to one address inside
// window.
//
// It counts outbox rows rather than keeping a counter in memory, because this
// is the one cap whose victim is not a user of this server: util.RateLimiter
// is per-process, so two instances behind a load balancer would give a
// stranger's inbox twice the budget. The count is exact across instances and
// is what idxGrantDeliveriesEmailTarget exists for.
func GrantEmailsSentTo(app core.App, address string, window time.Duration) int {
	var count int
	err := app.DB().NewQuery(`
		SELECT COUNT(*) FROM {{grantDeliveries}}
		WHERE kind = {:kind} AND target = {:target} AND created > {:cutoff}
	`).Bind(dbx.Params{
		"kind":   util.DeliveryKindEmail,
		"target": address,
		"cutoff": time.Now().Add(-window).UTC().Format("2006-01-02 15:04:05.000Z"),
	}).Row(&count)
	if err != nil {
		app.Logger().Error("Failed to count grant emails", "error", err)
		// Fail closed: an unreadable count must not read as budget left.
		return util.LimitFromEnv(util.GrantEmailsPerHourEnv, util.DefaultGrantEmailsPerHour)
	}
	return count
}

// GrantEmailSuppressed reports whether an address failed permanently recently
// enough that trying again would just annoy a relay.
func GrantEmailSuppressed(app core.App, address string) bool {
	var count int
	err := app.DB().NewQuery(`
		SELECT COUNT(*) FROM {{grantDeliveries}}
		WHERE kind = {:kind} AND target = {:target}
		  AND failedAt != '' AND failedAt > {:cutoff}
	`).Bind(dbx.Params{
		"kind":   util.DeliveryKindEmail,
		"target": address,
		"cutoff": time.Now().Add(-util.GrantEmailSuppressFor).UTC().Format("2006-01-02 15:04:05.000Z"),
	}).Row(&count)
	if err != nil {
		app.Logger().Error("Failed to read grant email suppression", "error", err)
		return true
	}
	return count > 0
}

// GrantEmailPayload is what an outbox row carries. It names the grant rather
// than copying its slug: the slug is a capability and the row is kept for a
// week, the mail should reflect the grant as it stands when it is sent, and a
// grant revoked in the meantime is then skipped instead of mailed.
type GrantEmailPayload struct {
	Grant      string `json:"grant"`
	Collection string `json:"collection"`
	Workspace  string `json:"workspace"`
	Locale     string `json:"locale"`
}

// EnqueueGrantEmail puts a grant on the outbox to be mailed to address.
//
// On the outbox rather than inline: SMTP is a call to a third party with a
// third party's timeouts, and the outbox already has retry with backoff,
// give-up after twelve attempts, lastError for the operator, and a kick so
// the mail normally leaves at once.
func EnqueueGrantEmail(app core.App, address string, payload GrantEmailPayload) error {
	if payload.Locale == "" {
		payload.Locale = "en"
	}
	err := enqueueDelivery(app, util.DeliveryKindEmail, NormalizeEmail(address), "", map[string]any{
		"grant":      payload.Grant,
		"collection": payload.Collection,
		"workspace":  payload.Workspace,
		"locale":     payload.Locale,
	})
	if err != nil {
		return err
	}
	KickGrantDeliveries()
	return nil
}
