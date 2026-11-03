package services

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// What each webhook event carries is decided here, once. Data names objects by
// id and state only: never a value, a label or a slug. A slug is the
// capability to a share, and a member allowed to manage webhooks is not
// thereby allowed to open the workspace's shares.

func linkWebhookData(link *core.Record) map[string]any {
	f := util.Fields.Link
	data := map[string]any{
		"object": "link",
		"id":     link.Id,
		"status": link.GetString(f.Status),
		"kind":   "share",
	}
	if IsRequestGrant(link) {
		data["kind"] = "answer"
	}
	if req := link.GetString(f.Request); req != "" {
		data["request"] = req
	}
	return data
}

// EmitLinkWebhook announces a link event to the link's own workspace.
func EmitLinkWebhook(app core.App, link *core.Record, eventType string, extra map[string]any) {
	data := linkWebhookData(link)
	for k, v := range extra {
		data[k] = v
	}
	EmitWebhookEvent(app, link.GetString(util.Fields.Link.Workspace), eventType, data)
}

// EmitResponseWebhook announces an answer event to the workspace that asked.
// The answer lives in the responder's workspace, so it is the request's
// workspace, not the link's, that hears about it.
func EmitResponseWebhook(app core.App, link *core.Record, eventType string, extra map[string]any) {
	reqID := link.GetString(util.Fields.Link.Request)
	if reqID == "" {
		return
	}
	req, err := app.FindRecordById(util.Coll.Requests, reqID)
	if err != nil || req == nil {
		return
	}
	data := map[string]any{
		"object":  "response",
		"id":      link.Id,
		"request": req.Id,
		"status":  link.GetString(util.Fields.Link.Status),
	}
	for k, v := range extra {
		data[k] = v
	}
	EmitWebhookEvent(app, req.GetString(util.Fields.Request.Workspace), eventType, data)
}

// EmitRemoteResponseWebhook announces an event about an answer kept on another
// server.
func EmitRemoteResponseWebhook(app core.App, rg *core.Record, eventType string) {
	f := util.Fields.RemoteGrant
	req, err := app.FindRecordById(util.Coll.Requests, rg.GetString(f.Request))
	if err != nil || req == nil {
		return
	}
	EmitWebhookEvent(app, req.GetString(util.Fields.Request.Workspace), eventType, map[string]any{
		"object":  "response",
		"id":      rg.Id,
		"request": req.Id,
		"status":  rg.GetString(f.Status),
		"server":  rg.GetString(f.Domain),
	})
}

// WebhookLinkStatusChanged announces a link moving between states, to its own
// workspace and, for an answer, to the workspace that asked.
func WebhookLinkStatusChanged(app core.App, link *core.Record, before, after string, extra map[string]any) {
	var linkEvent, responseEvent string
	switch after {
	case util.StatusPaused:
		linkEvent, responseEvent = util.WebhookLinkPaused, util.WebhookResponseChanged
	case util.StatusActive:
		if before != util.StatusPaused {
			return
		}
		linkEvent, responseEvent = util.WebhookLinkResumed, util.WebhookResponseChanged
	case util.StatusRevoked:
		linkEvent, responseEvent = util.WebhookLinkRevoked, util.WebhookResponseRevoked
	case util.StatusExpired:
		linkEvent, responseEvent = util.WebhookLinkExpired, util.WebhookResponseExpired
	default:
		return
	}
	EmitLinkWebhook(app, link, linkEvent, extra)
	EmitResponseWebhook(app, link, responseEvent, extra)
}

// WebhookRecordChanged tells every workspace whose answer reads this entry
// that the answer changed.
func WebhookRecordChanged(app core.App, recordID string) {
	for _, link := range GrantLinksForRecord(app, recordID) {
		if liveGrant(link) {
			EmitResponseWebhook(app, link, util.WebhookResponseChanged, nil)
		}
	}
}

// WebhookRecordDeleted is WebhookRecordChanged for a deleted entry: an answer
// left with nothing to read was, to its asker, taken back.
func WebhookRecordDeleted(app core.App, recordID string, links []*core.Record) {
	for _, link := range links {
		if !liveGrant(link) {
			continue
		}
		if grantStillResolves(app, link, recordID) {
			EmitResponseWebhook(app, link, util.WebhookResponseChanged, nil)
		} else {
			EmitResponseWebhook(app, link, util.WebhookResponseRevoked, map[string]any{"status": util.StatusRevoked})
		}
	}
}

func liveGrant(link *core.Record) bool {
	s := link.GetString(util.Fields.Link.Status)
	return s == util.StatusActive || s == util.StatusPaused
}
