package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"
	"time"
)

// A public submission must leave the request owner a notification.
func TestNotificationsCreatedOnRequestSubmission(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "n-id", userID, wsID)

	slug, _ := setupRequest(t, baseURL, token, userID, wsID, identityID, map[string]any{})

	pub := testutils.NewPBClient(t, baseURL)
	pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"senderName": "external client",
		"data":       map[string]any{"hello": "world"},
	}).Expect().Status(http.StatusOK)

	// The notification itself is written synchronously; this only absorbs the
	// fire-and-forget callback goroutine on slow CI machines.
	time.Sleep(100 * time.Millisecond)

	body := api.E.GET("/api/collections/"+util.Coll.Notifications+"/records").
		WithHeader("Authorization", token).
		Expect().Status(http.StatusOK).JSON().Object()
	items := body.Value("items").Array()
	items.Length().IsEqual(1)
	first := items.Value(0).Object()
	first.Value(util.Fields.Notification.Type).String().IsEqual(util.NotificationRequestResponse)
	first.Value(util.Fields.Notification.RefCollection).String().IsEqual(util.Coll.Requests)
}
