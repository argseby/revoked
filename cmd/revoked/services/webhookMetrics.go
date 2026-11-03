package services

import (
	"sort"
	"time"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// WebhookRange is a time range the metrics cover, cut into equal buckets.
type WebhookRange struct {
	Key  string
	Span time.Duration
	Step time.Duration
}

// WebhookRanges are the ranges an endpoint's metrics can be asked for; the
// first is the default.
var WebhookRanges = []WebhookRange{
	{Key: "24h", Span: 24 * time.Hour, Step: time.Hour},
	{Key: "1h", Span: time.Hour, Step: 5 * time.Minute},
	{Key: "7d", Span: 7 * 24 * time.Hour, Step: 6 * time.Hour},
}

// WebhookRangeFor finds a range by key, or the default for anything else.
func WebhookRangeFor(key string) WebhookRange {
	for _, r := range WebhookRanges {
		if r.Key == key {
			return r
		}
	}
	return WebhookRanges[0]
}

// WebhookBucket is one slice of a range: the attempts answered with a 2xx and
// the others, and how long the endpoint took to answer.
type WebhookBucket struct {
	Start     time.Time `json:"start"`
	Delivered int       `json:"delivered"`
	Failed    int       `json:"failed"`
	P50Ms     int       `json:"p50Ms"`
	P95Ms     int       `json:"p95Ms"`
}

// WebhookCodes counts attempts by the kind of answer they got.
type WebhookCodes struct {
	Success  int `json:"2xx"`
	Client   int `json:"4xx"`
	Server   int `json:"5xx"`
	NoAnswer int `json:"none"`
}

// WebhookEventCount is how many deliveries one event type made.
type WebhookEventCount struct {
	Type  string `json:"type"`
	Count int    `json:"count"`
}

// WebhookMetrics is how an endpoint has done over a range.
type WebhookMetrics struct {
	Range      string              `json:"range"`
	Buckets    []WebhookBucket     `json:"buckets"`
	Deliveries int                 `json:"deliveries"`
	FirstTry   int                 `json:"firstTry"`
	Retrying   int                 `json:"retrying"`
	P95Ms      int                 `json:"p95Ms"`
	Codes      WebhookCodes        `json:"codes"`
	Events     []WebhookEventCount `json:"events"`
}

type webhookAttemptRow struct {
	Status   int    `db:"status"`
	Error    string `db:"error"`
	Duration int    `db:"duration"`
	Created  string `db:"created"`
}

// webhookBuckets sorts an endpoint's attempts in a range into its buckets,
// oldest first; the last bucket is the one now falls in. It also answers the
// codes and the range's own p95.
func webhookBuckets(app core.App, endpointID string, r WebhookRange, now time.Time) ([]WebhookBucket, WebhookCodes, int) {
	n := int(r.Span / r.Step)
	start := now.UTC().Truncate(r.Step).Add(-time.Duration(n-1) * r.Step)
	buckets := make([]WebhookBucket, n)
	durations := make([][]int, n)
	for i := range buckets {
		buckets[i].Start = start.Add(time.Duration(i) * r.Step)
	}

	f := util.Fields.WebhookAttempt
	var rows []webhookAttemptRow
	_ = app.DB().NewQuery(
		"SELECT [[" + f.ResponseStatus + "]] AS status, [[" + f.Error + "]] AS error, " +
			"[[" + f.DurationMs + "]] AS duration, [[" + f.Created + "]] AS created " +
			"FROM {{" + util.Coll.WebhookAttempts + "}} " +
			"WHERE [[" + f.Endpoint + "]] = {:ep} AND [[" + f.Created + "]] >= {:since}").
		Bind(dbx.Params{"ep": endpointID, "since": start.Format(types.DefaultDateLayout)}).
		All(&rows)

	var codes WebhookCodes
	var all []int
	for _, row := range rows {
		at, err := types.ParseDateTime(row.Created)
		if err != nil {
			continue
		}
		i := int(at.Time().Sub(start) / r.Step)
		if i < 0 || i >= n {
			continue
		}
		switch {
		case row.Status >= 200 && row.Status < 300:
			buckets[i].Delivered++
			codes.Success++
		case row.Status >= 400 && row.Status < 500:
			buckets[i].Failed++
			codes.Client++
		case row.Status >= 500:
			buckets[i].Failed++
			codes.Server++
		default:
			buckets[i].Failed++
			codes.NoAnswer++
		}
		if row.Duration > 0 {
			durations[i] = append(durations[i], row.Duration)
			all = append(all, row.Duration)
		}
	}
	for i := range buckets {
		buckets[i].P50Ms = percentile(durations[i], 50)
		buckets[i].P95Ms = percentile(durations[i], 95)
	}
	return buckets, codes, percentile(all, 95)
}

// percentile is the nearest-rank percentile, 0 for no values.
func percentile(values []int, p int) int {
	if len(values) == 0 {
		return 0
	}
	sorted := append([]int(nil), values...)
	sort.Ints(sorted)
	rank := (p*len(sorted) + 99) / 100
	if rank < 1 {
		rank = 1
	}
	return sorted[rank-1]
}

// WebhookSeries is the last day per hour, for the small chart beside an
// endpoint in the list.
func WebhookSeries(app core.App, endpointID string, now time.Time) []WebhookBucket {
	buckets, _, _ := webhookBuckets(app, endpointID, WebhookRangeFor("24h"), now)
	return buckets
}

// MetricsForEndpoint reports how an endpoint has done over a range: attempts
// per bucket and how long they took, the answers it gave, the deliveries
// made, how many got through on the first try, how many wait to be tried
// again, and the event types sent most.
func MetricsForEndpoint(app core.App, endpointID string, r WebhookRange, now time.Time) WebhookMetrics {
	buckets, codes, p95 := webhookBuckets(app, endpointID, r, now)
	m := WebhookMetrics{Range: r.Key, Buckets: buckets, Codes: codes, P95Ms: p95, Events: []WebhookEventCount{}}
	since := buckets[0].Start.Format(types.DefaultDateLayout)

	d := util.Fields.WebhookDelivery
	var counts struct {
		Total    int `db:"total"`
		FirstTry int `db:"first"`
	}
	_ = app.DB().NewQuery(
		"SELECT COUNT(*) AS total, " +
			"COALESCE(SUM(CASE WHEN [[" + d.Status + "]] = {:ok} AND [[" + d.Attempts + "]] = 1 THEN 1 ELSE 0 END), 0) AS first " +
			"FROM {{" + util.Coll.WebhookDeliveries + "}} " +
			"WHERE [[" + d.Endpoint + "]] = {:ep} AND [[" + d.Created + "]] >= {:since}").
		Bind(dbx.Params{"ep": endpointID, "since": since, "ok": util.WebhookDeliverySucceeded}).
		One(&counts)
	m.Deliveries, m.FirstTry = counts.Total, counts.FirstTry

	// Waiting now, whenever the delivery began: that is what needs attention.
	var retrying struct {
		N int `db:"n"`
	}
	_ = app.DB().NewQuery(
		"SELECT COUNT(*) AS n FROM {{" + util.Coll.WebhookDeliveries + "}} " +
			"WHERE [[" + d.Endpoint + "]] = {:ep} AND [[" + d.Status + "]] = {:pending} AND [[" + d.Attempts + "]] > 0").
		Bind(dbx.Params{"ep": endpointID, "pending": util.WebhookDeliveryPending}).
		One(&retrying)
	m.Retrying = retrying.N

	e := util.Fields.WebhookEvent
	_ = app.DB().NewQuery(
		"SELECT e.[[" + e.Type + "]] AS type, COUNT(*) AS count " +
			"FROM {{" + util.Coll.WebhookDeliveries + "}} d " +
			"JOIN {{" + util.Coll.WebhookEvents + "}} e ON e.[[id]] = d.[[" + d.Event + "]] " +
			"WHERE d.[[" + d.Endpoint + "]] = {:ep} AND d.[[" + d.Created + "]] >= {:since} " +
			"GROUP BY e.[[" + e.Type + "]] ORDER BY count DESC LIMIT 8").
		Bind(dbx.Params{"ep": endpointID, "since": since}).
		All(&m.Events)
	return m
}
