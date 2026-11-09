package services

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

const (
	webhookSweepInterval = 15 * time.Second
	webhookBatch         = 50
	webhookParallel      = 8

	// maxWebhookAttempts with RetryDelay gives a receiver about a day and a
	// half to come back.
	maxWebhookAttempts = 12

	// webhookDisableAfter is how long an endpoint may fail without a single
	// success before it is turned off and its owner told.
	webhookDisableAfter = 72 * time.Hour

	webhookRetention       = 30 * 24 * time.Hour
	webhookSecretGrace     = 24 * time.Hour
	webhookResponseBodyMax = 2048
)

var webhookKick = make(chan struct{}, 1)

// KickWebhookDeliveries wakes the webhook worker without waiting for it.
func KickWebhookDeliveries() {
	select {
	case webhookKick <- struct{}{}:
	default:
	}
}

// EmitWebhookEvent records an event for a workspace and queues it for every
// enabled endpoint there that subscribes to its type. A workspace with no such
// endpoint records nothing, so webhooks cost nothing until someone wants them.
//
// It writes through the app it is given, so inside a transaction the event
// commits or rolls back with the change it announces. It never fails the
// caller: an announcement that could not be queued must not undo the change.
func EmitWebhookEvent(app core.App, workspace, eventType string, data map[string]any) {
	if workspace == "" {
		return
	}
	endpoints := subscribedEndpoints(app, workspace, eventType)
	if len(endpoints) == 0 {
		return
	}
	event, err := createWebhookEvent(app, workspace, eventType, data, false)
	if err != nil {
		app.Logger().Error("Failed to record webhook event", "error", err, "type", eventType)
		return
	}
	for _, ep := range endpoints {
		if _, err := queueWebhookDelivery(app, event, ep); err != nil {
			app.Logger().Error("Failed to queue webhook delivery", "error", err, "endpoint", ep.Id)
		}
	}
}

// EmitWebhookEventAbout announces an event about one item of the workspace:
// only to endpoints whose creator sees the item (VISIBILITY.md), and holds
// scope too when one is given (an answer needs responses:read). An endpoint
// acts as the member who made it, as an API key does.
func EmitWebhookEventAbout(app core.App, item *core.Record, eventType string, data map[string]any, scope string) {
	readers, _ := ExpectedAccess(app, item)
	EmitWebhookEventFor(app, item.GetString(util.FieldWorkspace), eventType, data, readers, scope)
}

// EmitWebhookEventFor is EmitWebhookEventAbout with the readers worked out
// beforehand, for an item that is gone by the time the event is sent.
func EmitWebhookEventFor(app core.App, workspace, eventType string, data map[string]any, readers []string, scope string) {
	if workspace == "" {
		return
	}
	v := loadWorkspaceView(app, workspace)
	var endpoints []*core.Record
	for _, ep := range subscribedEndpoints(app, workspace, eventType) {
		user := ep.GetString(util.Fields.WebhookEndpoint.User)
		if slices.Contains(readers, user) && v.holds(user, scope) {
			endpoints = append(endpoints, ep)
		}
	}
	if len(endpoints) == 0 {
		return
	}
	event, err := createWebhookEvent(app, workspace, eventType, data, false)
	if err != nil {
		app.Logger().Error("Failed to record webhook event", "error", err, "type", eventType)
		return
	}
	for _, ep := range endpoints {
		if _, err := queueWebhookDelivery(app, event, ep); err != nil {
			app.Logger().Error("Failed to queue webhook delivery", "error", err, "endpoint", ep.Id)
		}
	}
}

func subscribedEndpoints(app core.App, workspace, eventType string) []*core.Record {
	f := util.Fields.WebhookEndpoint
	rows, err := app.FindRecordsByFilter(util.Coll.WebhookEndpoints,
		f.Workspace+" = {:w} && "+f.Enabled+" = true", "", 0, 0, dbx.Params{"w": workspace})
	if err != nil {
		return nil
	}
	out := rows[:0]
	for _, ep := range rows {
		if util.WebhookSubscribes(WebhookEndpointEvents(ep), eventType) {
			out = append(out, ep)
		}
	}
	return out
}

// WebhookEndpointEvents decodes an endpoint's subscribed types.
func WebhookEndpointEvents(ep *core.Record) []string {
	var events []string
	_ = ep.UnmarshalJSONField(util.Fields.WebhookEndpoint.Events, &events)
	return events
}

func createWebhookEvent(app core.App, workspace, eventType string, data map[string]any, test bool) (*core.Record, error) {
	col, err := app.FindCollectionByNameOrId(util.Coll.WebhookEvents)
	if err != nil {
		return nil, err
	}
	f := util.Fields.WebhookEvent
	ev := core.NewRecord(col)
	ev.Set(f.Workspace, workspace)
	ev.Set(f.Type, eventType)
	ev.Set(f.Data, data)
	ev.Set(f.Test, test)
	return ev, app.Save(ev)
}

func queueWebhookDelivery(app core.App, event, endpoint *core.Record) (*core.Record, error) {
	col, err := app.FindCollectionByNameOrId(util.Coll.WebhookDeliveries)
	if err != nil {
		return nil, err
	}
	f := util.Fields.WebhookDelivery
	d := core.NewRecord(col)
	d.Set(f.Workspace, event.GetString(util.Fields.WebhookEvent.Workspace))
	d.Set(f.Endpoint, endpoint.Id)
	d.Set(f.Event, event.Id)
	d.Set(f.Status, util.WebhookDeliveryPending)
	d.Set(f.Attempts, 0)
	d.Set(f.NextAttemptAt, types.NowDateTime())
	return d, app.Save(d)
}

// WebhookEnvelope is the body every delivery of an event carries.
func WebhookEnvelope(event *core.Record) map[string]any {
	f := util.Fields.WebhookEvent
	var data map[string]any
	_ = event.UnmarshalJSONField(f.Data, &data)
	if data == nil {
		data = map[string]any{}
	}
	env := map[string]any{
		"id":        event.Id,
		"type":      event.GetString(f.Type),
		"created":   event.GetDateTime(f.Created).Time().UTC().Format(time.RFC3339),
		"workspace": event.GetString(f.Workspace),
		"data":      data,
	}
	if event.GetBool(f.Test) {
		env["test"] = true
	}
	return env
}

// NewWebhookSecret mints a signing secret.
func NewWebhookSecret() (string, error) {
	token, err := util.GenerateToken(32)
	if err != nil {
		return "", err
	}
	return util.WebhookSecretPrefix + token, nil
}

// SignWebhook is the hex HMAC-SHA256 of "<unix seconds>.<body>". The
// timestamp is inside the MAC, so a receiver that refuses old timestamps
// cannot be fed a captured delivery again.
func SignWebhook(secret string, at time.Time, body []byte) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(strconv.FormatInt(at.Unix(), 10)))
	mac.Write([]byte("."))
	mac.Write(body)
	return hex.EncodeToString(mac.Sum(nil))
}

// webhookSignature signs with the current secret, and with the previous one
// while it is still honoured, so a receiver can switch secrets at its own pace.
func webhookSignature(ep *core.Record, at time.Time, body []byte) string {
	f := util.Fields.WebhookEndpoint
	parts := []string{
		"t=" + strconv.FormatInt(at.Unix(), 10),
		"v1=" + SignWebhook(ep.GetString(f.Secret), at, body),
	}
	if prev := ep.GetString(f.PreviousSecret); prev != "" {
		if until := ep.GetDateTime(f.PreviousSecretExpiresAt); !until.IsZero() && until.Time().After(at) {
			parts = append(parts, "v1="+SignWebhook(prev, at, body))
		}
	}
	return strings.Join(parts, ",")
}

// RotateWebhookSecret replaces an endpoint's secret and keeps the old one
// signing for a grace period.
func RotateWebhookSecret(app core.App, ep *core.Record) (string, error) {
	secret, err := NewWebhookSecret()
	if err != nil {
		return "", err
	}
	f := util.Fields.WebhookEndpoint
	ep.Set(f.PreviousSecret, ep.GetString(f.Secret))
	ep.Set(f.PreviousSecretExpiresAt, types.NowDateTime().Add(webhookSecretGrace))
	ep.Set(f.Secret, secret)
	return secret, app.Save(ep)
}

// webhookResult is what one attempt saw.
type webhookResult struct {
	status   int
	body     string
	err      error
	duration time.Duration
	// permanent marks a refusal retrying cannot change.
	permanent bool
}

func (r webhookResult) ok() bool { return r.err == nil && r.status >= 200 && r.status < 300 }

func (r webhookResult) errorText() string {
	switch {
	case r.err != nil:
		return truncate(r.err.Error(), 500)
	case !r.ok():
		return "HTTP " + strconv.Itoa(r.status)
	}
	return ""
}

func postWebhook(ep, event *core.Record) webhookResult {
	url := ep.GetString(util.Fields.WebhookEndpoint.Url)
	if err := util.ValidateCallbackURL(url); err != nil {
		return webhookResult{err: err, permanent: true}
	}
	body, err := json.Marshal(WebhookEnvelope(event))
	if err != nil {
		return webhookResult{err: err, permanent: true}
	}
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return webhookResult{err: err, permanent: true}
	}
	now := time.Now()
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "Revoked-Webhooks/1")
	req.Header.Set(util.WebhookEventIdHeader, event.Id)
	req.Header.Set(util.WebhookEventTypeHeader, event.GetString(util.Fields.WebhookEvent.Type))
	req.Header.Set(util.WebhookSignatureHeader, webhookSignature(ep, now, body))

	resp, err := util.NewSafeCallbackClient(CallbackTimeout).Do(req)
	elapsed := time.Since(now)
	if err != nil {
		return webhookResult{err: err, duration: elapsed, permanent: errors.Is(err, util.ErrCallbackURLBlocked)}
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, webhookResponseBodyMax))
	return webhookResult{
		status:   resp.StatusCode,
		body:     strings.ToValidUTF8(string(raw), "�"),
		duration: elapsed,
	}
}

// AttemptWebhookDelivery makes one attempt now and records it. A manual
// attempt is a resend: it can mark the delivery succeeded, but it neither
// counts towards nor gives up the automatic retries.
func AttemptWebhookDelivery(app core.App, delivery *core.Record, manual bool) (*core.Record, error) {
	f := util.Fields.WebhookDelivery
	ep, epErr := app.FindRecordById(util.Coll.WebhookEndpoints, delivery.GetString(f.Endpoint))
	event, evErr := app.FindRecordById(util.Coll.WebhookEvents, delivery.GetString(f.Event))
	if epErr != nil || evErr != nil {
		// A bulk prune or a workspace deleted mid-save skips the cascade, so
		// a row can outlive what it delivers; left alone it would be due forever.
		return nil, app.Delete(delivery)
	}
	if !manual && !ep.GetBool(util.Fields.WebhookEndpoint.Enabled) {
		delivery.Set(f.Status, util.WebhookDeliveryFailed)
		delivery.Set(f.LastError, "The webhook was turned off.")
		return nil, app.Save(delivery)
	}

	res := postWebhook(ep, event)
	attempt, err := recordWebhookAttempt(app, delivery, res, manual)
	if err != nil {
		app.Logger().Error("Failed to record webhook attempt", "error", err, "delivery", delivery.Id)
	}

	now := types.NowDateTime()
	delivery.Set(f.LastStatus, res.status)
	delivery.Set(f.LastError, res.errorText())
	switch {
	case res.ok():
		delivery.Set(f.Status, util.WebhookDeliverySucceeded)
		delivery.Set(f.DeliveredAt, now)
	case manual:
	default:
		attempts := delivery.GetInt(f.Attempts) + 1
		delivery.Set(f.Attempts, attempts)
		if res.permanent || attempts >= maxWebhookAttempts || event.GetBool(util.Fields.WebhookEvent.Test) {
			delivery.Set(f.Status, util.WebhookDeliveryFailed)
		} else {
			delivery.Set(f.NextAttemptAt, now.Add(RetryDelay(attempts)))
		}
	}
	if err := app.Save(delivery); err != nil {
		return attempt, err
	}
	noteEndpointHealth(app, ep, res.ok())
	return attempt, nil
}

func recordWebhookAttempt(app core.App, delivery *core.Record, res webhookResult, manual bool) (*core.Record, error) {
	col, err := app.FindCollectionByNameOrId(util.Coll.WebhookAttempts)
	if err != nil {
		return nil, err
	}
	f := util.Fields.WebhookAttempt
	a := core.NewRecord(col)
	a.Set(f.Delivery, delivery.Id)
	a.Set(f.Endpoint, delivery.GetString(util.Fields.WebhookDelivery.Endpoint))
	a.Set(f.Workspace, delivery.GetString(util.Fields.WebhookDelivery.Workspace))
	a.Set(f.ResponseStatus, res.status)
	a.Set(f.ResponseBody, res.body)
	a.Set(f.Error, res.errorText())
	a.Set(f.DurationMs, res.duration.Milliseconds())
	a.Set(f.Manual, manual)
	return a, app.Save(a)
}

// noteEndpointHealth starts or clears the failing clock the auto-disable
// reads. Only the transition is written, so a busy endpoint is not re-saved
// on every delivery.
func noteEndpointHealth(app core.App, ep *core.Record, ok bool) {
	f := util.Fields.WebhookEndpoint
	failing := !ep.GetDateTime(f.FailingSince).IsZero()
	switch {
	case ok && failing:
		ep.Set(f.FailingSince, "")
	case !ok && !failing:
		ep.Set(f.FailingSince, types.NowDateTime())
	default:
		return
	}
	if err := app.Save(ep); err != nil {
		app.Logger().Error("Failed to record webhook health", "error", err, "endpoint", ep.Id)
	}
}

// SendWebhookTest sends one sample event of the given type to one endpoint,
// now, and returns its delivery. It is tried once and never retried.
func SendWebhookTest(app core.App, ep *core.Record, eventType string) (*core.Record, error) {
	event, err := createWebhookEvent(app, ep.GetString(util.Fields.WebhookEndpoint.Workspace),
		eventType, SampleWebhookData(eventType), true)
	if err != nil {
		return nil, err
	}
	delivery, err := queueWebhookDelivery(app, event, ep)
	if err != nil {
		return nil, err
	}
	// The worker must not pick it up while this attempt is in flight.
	delivery.Set(util.Fields.WebhookDelivery.NextAttemptAt, types.NowDateTime().Add(time.Hour))
	if err := app.Save(delivery); err != nil {
		return nil, err
	}
	_, err = AttemptWebhookDelivery(app, delivery, false)
	return delivery, err
}

// SampleWebhookData is the data of a test event: the shape of the real one,
// with ids that cannot be mistaken for real ones.
func SampleWebhookData(eventType string) map[string]any {
	object, _, _ := strings.Cut(eventType, ".")
	data := map[string]any{"object": object, "id": "example_" + object}
	switch object {
	case "link":
		data["kind"] = "share"
		data["status"] = util.StatusActive
	case "response":
		data["request"] = "example_request"
		data["status"] = util.StatusActive
	case "request", "attestation", "identity":
		data["status"] = util.StatusActive
	case "record":
		data["key"] = "email"
	case "member", "apikey":
		data["user"] = "example_user"
	}
	return data
}

// ReplayWebhookDeliveries puts an endpoint's failed deliveries since a moment
// back in the queue, and reports how many.
func ReplayWebhookDeliveries(app core.App, ep *core.Record, since time.Time) (int, error) {
	f := util.Fields.WebhookDelivery
	res, err := app.DB().NewQuery(
		"UPDATE {{" + util.Coll.WebhookDeliveries + "}} SET " +
			"[[" + f.Status + "]] = {:pending}, [[" + f.Attempts + "]] = 0, [[" + f.NextAttemptAt + "]] = {:now} " +
			"WHERE [[" + f.Endpoint + "]] = {:ep} AND [[" + f.Status + "]] = {:failed} AND [[" + f.Created + "]] >= {:since}").
		Bind(dbx.Params{
			"pending": util.WebhookDeliveryPending,
			"failed":  util.WebhookDeliveryFailed,
			"now":     types.NowDateTime().String(),
			"ep":      ep.Id,
			"since":   since.UTC().Format(types.DefaultDateLayout),
		}).Execute()
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	KickWebhookDeliveries()
	return int(n), nil
}

// RunWebhookDeliveries is the webhook worker. It runs until stop is closed,
// delivering whatever is due whenever it is kicked and every sweep interval.
func RunWebhookDeliveries(app core.App, stop <-chan struct{}) {
	ticker := time.NewTicker(webhookSweepInterval)
	defer ticker.Stop()
	for {
		deliverDueWebhooks(app)
		select {
		case <-stop:
			return
		case <-webhookKick:
		case <-ticker.C:
			now := time.Now()
			sweepExpiredShares(app, now)
			disableFailingEndpoints(app, now)
			pruneWebhooks(app, now)
		}
	}
}

func deliverDueWebhooks(app core.App) {
	f := util.Fields.WebhookDelivery
	for {
		rows, err := app.FindRecordsByFilter(util.Coll.WebhookDeliveries,
			f.Status+" = {:pending} && "+f.NextAttemptAt+" <= {:now}",
			f.NextAttemptAt, webhookBatch, 0,
			dbx.Params{"pending": util.WebhookDeliveryPending, "now": types.NowDateTime().String()})
		if err != nil || len(rows) == 0 {
			return
		}
		// One slow receiver must not hold up every other workspace's events.
		sem := make(chan struct{}, webhookParallel)
		var wg sync.WaitGroup
		for _, row := range rows {
			wg.Add(1)
			sem <- struct{}{}
			go func(row *core.Record) {
				defer wg.Done()
				defer func() { <-sem }()
				if _, err := AttemptWebhookDelivery(app, row, false); err != nil {
					app.Logger().Error("Failed to deliver webhook", "error", err, "delivery", row.Id)
				}
			}(row)
		}
		wg.Wait()
		if len(rows) < webhookBatch {
			return
		}
	}
}

// sweepExpiredShares settles shares whose end date passed while nobody opened
// them, so a workspace listening for link.expired hears it on time rather
// than at the next visit. Only workspaces with an endpoint are swept.
func sweepExpiredShares(app core.App, now time.Time) {
	var ids []struct {
		Id string `db:"id"`
	}
	err := app.DB().NewQuery(
		"SELECT l.id FROM {{" + util.Coll.Links + "}} l WHERE l.status = {:active} " +
			"AND l.expiresAt != '' AND l.expiresAt < {:now} " +
			"AND l.request = '' AND l.remoteDomain = '' " +
			"AND l.workspace IN (SELECT workspace FROM {{" + util.Coll.WebhookEndpoints + "}} WHERE enabled = TRUE) " +
			"LIMIT 100").
		Bind(dbx.Params{"active": util.StatusActive, "now": now.UTC().Format(types.DefaultDateLayout)}).
		All(&ids)
	if err != nil {
		return
	}
	for _, row := range ids {
		if link, err := app.FindRecordById(util.Coll.Links, row.Id); err == nil {
			RefreshLinkStatus(app, link)
		}
	}
}

func disableFailingEndpoints(app core.App, now time.Time) {
	f := util.Fields.WebhookEndpoint
	rows, err := app.FindRecordsByFilter(util.Coll.WebhookEndpoints,
		f.Enabled+" = true && "+f.FailingSince+" != '' && "+f.FailingSince+" < {:cutoff}",
		"", 50, 0, dbx.Params{"cutoff": now.Add(-webhookDisableAfter).UTC().Format(types.DefaultDateLayout)})
	if err != nil {
		return
	}
	for _, ep := range rows {
		ep.Set(f.Enabled, false)
		ep.Set(f.DisabledReason, "failing")
		if err := app.Save(ep); err != nil {
			app.Logger().Error("Failed to turn off a failing webhook", "error", err, "endpoint", ep.Id)
			continue
		}
		EmitNotification(app, ep.GetString(f.User), ep.GetString(f.Workspace),
			util.NotificationWebhookDisabled,
			"Webhook turned off",
			"Nothing reached "+ep.GetString(f.Url)+" for three days, so it was turned off. "+
				"Fix it, turn it back on, and resend what it missed.",
			util.Coll.WebhookEndpoints, ep.Id)
	}
}

// pruneWebhooks drops what is past retention. The rows go oldest-first, each
// table on its own, because a bulk delete skips the relation cascade.
func pruneWebhooks(app core.App, now time.Time) {
	cutoff := now.Add(-webhookRetention).UTC().Format(types.DefaultDateLayout)
	for _, coll := range []string{util.Coll.WebhookAttempts, util.Coll.WebhookDeliveries, util.Coll.WebhookEvents} {
		if _, err := app.DB().NewQuery(
			"DELETE FROM {{" + coll + "}} WHERE [[created]] < {:cutoff}").
			Bind(dbx.Params{"cutoff": cutoff}).Execute(); err != nil {
			app.Logger().Error("Failed to prune webhooks", "error", err, "collection", coll)
		}
	}
}

// WebhookEndpointStats counts an endpoint's deliveries in the last day.
type WebhookEndpointStats struct {
	Succeeded int `json:"succeeded"`
	Failed    int `json:"failed"`
	Pending   int `json:"pending"`
}

// StatsForEndpoint reports the last day's deliveries to an endpoint.
func StatsForEndpoint(app core.App, endpointID string, now time.Time) WebhookEndpointStats {
	f := util.Fields.WebhookDelivery
	var rows []struct {
		Status string `db:"status"`
		N      int    `db:"n"`
	}
	_ = app.DB().NewQuery(
		"SELECT [[" + f.Status + "]] AS status, COUNT(*) AS n FROM {{" + util.Coll.WebhookDeliveries + "}} " +
			"WHERE [[" + f.Endpoint + "]] = {:ep} AND [[" + f.Created + "]] >= {:since} GROUP BY [[" + f.Status + "]]").
		Bind(dbx.Params{"ep": endpointID, "since": now.Add(-24 * time.Hour).UTC().Format(types.DefaultDateLayout)}).
		All(&rows)
	var s WebhookEndpointStats
	for _, r := range rows {
		switch r.Status {
		case util.WebhookDeliverySucceeded:
			s.Succeeded = r.N
		case util.WebhookDeliveryFailed:
			s.Failed = r.N
		case util.WebhookDeliveryPending:
			s.Pending = r.N
		}
	}
	return s
}
