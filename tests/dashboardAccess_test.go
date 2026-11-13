package tests

import (
	"net/http"
	"reflect"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"
)

// The dashboard and the superuser sign-in answer only requests that reach the
// server directly. One that came through a reverse proxy finds nothing there,
// and never reaches the sign-in's rate limiter.
func TestDashboardIsLocalByDefault(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	// From the machine itself, as over an SSH tunnel.
	api.E.GET("/_/").Expect().Status(http.StatusOK)

	for _, header := range []string{"X-Forwarded-For", "Forwarded", "X-Real-IP"} {
		api.E.GET("/_/").WithHeader(header, "198.51.100.7").
			Expect().Status(http.StatusNotFound)
		for _, collection := range []string{"_superusers", "_SUPERUSERS", "pbc_3142635823"} {
			api.E.POST("/api/collections/"+collection+"/auth-with-password").
				WithHeader(header, "198.51.100.7").
				WithJSON(map[string]any{"identity": "nobody@test.invalid", "password": "guess"}).
				Expect().Status(http.StatusNotFound)
		}
	}

	// The rest of the API is the proxy's to reach.
	api.E.GET("/api/server").WithHeader("X-Forwarded-For", "198.51.100.7").
		Expect().Status(http.StatusOK)
}

func TestDashboardCanBePublic(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	t.Setenv(util.DashboardAccessEnv, "public")
	api.E.GET("/_/").WithHeader("X-Forwarded-For", "198.51.100.7").
		Expect().Status(http.StatusOK)
}

// Rate limits key on the client's address from the first boot: the proxy
// header is trusted without a visit to the dashboard.
func TestTrustedProxyHeaderIsAppliedAtBoot(t *testing.T) {
	_, app := testutils.SetupTestApp(t)

	got := app.Settings().TrustedProxy
	if !reflect.DeepEqual(got.Headers, []string{"X-Forwarded-For"}) || got.UseLeftmostIP {
		t.Fatalf("trusted proxy = %+v, want X-Forwarded-For with the rightmost address", got)
	}
}
