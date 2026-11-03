package routes

import (
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// webhookSendLimiter covers sends a caller fires by hand — tests and resends —
// keyed by the caller: each one is an outbound request to a URL they chose.
var webhookSendLimiter = util.NewRateLimiter(util.LimitFromEnv("RATELIMIT_WEBHOOK_SENDS", 30), time.Minute)

const (
	webhookPageDefault = 50
	webhookPageMax     = 100
	maxWebhookEvents   = 64
)

// WebhooksRoute serves a workspace's webhooks: its endpoints, the events they
// heard about, and every delivery and attempt, with resend, replay and test.
// The collections behind it are superuser-only, so this is the one way in;
// every handler resolves the caller's workspace and the webhook:manage scope
// first, and finds rows only inside that workspace.
func WebhooksRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/webhooks/event-types", func(re *core.RequestEvent) error {
			if _, ok := webhookWorkspace(app, re); !ok {
				return nil
			}
			// Whether this server delivers to loopback and private addresses, so
			// the app can say so before someone waits for a webhook that never
			// comes. Only someone who manages webhooks gets to know.
			return re.JSON(http.StatusOK, map[string]any{
				"items":            util.WebhookEventTypes,
				"privateCallbacks": util.PrivateCallbacksAllowed(),
			})
		})
		e.Router.GET("/api/webhooks/endpoints", func(re *core.RequestEvent) error { return listWebhookEndpoints(app, re) })
		e.Router.POST("/api/webhooks/endpoints", func(re *core.RequestEvent) error { return createWebhookEndpoint(app, re) })
		e.Router.GET("/api/webhooks/endpoints/{id}", func(re *core.RequestEvent) error { return getWebhookEndpoint(app, re) })
		e.Router.PATCH("/api/webhooks/endpoints/{id}", func(re *core.RequestEvent) error { return updateWebhookEndpoint(app, re) })
		e.Router.DELETE("/api/webhooks/endpoints/{id}", func(re *core.RequestEvent) error { return deleteWebhookEndpoint(app, re) })
		e.Router.GET("/api/webhooks/endpoints/{id}/secret", func(re *core.RequestEvent) error { return revealWebhookSecret(app, re) })
		e.Router.POST("/api/webhooks/endpoints/{id}/rotate-secret", func(re *core.RequestEvent) error { return rotateWebhookSecret(app, re) })
		e.Router.POST("/api/webhooks/endpoints/{id}/test", func(re *core.RequestEvent) error { return testWebhookEndpoint(app, re) })
		e.Router.POST("/api/webhooks/endpoints/{id}/replay", func(re *core.RequestEvent) error { return replayWebhookEndpoint(app, re) })
		e.Router.GET("/api/webhooks/events", func(re *core.RequestEvent) error { return listWebhookEvents(app, re) })
		e.Router.GET("/api/webhooks/endpoints/{id}/metrics", func(re *core.RequestEvent) error { return webhookEndpointMetrics(app, re) })
		e.Router.GET("/api/webhooks/deliveries", func(re *core.RequestEvent) error { return listWebhookDeliveries(app, re) })
		e.Router.GET("/api/webhooks/deliveries/{id}", func(re *core.RequestEvent) error { return getWebhookDelivery(app, re) })
		e.Router.POST("/api/webhooks/deliveries/{id}/resend", func(re *core.RequestEvent) error { return resendWebhookDelivery(app, re) })
		return e.Next()
	})
}

// webhookWorkspace resolves the workspace the caller acts in and checks they
// may manage its webhooks, writing the refusal when not.
func webhookWorkspace(app core.App, re *core.RequestEvent) (string, bool) {
	if re.Auth == nil {
		return "", denyGate(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
	}
	var workspace string
	switch re.Auth.Collection().Name {
	case util.Coll.ApiKeys:
		workspace = re.Auth.GetString(util.Fields.ApiKey.Workspace)
	case util.Coll.Users:
		workspace = re.Auth.GetString(util.Fields.User.ActiveWorkspace)
	default:
		return "", denyGate(re, http.StatusForbidden, &util.Errors.NotAuthorized)
	}
	// AccessWorkspaceAdmin checks nothing when it is given no workspace.
	if workspace == "" {
		return "", denyGate(re, http.StatusBadRequest, &util.Errors.MissingActiveWorkspace)
	}
	spec := util.AccessSpec{Kind: util.AccessWorkspaceAdmin, Scope: util.ScopeWebhookManage}
	if errs := spec.Diagnose(app, util.AccessSubject{Auth: re.Auth, RecordWorkspace: workspace}); len(errs) > 0 {
		return "", denyGate(re, http.StatusForbidden, &util.Errors.MissingPermission)
	}
	return workspace, true
}

// webhookRow finds a row by the id in the path, inside the workspace. A row in
// another workspace answers exactly like a missing one.
func webhookRow(app core.App, re *core.RequestEvent, coll, workspace string, notFound *util.AppError) (*core.Record, bool) {
	rec, err := app.FindRecordById(coll, re.Request.PathValue("id"))
	if err != nil || rec == nil || rec.GetString(util.FieldWorkspace) != workspace {
		return nil, denyGate(re, http.StatusNotFound, notFound)
	}
	return rec, true
}

func endpointFor(app core.App, re *core.RequestEvent) (*core.Record, string, bool) {
	ws, ok := webhookWorkspace(app, re)
	if !ok {
		return nil, "", false
	}
	ep, ok := webhookRow(app, re, util.Coll.WebhookEndpoints, ws, &util.Errors.WebhookNotFound)
	return ep, ws, ok
}

func endpointJSON(app core.App, ep *core.Record) map[string]any {
	f := util.Fields.WebhookEndpoint
	return map[string]any{
		"id":             ep.Id,
		"url":            ep.GetString(f.Url),
		"description":    ep.GetString(f.Description),
		"events":         services.WebhookEndpointEvents(ep),
		"enabled":        ep.GetBool(f.Enabled),
		"disabledReason": ep.GetString(f.DisabledReason),
		"failingSince":   dateOrEmpty(ep.GetDateTime(f.FailingSince)),
		"created":        dateOrEmpty(ep.GetDateTime(f.Created)),
		"stats":          services.StatsForEndpoint(app, ep.Id, time.Now()),
		"series":         services.WebhookSeries(app, ep.Id, time.Now()),
	}
}

func dateOrEmpty(d types.DateTime) string {
	if d.IsZero() {
		return ""
	}
	return d.Time().UTC().Format(time.RFC3339)
}

func auditWebhook(app core.App, re *core.RequestEvent, action, workspace string, ep *core.Record, old map[string]any) {
	entry := services.AuditEntry{
		Action:     action,
		Collection: util.Coll.WebhookEndpoints,
		RecordId:   ep.Id,
		Workspace:  workspace,
		Ip:         re.Request.RemoteAddr,
		UserAgent:  re.Request.UserAgent(),
		OldData:    old,
	}
	if action != util.AuditActionDelete {
		entry.NewData = ep.PublicExport()
	}
	if re.Auth.Collection().Name == util.Coll.ApiKeys {
		entry.ApiKey = re.Auth.Id
		entry.User = re.Auth.GetString(util.Fields.ApiKey.User)
	} else {
		entry.User = re.Auth.Id
	}
	services.RecordAudit(app, entry)
}

type webhookEndpointBody struct {
	URL         *string   `json:"url"`
	Description *string   `json:"description"`
	Events      *[]string `json:"events"`
	Enabled     *bool     `json:"enabled"`
}

// apply validates the body and writes what it names onto ep.
func (b webhookEndpointBody) apply(ep *core.Record) *util.AppError {
	f := util.Fields.WebhookEndpoint
	if b.URL != nil {
		url := strings.TrimSpace(*b.URL)
		if url == "" || len(url) > 2048 || util.ValidateCallbackURL(url) != nil {
			return &util.Errors.WebhookUrlInvalid
		}
		ep.Set(f.Url, url)
	}
	if b.Description != nil {
		d := strings.TrimSpace(*b.Description)
		if len(d) > 200 {
			d = d[:200]
		}
		ep.Set(f.Description, d)
	}
	if b.Events != nil {
		events := []string{}
		for _, t := range *b.Events {
			t = strings.TrimSpace(t)
			if !util.ValidWebhookEventType(t) {
				return &util.Errors.WebhookEventsInvalid
			}
			if !slices.Contains(events, t) {
				events = append(events, t)
			}
		}
		if len(events) == 0 || len(events) > maxWebhookEvents {
			return &util.Errors.WebhookEventsInvalid
		}
		ep.Set(f.Events, events)
	}
	if b.Enabled != nil {
		ep.Set(f.Enabled, *b.Enabled)
		if *b.Enabled {
			ep.Set(f.DisabledReason, "")
			ep.Set(f.FailingSince, "")
		} else {
			ep.Set(f.DisabledReason, "manual")
		}
	}
	return nil
}

func listWebhookEndpoints(app core.App, re *core.RequestEvent) error {
	ws, ok := webhookWorkspace(app, re)
	if !ok {
		return nil
	}
	rows, err := app.FindRecordsByFilter(util.Coll.WebhookEndpoints,
		util.Fields.WebhookEndpoint.Workspace+" = {:w}", "-created", 0, 0, dbx.Params{"w": ws})
	if err != nil {
		return re.InternalServerError("Failed to list webhooks", nil)
	}
	items := make([]map[string]any, 0, len(rows))
	for _, ep := range rows {
		items = append(items, endpointJSON(app, ep))
	}
	return re.JSON(http.StatusOK, map[string]any{"items": items})
}

func createWebhookEndpoint(app core.App, re *core.RequestEvent) error {
	ws, ok := webhookWorkspace(app, re)
	if !ok {
		return nil
	}
	var body webhookEndpointBody
	if err := re.BindBody(&body); err != nil || body.URL == nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.WebhookUrlInvalid)
	}
	if body.Events == nil {
		body.Events = &[]string{util.WebhookAllEvents}
	}
	count, err := app.CountRecords(util.Coll.WebhookEndpoints,
		dbx.HashExp{util.Fields.WebhookEndpoint.Workspace: ws})
	if err != nil {
		return re.InternalServerError("Failed to create the webhook", nil)
	}
	if count >= util.MaxWebhookEndpoints {
		return appErrorResponse(re, http.StatusConflict, &util.Errors.WebhookLimitReached)
	}

	col, err := app.FindCollectionByNameOrId(util.Coll.WebhookEndpoints)
	if err != nil {
		return re.InternalServerError("Failed to create the webhook", nil)
	}
	f := util.Fields.WebhookEndpoint
	ep := core.NewRecord(col)
	ep.Set(f.Workspace, ws)
	ep.Set(f.Enabled, true)
	if appErr := body.apply(ep); appErr != nil {
		return appErrorResponse(re, http.StatusBadRequest, appErr)
	}
	if re.Auth.Collection().Name == util.Coll.Users {
		ep.Set(f.User, re.Auth.Id)
	} else {
		ep.Set(f.User, re.Auth.GetString(util.Fields.ApiKey.User))
	}
	secret, err := services.NewWebhookSecret()
	if err != nil {
		return re.InternalServerError("Failed to create the webhook", nil)
	}
	ep.Set(f.Secret, secret)
	if err := app.Save(ep); err != nil {
		return re.InternalServerError("Failed to create the webhook", nil)
	}
	auditWebhook(app, re, util.AuditActionCreate, ws, ep, nil)

	out := endpointJSON(app, ep)
	out["secret"] = secret
	return re.JSON(http.StatusCreated, out)
}

func getWebhookEndpoint(app core.App, re *core.RequestEvent) error {
	ep, _, ok := endpointFor(app, re)
	if !ok {
		return nil
	}
	return re.JSON(http.StatusOK, endpointJSON(app, ep))
}

// webhookEndpointMetrics answers how an endpoint has done over ?range=1h,
// 24h (the default) or 7d.
func webhookEndpointMetrics(app core.App, re *core.RequestEvent) error {
	ep, _, ok := endpointFor(app, re)
	if !ok {
		return nil
	}
	r := services.WebhookRangeFor(re.Request.URL.Query().Get("range"))
	return re.JSON(http.StatusOK, services.MetricsForEndpoint(app, ep.Id, r, time.Now()))
}

func updateWebhookEndpoint(app core.App, re *core.RequestEvent) error {
	ep, ws, ok := endpointFor(app, re)
	if !ok {
		return nil
	}
	var body webhookEndpointBody
	if err := re.BindBody(&body); err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.WebhookEventsInvalid)
	}
	old := ep.PublicExport()
	if appErr := body.apply(ep); appErr != nil {
		return appErrorResponse(re, http.StatusBadRequest, appErr)
	}
	if err := app.Save(ep); err != nil {
		return re.InternalServerError("Failed to save the webhook", nil)
	}
	auditWebhook(app, re, util.AuditActionUpdate, ws, ep, old)
	return re.JSON(http.StatusOK, endpointJSON(app, ep))
}

func deleteWebhookEndpoint(app core.App, re *core.RequestEvent) error {
	ep, ws, ok := endpointFor(app, re)
	if !ok {
		return nil
	}
	old := ep.PublicExport()
	if err := app.Delete(ep); err != nil {
		return re.InternalServerError("Failed to delete the webhook", nil)
	}
	auditWebhook(app, re, util.AuditActionDelete, ws, ep, old)
	return re.NoContent(http.StatusNoContent)
}

func revealWebhookSecret(app core.App, re *core.RequestEvent) error {
	ep, _, ok := endpointFor(app, re)
	if !ok {
		return nil
	}
	return re.JSON(http.StatusOK, map[string]any{"secret": ep.GetString(util.Fields.WebhookEndpoint.Secret)})
}

func rotateWebhookSecret(app core.App, re *core.RequestEvent) error {
	ep, ws, ok := endpointFor(app, re)
	if !ok {
		return nil
	}
	secret, err := services.RotateWebhookSecret(app, ep)
	if err != nil {
		return re.InternalServerError("Failed to rotate the secret", nil)
	}
	auditWebhook(app, re, util.AuditActionUpdate, ws, ep, nil)
	return re.JSON(http.StatusOK, map[string]any{
		"secret":                  secret,
		"previousSecretExpiresAt": dateOrEmpty(ep.GetDateTime(util.Fields.WebhookEndpoint.PreviousSecretExpiresAt)),
	})
}

func testWebhookEndpoint(app core.App, re *core.RequestEvent) error {
	ep, _, ok := endpointFor(app, re)
	if !ok {
		return nil
	}
	if !allowRequest(re, webhookSendLimiter, re.Auth.Id) {
		return rateLimitedResponse(re)
	}
	var body struct {
		Type string `json:"type"`
	}
	_ = re.BindBody(&body)
	if body.Type == "" {
		body.Type = util.WebhookLinkRevoked
	}
	if body.Type == util.WebhookAllEvents || !util.ValidWebhookEventType(body.Type) {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.WebhookEventsInvalid)
	}
	delivery, err := services.SendWebhookTest(app, ep, body.Type)
	if err != nil || delivery == nil {
		return re.InternalServerError("Failed to send the test event", nil)
	}
	return re.JSON(http.StatusOK, deliveryDetail(app, delivery))
}

func replayWebhookEndpoint(app core.App, re *core.RequestEvent) error {
	ep, _, ok := endpointFor(app, re)
	if !ok {
		return nil
	}
	if !ep.GetBool(util.Fields.WebhookEndpoint.Enabled) {
		return appErrorResponse(re, http.StatusConflict, &util.Errors.WebhookDisabled)
	}
	var body struct {
		Since string `json:"since"`
	}
	_ = re.BindBody(&body)
	since := time.Now().Add(-24 * time.Hour)
	if body.Since != "" {
		t, err := time.Parse(time.RFC3339, body.Since)
		if err != nil {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ValidationFieldRequired)
		}
		since = t
	}
	n, err := services.ReplayWebhookDeliveries(app, ep, since)
	if err != nil {
		return re.InternalServerError("Failed to queue the deliveries", nil)
	}
	return re.JSON(http.StatusOK, map[string]any{"queued": n})
}

func pageParams(re *core.RequestEvent) (page, perPage int) {
	page, _ = strconv.Atoi(re.Request.URL.Query().Get("page"))
	perPage, _ = strconv.Atoi(re.Request.URL.Query().Get("perPage"))
	if page < 1 {
		page = 1
	}
	if perPage < 1 {
		perPage = webhookPageDefault
	}
	return page, min(perPage, webhookPageMax)
}

func listWebhookEvents(app core.App, re *core.RequestEvent) error {
	ws, ok := webhookWorkspace(app, re)
	if !ok {
		return nil
	}
	f := util.Fields.WebhookEvent
	filter := f.Workspace + " = {:w}"
	params := dbx.Params{"w": ws}
	if t := re.Request.URL.Query().Get("type"); t != "" {
		filter += " && " + f.Type + " = {:t}"
		params["t"] = t
	}
	page, perPage := pageParams(re)
	rows, err := app.FindRecordsByFilter(util.Coll.WebhookEvents, filter, "-created", perPage, (page-1)*perPage, params)
	if err != nil {
		return re.InternalServerError("Failed to list events", nil)
	}
	items := make([]map[string]any, 0, len(rows))
	for _, ev := range rows {
		items = append(items, services.WebhookEnvelope(ev))
	}
	return re.JSON(http.StatusOK, map[string]any{"items": items, "page": page, "perPage": perPage})
}

func deliveryJSON(d, event *core.Record) map[string]any {
	f := util.Fields.WebhookDelivery
	out := map[string]any{
		"id":            d.Id,
		"endpoint":      d.GetString(f.Endpoint),
		"event":         d.GetString(f.Event),
		"status":        d.GetString(f.Status),
		"attempts":      d.GetInt(f.Attempts),
		"lastStatus":    d.GetInt(f.LastStatus),
		"lastError":     d.GetString(f.LastError),
		"nextAttemptAt": "",
		"deliveredAt":   dateOrEmpty(d.GetDateTime(f.DeliveredAt)),
		"created":       dateOrEmpty(d.GetDateTime(f.Created)),
	}
	if d.GetString(f.Status) == util.WebhookDeliveryPending {
		out["nextAttemptAt"] = dateOrEmpty(d.GetDateTime(f.NextAttemptAt))
	}
	if event != nil {
		out["type"] = event.GetString(util.Fields.WebhookEvent.Type)
		out["test"] = event.GetBool(util.Fields.WebhookEvent.Test)
	}
	return out
}

func listWebhookDeliveries(app core.App, re *core.RequestEvent) error {
	ws, ok := webhookWorkspace(app, re)
	if !ok {
		return nil
	}
	f := util.Fields.WebhookDelivery
	q := re.Request.URL.Query()
	filter := f.Workspace + " = {:w}"
	params := dbx.Params{"w": ws}
	if v := q.Get("endpoint"); v != "" {
		filter += " && " + f.Endpoint + " = {:ep}"
		params["ep"] = v
	}
	if v := q.Get("status"); v != "" {
		if !slices.Contains(util.WebhookDeliveryStatuses, v) {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ValidationFieldRestricted)
		}
		filter += " && " + f.Status + " = {:s}"
		params["s"] = v
	}
	if v := q.Get("event"); v != "" {
		filter += " && " + f.Event + " = {:ev}"
		params["ev"] = v
	}
	if v := q.Get("type"); v != "" {
		filter += " && " + f.Event + "." + util.Fields.WebhookEvent.Type + " = {:t}"
		params["t"] = v
	}
	page, perPage := pageParams(re)
	rows, err := app.FindRecordsByFilter(util.Coll.WebhookDeliveries, filter, "-created", perPage, (page-1)*perPage, params)
	if err != nil {
		return re.InternalServerError("Failed to list deliveries", nil)
	}
	eventIDs := make([]string, 0, len(rows))
	for _, d := range rows {
		eventIDs = append(eventIDs, d.GetString(f.Event))
	}
	events := map[string]*core.Record{}
	if found, err := app.FindRecordsByIds(util.Coll.WebhookEvents, eventIDs); err == nil {
		for _, ev := range found {
			events[ev.Id] = ev
		}
	}
	items := make([]map[string]any, 0, len(rows))
	for _, d := range rows {
		items = append(items, deliveryJSON(d, events[d.GetString(f.Event)]))
	}
	return re.JSON(http.StatusOK, map[string]any{"items": items, "page": page, "perPage": perPage})
}

func deliveryDetail(app core.App, d *core.Record) map[string]any {
	f := util.Fields.WebhookDelivery
	event, _ := app.FindRecordById(util.Coll.WebhookEvents, d.GetString(f.Event))
	out := deliveryJSON(d, event)
	if event != nil {
		out["payload"] = services.WebhookEnvelope(event)
	}
	if ep, err := app.FindRecordById(util.Coll.WebhookEndpoints, d.GetString(f.Endpoint)); err == nil {
		out["url"] = ep.GetString(util.Fields.WebhookEndpoint.Url)
	}
	a := util.Fields.WebhookAttempt
	rows, _ := app.FindRecordsByFilter(util.Coll.WebhookAttempts,
		a.Delivery+" = {:d}", "-created", 100, 0, dbx.Params{"d": d.Id})
	attempts := make([]map[string]any, 0, len(rows))
	for _, r := range rows {
		attempts = append(attempts, map[string]any{
			"id":             r.Id,
			"responseStatus": r.GetInt(a.ResponseStatus),
			"responseBody":   r.GetString(a.ResponseBody),
			"error":          r.GetString(a.Error),
			"durationMs":     r.GetInt(a.DurationMs),
			"manual":         r.GetBool(a.Manual),
			"created":        dateOrEmpty(r.GetDateTime(a.Created)),
		})
	}
	out["attemptLog"] = attempts
	return out
}

func getWebhookDelivery(app core.App, re *core.RequestEvent) error {
	ws, ok := webhookWorkspace(app, re)
	if !ok {
		return nil
	}
	d, ok := webhookRow(app, re, util.Coll.WebhookDeliveries, ws, &util.Errors.WebhookDeliveryNotFound)
	if !ok {
		return nil
	}
	return re.JSON(http.StatusOK, deliveryDetail(app, d))
}

func resendWebhookDelivery(app core.App, re *core.RequestEvent) error {
	ws, ok := webhookWorkspace(app, re)
	if !ok {
		return nil
	}
	d, ok := webhookRow(app, re, util.Coll.WebhookDeliveries, ws, &util.Errors.WebhookDeliveryNotFound)
	if !ok {
		return nil
	}
	if !allowRequest(re, webhookSendLimiter, re.Auth.Id) {
		return rateLimitedResponse(re)
	}
	if _, err := services.AttemptWebhookDelivery(app, d, true); err != nil {
		return re.InternalServerError("Failed to resend", nil)
	}
	fresh, err := app.FindRecordById(util.Coll.WebhookDeliveries, d.Id)
	if err != nil {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.WebhookDeliveryNotFound)
	}
	return re.JSON(http.StatusOK, deliveryDetail(app, fresh))
}
