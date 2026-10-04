package services

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

const (
	// deliverySweepInterval is how often the worker looks for due deliveries
	// without being woken: retries, and rows whose wake-up raced their commit.
	deliverySweepInterval = 30 * time.Second

	// deliveryBatch bounds one pass over the outbox.
	deliveryBatch = 50

	// maxDeliveryAttempts and the delays below give a receiver about a day and
	// a half to come back before a delivery is given up on.
	maxDeliveryAttempts = 12
	firstRetryDelay     = 30 * time.Second
	maxRetryDelay       = 6 * time.Hour

	// deliveryRetention is how long a settled delivery stays in the outbox,
	// for an operator looking into one that failed.
	deliveryRetention = 7 * 24 * time.Hour
)

// errPermanent marks a refusal that retrying cannot change.
var errPermanent = errors.New("refused by receiver")

var deliveryKick = make(chan struct{}, 1)

// KickGrantDeliveries wakes the delivery worker without waiting for it.
func KickGrantDeliveries() {
	select {
	case deliveryKick <- struct{}{}:
	default:
	}
}

// enqueueDelivery writes one outbox row, due immediately. It writes through
// the app it is given, so inside a transaction the row commits or rolls back
// with the change it announces.
func enqueueDelivery(app core.App, kind, target, requestID string, payload map[string]any) error {
	col, err := app.FindCollectionByNameOrId(util.Coll.GrantDeliveries)
	if err != nil {
		return err
	}
	f := util.Fields.GrantDelivery
	row := core.NewRecord(col)
	row.Set(f.Kind, kind)
	row.Set(f.Target, target)
	row.Set(f.Request, requestID)
	row.Set(f.Payload, payload)
	row.Set(f.Attempts, 0)
	row.Set(f.NextAttemptAt, types.NowDateTime())
	return app.Save(row)
}

// RunGrantDeliveries is the outbox worker. It runs until stop is closed,
// delivering whatever is due whenever it is kicked and every sweep interval,
// and settles expired request-born links on the same beat.
func RunGrantDeliveries(app core.App, root *server.RootKey, stop <-chan struct{}) {
	ticker := time.NewTicker(deliverySweepInterval)
	defer ticker.Stop()
	for {
		deliverDue(app, root)
		select {
		case <-stop:
			return
		case <-deliveryKick:
		case <-ticker.C:
			SweepExpiredGrants(app, time.Now())
			pruneDeliveries(app, time.Now())
		}
	}
}

// deliverDue works through every due row, one batch at a time.
func deliverDue(app core.App, root *server.RootKey) {
	f := util.Fields.GrantDelivery
	for {
		rows, err := app.FindRecordsByFilter(util.Coll.GrantDeliveries,
			f.DeliveredAt+" = '' && "+f.FailedAt+" = '' && "+f.NextAttemptAt+" <= {:now}",
			f.NextAttemptAt, deliveryBatch, 0,
			dbx.Params{"now": types.NowDateTime().String()})
		if err != nil || len(rows) == 0 {
			return
		}
		for _, row := range rows {
			attemptDelivery(app, root, row)
		}
		if len(rows) < deliveryBatch {
			return
		}
	}
}

// attemptDelivery makes one attempt and records its outcome on the row.
func attemptDelivery(app core.App, root *server.RootKey, row *core.Record) {
	f := util.Fields.GrantDelivery
	attempts := row.GetInt(f.Attempts) + 1
	row.Set(f.Attempts, attempts)

	var err error
	switch row.GetString(f.Kind) {
	case util.DeliveryKindPeer:
		err = deliverPeerEvents(root, row)
	case util.DeliveryKindCallback:
		err = deliverCallbackEvent(row)
	default:
		err = fmt.Errorf("%w: unknown kind", errPermanent)
	}

	now := types.NowDateTime()
	switch {
	case err == nil:
		row.Set(f.DeliveredAt, now)
		row.Set(f.LastError, "")
	case errors.Is(err, errPermanent) || attempts >= maxDeliveryAttempts:
		row.Set(f.FailedAt, now)
		row.Set(f.LastError, truncate(err.Error(), 500))
		deliveryGivenUp(app, row, err)
	default:
		row.Set(f.NextAttemptAt, now.Add(RetryDelay(attempts)))
		row.Set(f.LastError, truncate(err.Error(), 500))
	}
	if saveErr := app.Save(row); saveErr != nil {
		app.Logger().Error("Failed to record grant delivery", "error", saveErr, "delivery", row.Id)
	}
}

// pruneDeliveries drops settled deliveries past their retention.
func pruneDeliveries(app core.App, now time.Time) {
	f := util.Fields.GrantDelivery
	cutoff := now.Add(-deliveryRetention).UTC().Format(types.DefaultDateLayout)
	if _, err := app.DB().NewQuery(
		"DELETE FROM {{" + util.Coll.GrantDeliveries + "}} WHERE " +
			"([[" + f.DeliveredAt + "]] != '' AND [[" + f.DeliveredAt + "]] < {:cutoff}) OR " +
			"([[" + f.FailedAt + "]] != '' AND [[" + f.FailedAt + "]] < {:cutoff})").
		Bind(dbx.Params{"cutoff": cutoff}).Execute(); err != nil {
		app.Logger().Error("Failed to prune grant deliveries", "error", err)
	}
}

// RetryDelay is the wait after the given number of failed attempts: doubling
// from firstRetryDelay, capped at maxRetryDelay.
func RetryDelay(attempts int) time.Duration {
	d := firstRetryDelay
	for i := 1; i < attempts; i++ {
		d *= 2
		if d >= maxRetryDelay {
			return maxRetryDelay
		}
	}
	return d
}

// deliverPeerEvents signs the queued events for the receiving server at the
// moment of sending, so every attempt carries a fresh, short-lived signature.
func deliverPeerEvents(root *server.RootKey, row *core.Record) error {
	f := util.Fields.GrantDelivery
	var payload struct {
		Events []server.GrantEvent `json:"events"`
	}
	if err := row.UnmarshalJSONField(f.Payload, &payload); err != nil {
		return fmt.Errorf("%w: unreadable payload", errPermanent)
	}
	target := row.GetString(f.Target)
	signed, err := root.SignGrantEvents(target, payload.Events, time.Now())
	if err != nil {
		return err
	}
	body, err := json.Marshal(signed)
	if err != nil {
		return err
	}
	base, _ := util.PeerBaseURL(target)
	req, err := http.NewRequest(http.MethodPost, base+"/api/grants/events", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("%w: %v", errPermanent, err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := util.NewSafeCallbackClient(CallbackTimeout).Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return classifyStatus(resp.StatusCode)
}

// deliverCallbackEvent passes one event on to a request's callback URL,
// through the same client and checks as a submission callback.
func deliverCallbackEvent(row *core.Record) error {
	f := util.Fields.GrantDelivery
	var payload map[string]any
	if err := row.UnmarshalJSONField(f.Payload, &payload); err != nil {
		return fmt.Errorf("%w: unreadable payload", errPermanent)
	}
	status, err := PostCallback(row.GetString(f.Target), row.GetString(f.Request), payload)
	if err != nil {
		if errors.Is(err, util.ErrCallbackURLBlocked) {
			return fmt.Errorf("%w: %v", errPermanent, err)
		}
		return err
	}
	return classifyStatus(status)
}

// classifyStatus treats a 2xx as delivered, a timeout, throttle or server
// error as worth retrying, and any other refusal as final.
func classifyStatus(status int) error {
	switch {
	case status >= 200 && status < 300:
		return nil
	case status == http.StatusRequestTimeout, status == http.StatusTooManyRequests, status >= 500:
		return fmt.Errorf("HTTP %d", status)
	default:
		return fmt.Errorf("%w: HTTP %s", errPermanent, strconv.Itoa(status))
	}
}

// deliveryGivenUp tells a request's owner that a callback never landed. A
// peer delivery has nobody local to tell; the log is its record.
func deliveryGivenUp(app core.App, row *core.Record, cause error) {
	f := util.Fields.GrantDelivery
	if row.GetString(f.Kind) != util.DeliveryKindCallback {
		app.Logger().Warn("Gave up delivering grant events",
			"domain", row.GetString(f.Target), "error", cause.Error())
		return
	}
	req, err := app.FindRecordById(util.Coll.Requests, row.GetString(f.Request))
	if err != nil || req == nil {
		return
	}
	EmitNotification(app, req.GetString(util.Fields.Request.User),
		req.GetString(util.Fields.Request.Workspace),
		util.NotificationCallbackFailed,
		"Callback delivery failed",
		"An update about a response to request "+req.GetString(util.Fields.Request.Slug)+
			" could not be delivered to its callback URL: "+cause.Error(),
		util.Coll.Requests, req.Id)
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}
