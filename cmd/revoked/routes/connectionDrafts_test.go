package routes

import (
	"testing"
	"time"
)

func TestDraftsExpireAndAreCappedPerConnection(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := &draftStore{drafts: map[string]*proposalDraft{}, now: func() time.Time { return now }}
	put := func(conn string) (string, bool) {
		return s.put(&proposalDraft{connection: conn, user: "u", values: map[string]string{"a": "x"},
			expires: now.Add(draftTTL)})
	}

	id, ok := put("c1")
	if !ok || !draftIDPattern.MatchString(id) || s.get(id, "u") == nil {
		t.Fatalf("draft not held: %q %v", id, ok)
	}
	if s.get(id, "someone else") != nil {
		t.Fatal("another person read the draft")
	}

	for i := 1; i < draftMaxPerConnect; i++ {
		if _, ok := put("c1"); !ok {
			t.Fatalf("draft %d refused below the cap", i)
		}
	}
	if _, ok := put("c1"); ok {
		t.Fatal("draft over the cap accepted")
	}
	if _, ok := put("c2"); !ok {
		t.Fatal("another connection's draft refused")
	}

	now = now.Add(draftTTL)
	if s.get(id, "u") != nil {
		t.Fatal("expired draft still readable")
	}
	if _, ok := put("c1"); !ok {
		t.Fatal("expired drafts still count towards the cap")
	}

	s.dropConnection("c1")
	for _, d := range s.drafts {
		if d.connection == "c1" {
			t.Fatal("a draft outlived its connection")
		}
	}
}

func TestDraftValuesAreRefusedWhole(t *testing.T) {
	if v, p := draftValues(map[string]string{"a": " x\ny ", "b_2": "z\t1"}); p != "" || v["a"] != "x\ny" {
		t.Fatalf("good values refused: %v %q", v, p)
	}
	many := map[string]string{}
	for i := 0; i <= draftMaxKeys; i++ {
		many[string(rune('a'+i%26))+string(rune('a'+i/26))] = "x"
	}
	for _, bad := range []map[string]string{nil, many, {"A": "x"}, {"a": ""}, {"a": "x\x1by"}, {"a": "\x7f"}} {
		if _, p := draftValues(bad); p == "" {
			t.Errorf("accepted %v", bad)
		}
	}
}
