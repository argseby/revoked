package util

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"syscall"
	"time"
)

// AllowPrivateCallbacksEnv opts a deployment out of the private-network block,
// for LAN-only installs. Off by default: on a public host the same capability is
// a server-side request forgery primitive.
const AllowPrivateCallbacksEnv = "ALLOW_PRIVATE_CALLBACKS"

// ErrCallbackURLBlocked is returned when a callback target is refused by policy.
var ErrCallbackURLBlocked = errors.New("callback URL blocked by policy")

func privateCallbacksAllowed() bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv(AllowPrivateCallbacksEnv)))
	return v == "1" || v == "true" || v == "yes"
}

// isBlockedIP reports whether ip points somewhere a user-supplied callback must
// never reach: loopback, link-local (the 169.254.169.254 cloud metadata
// endpoint), multicast, unspecified and private ranges.
func isBlockedIP(ip net.IP) bool {
	if ip == nil {
		return true
	}
	if ip.IsLoopback() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() ||
		ip.IsInterfaceLocalMulticast() || ip.IsMulticast() || ip.IsUnspecified() {
		return true
	}
	// IPv4-mapped IPv6 (::ffff:127.0.0.1) must be judged on the mapped address.
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}
	if ip.IsPrivate() {
		return !privateCallbacksAllowed()
	}
	// IPv6 unique-local (fc00::/7) is the v6 equivalent of a private range.
	if len(ip) == net.IPv6len && ip[0]&0xfe == 0xfc {
		return !privateCallbacksAllowed()
	}
	return false
}

// NewSafeCallbackClient returns an HTTP client hardened for delivering
// user-configured callbacks, which are attacker-controlled SSRF targets.
//
// Redirects are refused so an allowed host cannot bounce the request onward to a
// blocked one, and every dialed address is re-checked in the dialer's Control
// hook — after DNS, immediately before connect — because validating only the
// hostname loses to DNS rebinding.
func NewSafeCallbackClient(timeout time.Duration) *http.Client {
	dialer := &net.Dialer{
		Timeout:   10 * time.Second,
		KeepAlive: 10 * time.Second,
		Control: func(network, address string, _ syscall.RawConn) error {
			if network != "tcp4" && network != "tcp6" && network != "tcp" {
				return fmt.Errorf("%w: unsupported network %q", ErrCallbackURLBlocked, network)
			}
			host, _, err := net.SplitHostPort(address)
			if err != nil {
				return fmt.Errorf("%w: unparsable address", ErrCallbackURLBlocked)
			}
			if isBlockedIP(net.ParseIP(host)) {
				return fmt.Errorf("%w: %s is not a permitted destination", ErrCallbackURLBlocked, host)
			}
			return nil
		},
	}

	return &http.Client{
		Timeout: timeout,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		},
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				return dialer.DialContext(ctx, network, addr)
			},
			TLSHandshakeTimeout:   10 * time.Second,
			ResponseHeaderTimeout: 10 * time.Second,
			DisableKeepAlives:     true,
		},
	}
}

// parseAbsoluteURL requires a scheme, so a bare "example.com/hook" is rejected
// rather than silently treated as a path.
func parseAbsoluteURL(raw string) (*url.URL, error) {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil {
		return nil, fmt.Errorf("%w: unparsable URL", ErrCallbackURLBlocked)
	}
	if !u.IsAbs() {
		return nil, fmt.Errorf("%w: URL must be absolute", ErrCallbackURLBlocked)
	}
	return u, nil
}

// ValidateCallbackURL rejects a callback target on scheme and literal-IP host
// before any network activity. It is a pre-filter, not the boundary — the dialer
// Control hook in [NewSafeCallbackClient] enforces the policy at connect time.
func ValidateCallbackURL(raw string) error {
	u, err := parseAbsoluteURL(raw)
	if err != nil {
		return err
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return fmt.Errorf("%w: scheme %q is not allowed", ErrCallbackURLBlocked, u.Scheme)
	}
	host := u.Hostname()
	if host == "" {
		return fmt.Errorf("%w: missing host", ErrCallbackURLBlocked)
	}
	if ip := net.ParseIP(host); ip != nil && isBlockedIP(ip) {
		return fmt.Errorf("%w: %s is not a permitted destination", ErrCallbackURLBlocked, host)
	}
	return nil
}
