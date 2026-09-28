package services

import (
	"bytes"
	"encoding/json"
	"net/http"
	"revoked/util"
	"time"
)

// CallbackTimeout bounds one delivery attempt end to end. A callback fires from
// a background goroutine and is never retried, so the budget is the receiver's
// whole window: answer fast and do the work afterwards.
const CallbackTimeout = 10 * time.Second

// PostCallback delivers payload to a request's callback URL and reports the
// status the target answered with. It is the one place a callback leaves the
// server, so the test button and a real submission cannot drift apart — a test
// that took a different route would prove nothing about delivery.
//
// The target is attacker-influenced input this server fetches itself: the URL
// is validated up front and fetched through a client that refuses redirects and
// re-checks the resolved IP at connect time.
func PostCallback(url, requestID string, payload map[string]any) (int, error) {
	if err := util.ValidateCallbackURL(url); err != nil {
		return 0, err
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return 0, err
	}
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Revoked-Request", requestID)

	resp, err := util.NewSafeCallbackClient(CallbackTimeout).Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	return resp.StatusCode, nil
}

// SampleCallbackPayload is the body the test button sends: the shape of a real
// delivery with obviously fake values, plus `test: true` so a receiving
// workflow can branch on it instead of writing the example into a CRM.
func SampleCallbackPayload(requestID, slug string) map[string]any {
	return map[string]any{
		"requestId":  requestID,
		"slug":       slug,
		"responseId": "example-response-id",
		"linkId":     "example-response-id",
		"identity":   "",
		"identifier": "example-identifier",
		"senderName": "Example Responder",
		"data": map[string]any{
			"email": "ada@example.com",
			"phone": "+44 20 7946 0000",
		},
		"test": true,
	}
}
