package util

import "slices"

// Webhook event types. An event names what changed and its new state, never a
// value: a receiver reads the value through the API, where a revoked grant
// stops answering and a sealed record was never readable.
const (
	WebhookLinkCreated = "link.created"
	WebhookLinkUpdated = "link.updated"
	WebhookLinkViewed  = "link.viewed"
	WebhookLinkPaused  = "link.paused"
	WebhookLinkResumed = "link.resumed"
	WebhookLinkRevoked = "link.revoked"
	WebhookLinkExpired = "link.expired"

	WebhookRequestCreated = "request.created"
	WebhookRequestPaused  = "request.paused"
	WebhookRequestResumed = "request.resumed"
	WebhookRequestClosed  = "request.closed"

	WebhookResponseSubmitted = "response.submitted"
	WebhookResponseChanged   = "response.changed"
	WebhookResponseRevoked   = "response.revoked"
	WebhookResponseExpired   = "response.expired"

	WebhookRecordCreated = "record.created"
	WebhookRecordUpdated = "record.updated"
	WebhookRecordDeleted = "record.deleted"

	WebhookAttestationIssued  = "attestation.issued"
	WebhookAttestationRevoked = "attestation.revoked"
	WebhookIdentityCreated    = "identity.created"
	WebhookIdentityRevoked    = "identity.revoked"

	WebhookMemberJoined       = "member.joined"
	WebhookMemberUpdated      = "member.updated"
	WebhookMemberRemoved      = "member.removed"
	WebhookApiKeyCreated      = "apikey.created"
	WebhookApiKeyRevoked      = "apikey.revoked"
	WebhookConnectionApproved = "connection.approved"
	WebhookConnectionRevoked  = "connection.revoked"

	// WebhookAllEvents subscribes an endpoint to every type, including ones
	// added after it was created.
	WebhookAllEvents = "*"
)

// Webhook delivery statuses.
const (
	WebhookDeliveryPending   = "pending"
	WebhookDeliverySucceeded = "succeeded"
	WebhookDeliveryFailed    = "failed"
)

// WebhookDeliveryStatuses lists the valid delivery statuses.
var WebhookDeliveryStatuses = []string{WebhookDeliveryPending, WebhookDeliverySucceeded, WebhookDeliveryFailed}

const (
	// MaxWebhookEndpoints bounds one workspace's endpoints: each event fans
	// out to every one of them.
	MaxWebhookEndpoints = 16

	// WebhookSecretPrefix marks a signing secret, so one pasted into the
	// wrong place is recognisable.
	WebhookSecretPrefix = "whsec_"

	// WebhookSignatureHeader carries `t=<unix>,v1=<hex>`, with one v1 per
	// secret in use while a rotated secret is still honoured.
	WebhookSignatureHeader = "Revoked-Signature"
	WebhookEventIdHeader   = "Revoked-Event-Id"
	WebhookEventTypeHeader = "Revoked-Event-Type"
)

// WebhookEventType describes one event a workspace can subscribe to.
type WebhookEventType struct {
	Type        string `json:"type"`
	Group       string `json:"group"`
	Description string `json:"description"`
	// Noisy types are left out of a new endpoint unless picked by name.
	Noisy bool `json:"noisy,omitempty"`
}

// WebhookEventTypes is the catalogue, in display order. GET
// /api/webhooks/event-types serves it so the app cannot drift.
var WebhookEventTypes = []WebhookEventType{
	{Type: WebhookLinkCreated, Group: "Shares", Description: "A share was created."},
	{Type: WebhookLinkUpdated, Group: "Shares", Description: "A share's records, limits or label changed."},
	{Type: WebhookLinkViewed, Group: "Shares", Description: "Someone opened a share.", Noisy: true},
	{Type: WebhookLinkPaused, Group: "Shares", Description: "A share was paused."},
	{Type: WebhookLinkResumed, Group: "Shares", Description: "A paused share was turned back on."},
	{Type: WebhookLinkRevoked, Group: "Shares", Description: "A share was revoked or deleted."},
	{Type: WebhookLinkExpired, Group: "Shares", Description: "A share reached its end date or its view limit."},

	{Type: WebhookRequestCreated, Group: "Requests", Description: "A request was created."},
	{Type: WebhookRequestPaused, Group: "Requests", Description: "A request was paused."},
	{Type: WebhookRequestResumed, Group: "Requests", Description: "A paused request was turned back on."},
	{Type: WebhookRequestClosed, Group: "Requests", Description: "A request was revoked, expired, completed or deleted."},

	{Type: WebhookResponseSubmitted, Group: "Answers", Description: "Someone answered a request, or answered it again."},
	{Type: WebhookResponseChanged, Group: "Answers", Description: "An answer's entries changed, or it was paused or resumed."},
	{Type: WebhookResponseRevoked, Group: "Answers", Description: "Someone took their answer back."},
	{Type: WebhookResponseExpired, Group: "Answers", Description: "An answer reached its end date or its view limit."},

	{Type: WebhookRecordCreated, Group: "Vault", Description: "A record was added."},
	{Type: WebhookRecordUpdated, Group: "Vault", Description: "A record changed.", Noisy: true},
	{Type: WebhookRecordDeleted, Group: "Vault", Description: "A record was deleted."},

	{Type: WebhookAttestationIssued, Group: "Identity", Description: "An attestation was accepted and issued."},
	{Type: WebhookAttestationRevoked, Group: "Identity", Description: "An attestation was revoked."},
	{Type: WebhookIdentityCreated, Group: "Identity", Description: "An identity was created."},
	{Type: WebhookIdentityRevoked, Group: "Identity", Description: "An identity was revoked."},

	{Type: WebhookMemberJoined, Group: "Workspace", Description: "Someone joined the workspace."},
	{Type: WebhookMemberUpdated, Group: "Workspace", Description: "A member's permissions changed."},
	{Type: WebhookMemberRemoved, Group: "Workspace", Description: "Someone left or was removed."},
	{Type: WebhookApiKeyCreated, Group: "Workspace", Description: "An API key was created."},
	{Type: WebhookApiKeyRevoked, Group: "Workspace", Description: "An API key was deleted."},
	{Type: WebhookConnectionApproved, Group: "Workspace", Description: "A tool was connected."},
	{Type: WebhookConnectionRevoked, Group: "Workspace", Description: "A connected tool was removed."},
}

// ValidWebhookEventType reports whether t is a subscribable type or "*".
func ValidWebhookEventType(t string) bool {
	if t == WebhookAllEvents {
		return true
	}
	return slices.ContainsFunc(WebhookEventTypes, func(e WebhookEventType) bool { return e.Type == t })
}

// WebhookSubscribes reports whether an endpoint's event list covers t. "*"
// leaves out the noisy types, which are only sent when named.
func WebhookSubscribes(events []string, t string) bool {
	if slices.Contains(events, t) {
		return true
	}
	if !slices.Contains(events, WebhookAllEvents) {
		return false
	}
	for _, e := range WebhookEventTypes {
		if e.Type == t {
			return !e.Noisy
		}
	}
	return false
}
