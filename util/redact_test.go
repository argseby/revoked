package util

import (
	"testing"

	"github.com/pocketbase/pocketbase/tools/types"
)

// Invariant #10: audit snapshots never retain secret material.
func TestRedactAuditDataStripsSecretsKeepsTheRest(t *testing.T) {
	in := map[string]any{
		Fields.Record.Value: "sk-live-secret",
		Fields.Record.Label: "API key",
	}
	out := RedactAuditData(Coll.Records, in)

	if out[Fields.Record.Value] != AuditRedacted {
		t.Fatalf("value survived redaction: %v", out[Fields.Record.Value])
	}
	if out[Fields.Record.Label] != "API key" {
		t.Fatalf("non-secret field was damaged: %v", out[Fields.Record.Label])
	}
	if in[Fields.Record.Value] != "sk-live-secret" {
		t.Fatal("input map was mutated")
	}
}

// An empty secret stays empty: the snapshot shows whether one was set, and a
// marker on an absent password would claim there was something to hide.
func TestRedactAuditDataLeavesEmptySecretsEmpty(t *testing.T) {
	out := RedactAuditData(Coll.Links, map[string]any{
		Fields.Link.Password: "",
		Fields.Link.Data:     types.JSONRaw("null"),
	})
	if out[Fields.Link.Password] != "" {
		t.Fatalf("empty password became %v", out[Fields.Link.Password])
	}
	if string(out[Fields.Link.Data].(types.JSONRaw)) != "null" {
		t.Fatalf("empty data became %v", out[Fields.Link.Data])
	}
}

func TestRedactAuditDataRedactsPopulatedLinkData(t *testing.T) {
	out := RedactAuditData(Coll.Links, map[string]any{
		Fields.Link.Data: types.JSONRaw(`{"ssn":"123-45-6789"}`),
	})
	if out[Fields.Link.Data] != AuditRedacted {
		t.Fatalf("collected data survived redaction: %v", out[Fields.Link.Data])
	}
}

// The backfill migration re-runs redaction over rows the hook already handled.
func TestRedactAuditDataIsIdempotent(t *testing.T) {
	once := RedactAuditData(Coll.Records, map[string]any{Fields.Record.Value: "secret"})
	twice := RedactAuditData(Coll.Records, once)
	if twice[Fields.Record.Value] != AuditRedacted {
		t.Fatalf("second pass changed the marker: %v", twice[Fields.Record.Value])
	}
}

func TestRedactAuditDataPassesUnknownCollectionsThrough(t *testing.T) {
	in := map[string]any{"name": "My Workspace"}
	out := RedactAuditData(Coll.Workspaces, in)
	if out["name"] != "My Workspace" {
		t.Fatalf("uncatalogued collection was altered: %v", out)
	}
}

func TestRedactAuditDataNilStaysNil(t *testing.T) {
	if RedactAuditData(Coll.Records, nil) != nil {
		t.Fatal("nil snapshot grew content")
	}
}
