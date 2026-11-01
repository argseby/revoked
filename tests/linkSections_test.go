package tests

import (
	"net/http"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/google/uuid"
)

// A link made from single records names no section, yet its page is laid out
// in the sections its owner filed those records under.
func TestLinkResolveGroupsRecordsByVaultSection(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	record := func(key, value string) string {
		return extractID(t, baseURL, util.Coll.Records, token, map[string]any{
			util.Fields.Record.Key:       key,
			util.Fields.Record.Value:     value,
			util.Fields.Record.Label:     key,
			util.Fields.Record.Type:      util.TypeText,
			util.Fields.Record.Format:    util.FormatDefault,
			util.Fields.Record.User:      userID,
			util.Fields.Record.Workspace: wsID,
		})
	}
	section := func(key, name string, records ...string) string {
		return extractID(t, baseURL, util.Coll.Sections, token, map[string]any{
			util.Fields.Section.Key:       key,
			util.Fields.Section.Name:      name,
			util.Fields.Section.User:      userID,
			util.Fields.Section.Workspace: wsID,
			util.Fields.Section.Records:   records,
		})
	}

	name := record("full_name", "Max Mustermann")
	birthday := record("birthday", "1990-01-01")
	doctor := record("doctor_name", "Dr. Beispiel")
	contact := record("contact_name", "Erika Mustermann")
	phone := record("contact_phone", "+49 30 1234567")
	loose := record("blood_type", "0+")

	// Created in another order than the link lists their records, and the
	// first holds a record the link does not grant.
	doctorSec := section("doctor", "Doctor", doctor)
	personalSec := section("personal_information", "Personal information", birthday, name)
	contactSec := section("emergency_contact", "Emergency contact", contact, phone)
	section("unrelated", "Unrelated")

	slug := "sec-" + uuid.New().String()[:8]
	extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Notfallkarte Max Mustermann",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
		util.Fields.Link.Records:   []string{name, contact, phone, loose, doctor},
	})

	check := func(t *testing.T, path, method string) {
		req := testutils.NewPBClient(t, baseURL).E.Request(method, path)
		if method == http.MethodPost {
			req = req.WithJSON(map[string]any{})
		}
		body := req.Expect().Status(http.StatusOK).JSON().Object()
		body.Value("records").Array().Length().IsEqual(5)

		sections := body.Value("sections").Array()
		sections.Length().IsEqual(3)
		want := []struct {
			id, key, name string
			records       []any
		}{
			{personalSec, "personal_information", "Personal information", []any{name}},
			{contactSec, "emergency_contact", "Emergency contact", []any{contact, phone}},
			{doctorSec, "doctor", "Doctor", []any{doctor}},
		}
		for i, w := range want {
			s := sections.Value(i).Object()
			s.Value("id").String().IsEqual(w.id)
			s.Value("key").String().IsEqual(w.key)
			s.Value("name").String().IsEqual(w.name)
			// Only what the link grants: the ungranted birthday is not named.
			s.Value("records").Array().IsEqual(w.records)
			s.NotContainsKey(util.Fields.Section.User)
			s.NotContainsKey(util.Fields.Section.Workspace)
		}
	}

	t.Run("the resolve", func(t *testing.T) {
		check(t, "/api/public/links/"+slug, http.MethodPost)
	})
	t.Run("the short JSON form", func(t *testing.T) {
		check(t, "/s/"+slug+".json", http.MethodGet)
	})
}

// A resolve lists the link's records in the order it grants them, and one that
// has since been deleted drops out without disturbing the rest — the loader
// reads them all in one query, so order is its job rather than the database's.
func TestLinkResolveKeepsGrantOrderAfterADeletion(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	record := func(key string) string {
		return extractID(t, baseURL, util.Coll.Records, token, map[string]any{
			util.Fields.Record.Key:       key,
			util.Fields.Record.Value:     key + "-value",
			util.Fields.Record.Label:     key,
			util.Fields.Record.Type:      util.TypeText,
			util.Fields.Record.Format:    util.FormatDefault,
			util.Fields.Record.User:      userID,
			util.Fields.Record.Workspace: wsID,
		})
	}

	first := record("aaa_first")
	gone := record("bbb_gone")
	third := record("ccc_third")
	fourth := record("ddd_fourth")

	// Granted in an order that matches neither creation nor any sort of the
	// keys, so a resolve that fell back to the database's order would show it.
	slug := "ord-" + uuid.New().String()[:8]
	extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Ordered share",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
		util.Fields.Link.Records:   []string{fourth, gone, first, third},
	})

	api.Delete(util.Coll.Records, gone, token).Expect().Status(http.StatusNoContent)

	want := []string{"ddd_fourth", "aaa_first", "ccc_third"}
	for _, probe := range []struct {
		path, method string
	}{
		{"/s/" + slug, http.MethodGet},
		{"/api/public/links/" + slug, http.MethodPost},
	} {
		t.Run(probe.method+" "+probe.path, func(t *testing.T) {
			req := testutils.NewPBClient(t, baseURL).E.Request(probe.method, probe.path)
			if probe.method == http.MethodPost {
				req = req.WithJSON(map[string]any{})
			}
			records := req.Expect().Status(http.StatusOK).JSON().Object().
				Value("records").Array()

			records.Length().IsEqual(len(want))
			for i, key := range want {
				records.Value(i).Object().Value(util.Fields.Record.Key).String().IsEqual(key)
			}
		})
	}
}
