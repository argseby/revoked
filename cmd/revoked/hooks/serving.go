package hooks

import (
	"net"

	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"golang.org/x/net/netutil"
)

// BindConnectionLimit bounds how many connections the server accepts at once.
//
// Every in-flight request holds request state and buffers, so without a bound
// the only one is memory: the load test OOM-killed a 512 MB instance at 6400
// concurrent connections while its CPU quota still had headroom, which turns a
// slow minute into a dead server. The limiter stops accepting rather than
// refusing, so the excess waits in the kernel's backlog and times out there —
// callers see latency and then failure, and the server stays up to serve the
// ones it already took.
func BindConnectionLimit(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		limited, err := limitListener(e.Listener, e.Server.Addr,
			util.LimitFromEnv(util.MaxOpenConnectionsEnv, util.DefaultMaxOpenConnections))
		if err != nil {
			return err
		}
		e.Listener = limited
		return e.Next()
	})
}

// limitListener wraps listener — binding addr first when there is none yet, as
// PocketBase would have — and returns it unchanged when the cap is off. A nil
// result leaves PocketBase to bind the address itself.
func limitListener(listener net.Listener, addr string, limit int) (net.Listener, error) {
	if limit <= 0 || (listener == nil && addr == "") {
		return listener, nil
	}
	if listener == nil {
		bound, err := net.Listen("tcp", addr)
		if err != nil {
			return nil, err
		}
		listener = bound
	}
	return netutil.LimitListener(listener, limit), nil
}
