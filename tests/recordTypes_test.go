package tests

import (
	"fmt"
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"
)

// The client offers a type per kind of value it knows how to render — a url, a
// boolean, a date — and writes that type onto the record. The collection's
// select field is what decides whether that save lands, so every type the
// catalogue names has to be one the collection accepts: when it did not, a
// date record was refused with a bare validation error and the field simply
// could not be filled.
func TestRecordAcceptsEveryDeclaredType(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	workspace := api.Get(util.Coll.Users, userID, token).
		Expect().Status(http.StatusOK).JSON().Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()

	for i, recordType := range util.RecordTypes {
		if recordType == util.TypeFile {
			// A file record carries its value in the upload, not in the field;
			// files_test.go covers that path.
			continue
		}

		t.Run(recordType, func(t *testing.T) {
			api := api.T(t)
			api.Create(util.Coll.Records, token, map[string]any{
				util.Fields.Record.Key:       fmt.Sprintf("typed_%d", i),
				util.Fields.Record.Value:     "2026-03-14T09:30",
				util.Fields.Record.Label:     "Typed record",
				util.Fields.Record.Type:      recordType,
				util.Fields.Record.Format:    util.FormatDefault,
				util.Fields.Record.User:      userID,
				util.Fields.Record.Workspace: workspace,
			}).Expect().Status(http.StatusOK)
		})
	}
}
