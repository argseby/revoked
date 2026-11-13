package util

import (
	"net/http/httptest"
	"os"
	"reflect"
	"testing"
)

func TestTrustedProxyHeaders(t *testing.T) {
	cases := []struct {
		name  string
		value *string
		want  []string
	}{
		{"unset", nil, []string{"X-Forwarded-For"}},
		{"blank", ptr("  "), []string{"X-Forwarded-For"}},
		{"none", ptr("none"), []string{}},
		{"off", ptr("OFF"), []string{}},
		{"one", ptr("x-real-ip"), []string{"X-Real-Ip"}},
		{"several", ptr("CF-Connecting-IP, X-Forwarded-For"), []string{"Cf-Connecting-Ip", "X-Forwarded-For"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if c.value == nil {
				t.Setenv(TrustedProxyHeaderEnv, "")
				unsetEnv(t, TrustedProxyHeaderEnv)
			} else {
				t.Setenv(TrustedProxyHeaderEnv, *c.value)
			}
			if got := TrustedProxyHeaders(); !reflect.DeepEqual(got, c.want) {
				t.Fatalf("got %q, want %q", got, c.want)
			}
		})
	}
}

func TestDashboardIsPublic(t *testing.T) {
	for value, want := range map[string]bool{"": false, "local": false, "public": true, " Public ": true, "yes": false} {
		t.Setenv(DashboardAccessEnv, value)
		if got := DashboardIsPublic(); got != want {
			t.Errorf("%q: got %v, want %v", value, got, want)
		}
	}
}

func TestIsSuperuserPath(t *testing.T) {
	for path, want := range map[string]bool{
		"/_/":         true,
		"/_":          true,
		"/_/images/x": true,
		"/api/collections/_superusers/auth-with-password":    true,
		"/api/collections/_SUPERUSERS/auth-with-password":    true,
		"/api/collections/pbc_3142635823/auth-with-password": true,
		"/api/collections/users/auth-with-password":          false,
		"/api/server":       false,
		"/healthz":          false,
		"/__/":              false,
		"/api/collections/": false,
	} {
		if got := IsSuperuserPath(path); got != want {
			t.Errorf("%s: got %v, want %v", path, got, want)
		}
	}
}

func TestIsDirectRequest(t *testing.T) {
	cases := []struct {
		name   string
		remote string
		header string
		want   bool
	}{
		{"loopback", "127.0.0.1:5123", "", true},
		{"loopback v6", "[::1]:5123", "", true},
		{"docker bridge", "172.17.0.1:5123", "", true},
		{"mapped private", "[::ffff:10.0.0.4]:5123", "", true},
		{"public address", "203.0.113.9:5123", "", false},
		{"proxied from loopback", "127.0.0.1:5123", "X-Forwarded-For", false},
		{"proxied with Forwarded", "172.18.0.5:5123", "Forwarded", false},
		{"proxied with X-Real-IP", "172.18.0.5:5123", "X-Real-IP", false},
		{"unparsable", "somewhere", "", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := httptest.NewRequest("GET", "/_/", nil)
			r.RemoteAddr = c.remote
			if c.header != "" {
				r.Header.Set(c.header, "198.51.100.7")
			}
			if got := IsDirectRequest(r); got != c.want {
				t.Fatalf("got %v, want %v", got, c.want)
			}
		})
	}
}

func ptr(s string) *string { return &s }

// unsetEnv removes name for the rest of the test; t.Setenv first, so it is
// restored afterwards.
func unsetEnv(t *testing.T, name string) {
	t.Helper()
	if err := os.Unsetenv(name); err != nil {
		t.Fatal(err)
	}
}
