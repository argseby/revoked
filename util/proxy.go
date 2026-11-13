package util

import (
	"net/http"
	"net/netip"
	"os"
	"strings"
)

// TrustedProxyHeaderEnv names the header the reverse proxy puts the client's
// address in. It is applied over the dashboard's setting at every boot, so rate
// limits see real client addresses from the first start.
const TrustedProxyHeaderEnv = "TRUSTED_PROXY_HEADER"

// DefaultTrustedProxyHeader is what nginx, Caddy, Traefik and Nginx Proxy
// Manager all append the client's address to.
const DefaultTrustedProxyHeader = "X-Forwarded-For"

// TrustedProxyHeaders reads TRUSTED_PROXY_HEADER: the default when unset, none
// for `none` or `off` (a server with no proxy in front, where any client could
// write the header itself), otherwise the comma-separated names given.
func TrustedProxyHeaders() []string {
	raw, set := os.LookupEnv(TrustedProxyHeaderEnv)
	raw = strings.TrimSpace(raw)
	if !set || raw == "" {
		return []string{DefaultTrustedProxyHeader}
	}
	switch strings.ToLower(raw) {
	case "none", "off":
		return []string{}
	}
	var headers []string
	for _, h := range strings.Split(raw, ",") {
		if h = strings.TrimSpace(h); h != "" {
			headers = append(headers, http.CanonicalHeaderKey(h))
		}
	}
	return headers
}

// DashboardAccessEnv decides who reaches the superuser dashboard and the
// superuser sign-in behind it.
const DashboardAccessEnv = "DASHBOARD_ACCESS"

// DashboardIsPublic reports whether DASHBOARD_ACCESS is `public`. Anything
// else, unset included, keeps the dashboard local.
func DashboardIsPublic() bool {
	return strings.EqualFold(strings.TrimSpace(os.Getenv(DashboardAccessEnv)), "public")
}

// forwardingHeaders are the headers a reverse proxy adds. A request carrying
// any of them came through one, whatever address it arrives from.
var forwardingHeaders = []string{
	"X-Forwarded-For", "X-Forwarded-Host", "X-Forwarded-Proto",
	"X-Real-Ip", "Forwarded", "Cf-Connecting-Ip", "True-Client-Ip",
}

// IsSuperuserPath reports whether path is the dashboard or the superuser
// collection's API — its sign-in, OTP and token refresh among them.
func IsSuperuserPath(path string) bool {
	// Collections resolve by name without regard to case.
	path = strings.ToLower(path)
	return path == "/_" || strings.HasPrefix(path, "/_/") ||
		strings.HasPrefix(path, "/api/collections/_superusers/") ||
		strings.HasPrefix(path, "/api/collections/pbc_3142635823/")
}

// IsDirectRequest reports whether r reached the server without a reverse
// proxy: from the machine itself or the container's private network (an SSH
// tunnel, `curl localhost`), and with no forwarding header. The address is the
// connection's own, never a header's.
func IsDirectRequest(r *http.Request) bool {
	for _, h := range forwardingHeaders {
		if r.Header.Get(h) != "" {
			return false
		}
	}
	addr, err := netip.ParseAddrPort(r.RemoteAddr)
	var ip netip.Addr
	if err == nil {
		ip = addr.Addr()
	} else if ip, err = netip.ParseAddr(r.RemoteAddr); err != nil {
		return false
	}
	ip = ip.Unmap()
	return ip.IsLoopback() || ip.IsPrivate()
}
