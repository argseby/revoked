package hooks

import (
	"net"
	"testing"
	"time"
)

func TestLimitListenerLeavesTheListenerAloneWhenTheCapIsOff(t *testing.T) {
	base, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listening: %v", err)
	}
	defer base.Close()

	got, err := limitListener(base, "", 0)
	if err != nil {
		t.Fatalf("limitListener: %v", err)
	}
	if got != base {
		t.Fatal("the listener was wrapped although the cap is off")
	}
}

// Nothing to bind and nothing bound: PocketBase binds the address itself, so a
// nil listener must come back nil rather than as a wrapper around nothing.
func TestLimitListenerReturnsNilWithNothingToBind(t *testing.T) {
	got, err := limitListener(nil, "", 100)
	if err != nil {
		t.Fatalf("limitListener: %v", err)
	}
	if got != nil {
		t.Fatal("a listener was returned with no address to bind")
	}
}

func TestLimitListenerBindsTheAddressItIsGiven(t *testing.T) {
	probe, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listening: %v", err)
	}
	addr := probe.Addr().String()
	probe.Close()

	got, err := limitListener(nil, addr, 10)
	if err != nil {
		t.Fatalf("limitListener: %v", err)
	}
	if got == nil {
		t.Fatal("no listener was bound")
	}
	defer got.Close()

	if got.Addr().String() != addr {
		t.Fatalf("bound %s, expected %s", got.Addr(), addr)
	}
}

// The property the cap exists for: past the limit a connection waits to be
// accepted instead of being taken on, which is what bounds the memory a flood
// of callers can make the server hold.
func TestLimitListenerHoldsConnectionsPastTheCap(t *testing.T) {
	base, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listening: %v", err)
	}
	limited, err := limitListener(base, "", 1)
	if err != nil {
		t.Fatalf("limitListener: %v", err)
	}
	defer limited.Close()

	for i := 0; i < 2; i++ {
		conn, dialErr := net.Dial("tcp", limited.Addr().String())
		if dialErr != nil {
			t.Fatalf("dialing: %v", dialErr)
		}
		defer conn.Close()
	}

	first, err := limited.Accept()
	if err != nil {
		t.Fatalf("accepting the first connection: %v", err)
	}

	second := make(chan net.Conn, 1)
	go func() {
		conn, acceptErr := limited.Accept()
		if acceptErr == nil {
			second <- conn
		}
	}()

	select {
	case conn := <-second:
		conn.Close()
		t.Fatal("a second connection was accepted while the cap was taken")
	case <-time.After(200 * time.Millisecond):
	}

	first.Close()

	select {
	case conn := <-second:
		conn.Close()
	case <-time.After(5 * time.Second):
		t.Fatal("no connection was accepted after the cap freed up")
	}
}
