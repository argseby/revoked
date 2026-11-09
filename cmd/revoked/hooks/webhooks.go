package hooks

import (
	"slices"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// BindWebhookHooks turns writes into webhook events and runs the worker that
// delivers them.
//
// The hooks are model hooks, not request hooks, so a change the server makes
// itself (an expiry, a grant materialised from an answer) is announced exactly
// like one made through the API. Each event is written with the app the save
// ran in, after it succeeded, so a rolled-back change announces nothing.
func BindWebhookHooks(app core.App) {
	bindLinkWebhooks(app)
	bindRequestWebhooks(app)
	bindRemoteGrantWebhooks(app)
	bindRecordWebhooks(app)
	bindIdentityWebhooks(app)
	bindWorkspaceWebhooks(app)

	app.OnRecordAfterCreateSuccess(util.Coll.WebhookDeliveries).BindFunc(func(e *core.RecordEvent) error {
		services.KickWebhookDeliveries()
		return e.Next()
	})

	stop := make(chan struct{})
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		go services.RunWebhookDeliveries(app, stop)
		return e.Next()
	})
	app.OnTerminate().BindFunc(func(e *core.TerminateEvent) error {
		select {
		case <-stop:
		default:
			close(stop)
		}
		return e.Next()
	})
}

func bindLinkWebhooks(app core.App) {
	f := util.Fields.Link
	app.OnRecordCreate(util.Coll.Links).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		services.EmitLinkWebhook(e.App, e.Record, util.WebhookLinkCreated, nil)
		services.EmitResponseWebhook(e.App, e.Record, util.WebhookResponseSubmitted, nil)
		return nil
	})

	app.OnRecordUpdate(util.Coll.Links).BindFunc(func(e *core.RecordEvent) error {
		original := e.Record.Original()
		before := original.GetString(f.Status)
		contentChanged := changedAny(e.Record, original,
			f.Records, f.Sections, f.Grants, f.Data, f.Label, f.ExpiresAt, f.MaxViews,
			f.Password, f.Identity, f.RequireHandshake, f.Watermark)
		if err := e.Next(); err != nil {
			return err
		}
		after := e.Record.GetString(f.Status)
		if after != before {
			services.WebhookLinkStatusChanged(e.App, e.Record, before, after, nil)
			return nil
		}
		if contentChanged {
			services.EmitLinkWebhook(e.App, e.Record, util.WebhookLinkUpdated, nil)
			if changedAny(e.Record, original, f.Grants, f.Data) {
				services.EmitResponseWebhook(e.App, e.Record, util.WebhookResponseChanged, nil)
			}
		}
		return nil
	})

	app.OnRecordDelete(util.Coll.Links).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		if s := e.Record.GetString(f.Status); s == util.StatusActive || s == util.StatusPaused {
			deleted := map[string]any{"status": util.StatusRevoked, "deleted": true}
			services.EmitLinkWebhook(e.App, e.Record, util.WebhookLinkRevoked, deleted)
			services.EmitResponseWebhook(e.App, e.Record, util.WebhookResponseRevoked, deleted)
		}
		return nil
	})
}

func bindRequestWebhooks(app core.App) {
	f := util.Fields.Request
	data := func(req *core.Record) map[string]any {
		return map[string]any{"object": "request", "id": req.Id, "status": req.GetString(f.Status)}
	}
	app.OnRecordCreate(util.Coll.Requests).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		services.EmitWebhookEventAbout(e.App, e.Record, util.WebhookRequestCreated, data(e.Record), "")
		return nil
	})
	app.OnRecordUpdate(util.Coll.Requests).BindFunc(func(e *core.RecordEvent) error {
		before := e.Record.Original().GetString(f.Status)
		if err := e.Next(); err != nil {
			return err
		}
		after := e.Record.GetString(f.Status)
		if after == before {
			return nil
		}
		var eventType string
		switch {
		case after == util.StatusPaused:
			eventType = util.WebhookRequestPaused
		case after == util.StatusActive && before == util.StatusPaused:
			eventType = util.WebhookRequestResumed
		case after != util.StatusActive:
			eventType = util.WebhookRequestClosed
		default:
			return nil
		}
		services.EmitWebhookEventAbout(e.App, e.Record, eventType, data(e.Record), "")
		return nil
	})
	app.OnRecordDelete(util.Coll.Requests).BindFunc(func(e *core.RecordEvent) error {
		readers, _ := services.ExpectedAccess(e.App, e.Record)
		if err := e.Next(); err != nil {
			return err
		}
		if s := e.Record.GetString(f.Status); s == util.StatusActive || s == util.StatusPaused {
			d := data(e.Record)
			d["status"] = util.StatusRevoked
			d["deleted"] = true
			services.EmitWebhookEventFor(e.App, e.Record.GetString(f.Workspace), util.WebhookRequestClosed, d, readers, "")
		}
		return nil
	})
}

// Answers kept on another server reach this one as remoteGrants rows: created
// on submission, re-stamped by every event the responder's server sends.
func bindRemoteGrantWebhooks(app core.App) {
	f := util.Fields.RemoteGrant
	app.OnRecordCreate(util.Coll.RemoteGrants).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		services.EmitRemoteResponseWebhook(e.App, e.Record, util.WebhookResponseSubmitted)
		return nil
	})
	app.OnRecordUpdate(util.Coll.RemoteGrants).BindFunc(func(e *core.RecordEvent) error {
		original := e.Record.Original()
		stamped := e.Record.GetInt(f.StatusAt) != original.GetInt(f.StatusAt) && e.Record.GetInt(f.StatusAt) != 0
		reanswered := changedAny(e.Record, original, f.Token, f.Keys)
		if err := e.Next(); err != nil {
			return err
		}
		switch {
		case stamped:
			eventType := util.WebhookResponseChanged
			switch e.Record.GetString(f.Status) {
			case util.StatusRevoked:
				eventType = util.WebhookResponseRevoked
			case util.StatusExpired:
				eventType = util.WebhookResponseExpired
			}
			services.EmitRemoteResponseWebhook(e.App, e.Record, eventType)
		case reanswered:
			services.EmitRemoteResponseWebhook(e.App, e.Record, util.WebhookResponseChanged)
		}
		return nil
	})
}

func bindRecordWebhooks(app core.App) {
	f := util.Fields.Record
	data := func(rec *core.Record) map[string]any {
		return map[string]any{"object": "record", "id": rec.Id, "key": rec.GetString(f.Key)}
	}
	app.OnRecordCreate(util.Coll.Records).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		services.EmitWebhookEventAbout(e.App, e.Record, util.WebhookRecordCreated, data(e.Record), "")
		return nil
	})
	app.OnRecordUpdate(util.Coll.Records).BindFunc(func(e *core.RecordEvent) error {
		changed := recordContentChanged(e.Record) ||
			changedAny(e.Record, e.Record.Original(), f.Key, f.Sealed)
		if err := e.Next(); err != nil {
			return err
		}
		if changed {
			services.EmitWebhookEventAbout(e.App, e.Record, util.WebhookRecordUpdated, data(e.Record), "")
			services.WebhookRecordChanged(e.App, e.Record.Id)
		}
		return nil
	})
	// The answers are collected first: once the entry is gone, so are the
	// aliases that led to it.
	app.OnRecordDelete(util.Coll.Records).BindFunc(func(e *core.RecordEvent) error {
		links := services.GrantLinksForRecord(e.App, e.Record.Id)
		// Worked out while the sections still name it.
		readers, _ := services.ExpectedAccess(e.App, e.Record)
		if err := e.Next(); err != nil {
			return err
		}
		services.EmitWebhookEventFor(e.App, e.Record.GetString(f.Workspace), util.WebhookRecordDeleted, data(e.Record), readers, "")
		services.WebhookRecordDeleted(e.App, e.Record.Id, links)
		return nil
	})
}

func bindIdentityWebhooks(app core.App) {
	id := util.Fields.Identity
	app.OnRecordCreate(util.Coll.Identities).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		services.EmitWebhookEvent(e.App, e.Record.GetString(id.Workspace), util.WebhookIdentityCreated, identityData(e.Record))
		return nil
	})
	app.OnRecordUpdate(util.Coll.Identities).BindFunc(func(e *core.RecordEvent) error {
		before := e.Record.Original().GetString(id.Status)
		if err := e.Next(); err != nil {
			return err
		}
		if before != util.StatusRevoked && e.Record.GetString(id.Status) == util.StatusRevoked {
			services.EmitWebhookEvent(e.App, e.Record.GetString(id.Workspace), util.WebhookIdentityRevoked, identityData(e.Record))
		}
		return nil
	})

	at := util.Fields.Attestation
	app.OnRecordUpdate(util.Coll.Attestations).BindFunc(func(e *core.RecordEvent) error {
		before := e.Record.Original().GetString(at.Status)
		if err := e.Next(); err != nil {
			return err
		}
		after := e.Record.GetString(at.Status)
		var eventType string
		switch {
		case after == before:
			return nil
		case after == util.StatusActive:
			eventType = util.WebhookAttestationIssued
		case after == util.StatusRevoked:
			eventType = util.WebhookAttestationRevoked
		default:
			return nil
		}
		services.EmitWebhookEventAbout(e.App, e.Record, eventType, map[string]any{
			"object": "attestation",
			"id":     e.Record.Id,
			"type":   e.Record.GetString(at.Type),
			"status": after,
		}, "")
		return nil
	})
}

func identityData(rec *core.Record) map[string]any {
	f := util.Fields.Identity
	return map[string]any{
		"object":      "identity",
		"id":          rec.Id,
		"fingerprint": rec.GetString(f.Fingerprint),
		"status":      rec.GetString(f.Status),
	}
}

func bindWorkspaceWebhooks(app core.App) {
	m := util.Fields.WorkspaceMember
	member := func(rec *core.Record) map[string]any {
		return map[string]any{
			"object":      "member",
			"id":          rec.Id,
			"user":        rec.GetString(m.User),
			"permissions": util.SurfacesFor(rec.GetStringSlice(m.Permissions)),
		}
	}
	app.OnRecordCreate(util.Coll.WorkspaceMembers).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		services.EmitWebhookEvent(e.App, e.Record.GetString(m.Workspace), util.WebhookMemberJoined, member(e.Record))
		return nil
	})
	app.OnRecordUpdate(util.Coll.WorkspaceMembers).BindFunc(func(e *core.RecordEvent) error {
		before := e.Record.Original().GetStringSlice(m.Permissions)
		if err := e.Next(); err != nil {
			return err
		}
		after := e.Record.GetStringSlice(m.Permissions)
		slices.Sort(before)
		slices.Sort(after)
		if !slices.Equal(before, after) {
			services.EmitWebhookEvent(e.App, e.Record.GetString(m.Workspace), util.WebhookMemberUpdated, member(e.Record))
		}
		return nil
	})
	app.OnRecordDelete(util.Coll.WorkspaceMembers).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		services.EmitWebhookEvent(e.App, e.Record.GetString(m.Workspace), util.WebhookMemberRemoved, member(e.Record))
		return nil
	})

	k := util.Fields.ApiKey
	apiKey := func(rec *core.Record) map[string]any {
		return map[string]any{"object": "apikey", "id": rec.Id, "user": rec.GetString(k.User)}
	}
	app.OnRecordCreate(util.Coll.ApiKeys).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		services.EmitWebhookEvent(e.App, e.Record.GetString(k.Workspace), util.WebhookApiKeyCreated, apiKey(e.Record))
		return nil
	})
	app.OnRecordDelete(util.Coll.ApiKeys).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		services.EmitWebhookEvent(e.App, e.Record.GetString(k.Workspace), util.WebhookApiKeyRevoked, apiKey(e.Record))
		return nil
	})

	c := util.Fields.Connection
	connection := func(rec *core.Record) map[string]any {
		return map[string]any{"object": "connection", "id": rec.Id, "clientId": rec.GetString(c.ClientId)}
	}
	app.OnRecordCreate(util.Coll.Connections).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		services.EmitWebhookEvent(e.App, e.Record.GetString(c.Workspace), util.WebhookConnectionApproved, connection(e.Record))
		return nil
	})
	app.OnRecordDelete(util.Coll.Connections).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		services.EmitWebhookEvent(e.App, e.Record.GetString(c.Workspace), util.WebhookConnectionRevoked, connection(e.Record))
		return nil
	})
}

func changedAny(rec, original *core.Record, fields ...string) bool {
	for _, field := range fields {
		if rec.GetString(field) != original.GetString(field) {
			return true
		}
	}
	return false
}
