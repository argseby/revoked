package tests

import (
	"net/http"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"
)

// A computer shows a QR code to /app so sign-up can move to the phone. The
// page opens the app, offers a store only when the operator named one, and
// shows each phone only its own store.
func TestAppPageHandsOverToThePhone(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	const iphone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)"
	const android = "Mozilla/5.0 (Linux; Android 15; Pixel 9)"

	t.Run("it opens the app and offers no store by default", func(t *testing.T) {
		t.Setenv(util.AppStoreURLEnv, "")
		t.Setenv(util.PlayStoreURLEnv, "")
		res := api.E.GET("/app").Expect().Status(http.StatusOK)
		res.Header("Content-Security-Policy").Contains("default-src 'none'")
		body := res.Body()
		body.Contains(`href="revoked://open"`)
		body.NotContains("App Store")
		body.NotContains("Google Play")
	})

	t.Run("each phone sees only its own store", func(t *testing.T) {
		t.Setenv(util.AppStoreURLEnv, "https://apps.apple.com/app/id1")
		t.Setenv(util.PlayStoreURLEnv, "https://play.google.com/store/apps/details?id=x")

		ios := api.E.GET("/app").WithHeader("User-Agent", iphone).Expect().Body()
		ios.Contains("https://apps.apple.com/app/id1")
		ios.NotContains("play.google.com")

		droid := api.E.GET("/app").WithHeader("User-Agent", android).Expect().Body()
		droid.Contains("play.google.com")
		droid.NotContains("apps.apple.com")
	})

	t.Run("a store link that is not https is dropped", func(t *testing.T) {
		t.Setenv(util.AppStoreURLEnv, "javascript:alert(1)")
		t.Setenv(util.PlayStoreURLEnv, "http://play.example.com")
		body := api.E.GET("/app").Expect().Body()
		body.NotContains("javascript:")
		body.NotContains("play.example.com")
	})

	t.Run("German browsers get German", func(t *testing.T) {
		api.E.GET("/app").WithHeader("Accept-Language", "de-DE,de;q=0.9,en;q=0.8").
			Expect().Body().Contains("App öffnen")
	})
}
