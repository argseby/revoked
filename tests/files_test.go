package tests

import (
	"bytes"
	"net/http"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
	"github.com/google/uuid"
	"github.com/pocketbase/dbx"
)

// uploadFileRecord posts a multipart record create carrying one file.
func uploadFileRecord(api *testutils.PBClient, token string, fields map[string]string, filename string, content []byte) *httpexpect.Response {
	req := api.E.POST("/api/collections/"+util.Coll.Records+"/records").
		WithHeader("Authorization", token).
		WithMultipart()
	for k, v := range fields {
		req = req.WithFormField(k, v)
	}
	return req.WithFileBytes(util.Fields.Record.File, filename, content).Expect()
}

func fileRecordFields(userID, wsID, key string) map[string]string {
	return map[string]string{
		util.Fields.Record.Key:       key,
		util.Fields.Record.Label:     "File " + key,
		util.Fields.Record.Type:      util.TypeFile,
		util.Fields.Record.Format:    util.FormatDefault,
		util.Fields.Record.User:      userID,
		util.Fields.Record.Workspace: wsID,
	}
}

// A stored file must be reachable only through an owner's rule-checked token or
// a claimed public download — never through PocketBase's raw file URL. The
// field is Protected for exactly this reason; if this test fails, every vault
// file is public to anyone who learns record id + filename.
func TestFileRecordHashAndRawUrlSideDoor(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	content := []byte("%PDF-1.4 file-canary-content-2ac8")
	created := uploadFileRecord(api, token, fileRecordFields(userID, wsID, "cv"), "cv.pdf", content).
		Status(http.StatusOK).JSON().Object()

	created.Value(util.Fields.Record.Value).String().IsEmpty()
	// The uploader's own name survives; PocketBase's storage name does not.
	created.Value(util.Fields.Record.Filename).String().IsEqual("cv.pdf")
	created.Value(util.Fields.Record.ContentHash).String().Length().IsEqual(64)
	created.Value(util.Fields.Record.HashSalt).String().Length().IsEqual(32)
	created.Value(util.Fields.Record.Mime).String().IsEqual("application/pdf")
	created.Value(util.Fields.Record.Size).Number().IsEqual(len(content))

	recID := created.Value("id").String().Raw()
	filename := created.Value(util.Fields.Record.File).String().Raw()
	if filename == "" {
		t.Fatal("expected a stored filename on the created record")
	}

	api.E.GET("/api/files/" + util.Coll.Records + "/" + recID + "/" + filename).
		Expect().Status(http.StatusNotFound)
}

// The resolve claims the view once; the download token carries that claim to
// the byte endpoint. A token is single-use and useless for any other record.
func TestFileDownloadTokenFlow(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	content := []byte("file-download-canary-91d3")
	recID := uploadFileRecord(api, token, fileRecordFields(userID, wsID, "doc"), "doc.txt", content).
		Status(http.StatusOK).JSON().Object().Value("id").String().Raw()

	slug := "file-dl-" + uuid.New().String()[:8]
	extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "File share",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
		util.Fields.Link.Records:   []string{recID},
	})

	resolved := api.E.POST("/api/public/links/" + slug).Expect().
		Status(http.StatusOK).JSON().Object()
	entry := resolved.Value("records").Array().Value(0).Object()
	entry.Value("type").String().IsEqual(util.TypeFile)
	entry.Value("contentHash").String().Length().IsEqual(64)
	entry.Value("filename").String().IsEqual("doc.txt")
	entry.NotContainsKey("file")
	entry.Value("size").Number().IsEqual(len(content))
	entry.NotContainsKey("hashSalt")
	entry.NotContainsKey("value")
	dlToken := entry.Value("downloadToken").String().NotEmpty().Raw()

	download := api.E.GET("/api/public/links/"+slug+"/files/"+recID).
		WithQuery("dl", dlToken).Expect().Status(http.StatusOK)
	download.Header("Content-Disposition").Contains("attachment")
	download.Header("Content-Disposition").Contains("doc.txt")
	download.Header("X-Content-Type-Options").IsEqual("nosniff")
	download.Body().IsEqual(string(content))

	// Spent tokens and unknown tokens read the same: no bytes.
	api.E.GET("/api/public/links/"+slug+"/files/"+recID).
		WithQuery("dl", dlToken).Expect().Status(http.StatusUnauthorized)
	api.E.GET("/api/public/links/"+slug+"/files/"+recID).
		WithQuery("dl", "not-a-token").Expect().Status(http.StatusUnauthorized)
}

// One human read of a file share costs one view: the download rides the
// resolve's claim instead of claiming again, and a spent cap refuses the next
// resolve rather than the pending download.
func TestFileShareViewCapSemantics(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	content := []byte("capped-file-content-55aa")
	recID := uploadFileRecord(api, token, fileRecordFields(userID, wsID, "capped"), "capped.txt", content).
		Status(http.StatusOK).JSON().Object().Value("id").String().Raw()

	slug := "file-cap-" + uuid.New().String()[:8]
	extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Capped file share",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
		util.Fields.Link.Records:   []string{recID},
		util.Fields.Link.MaxViews:  1,
	})

	dlToken := api.E.POST("/api/public/links/" + slug).Expect().
		Status(http.StatusOK).JSON().Object().
		Value("records").Array().Value(0).Object().
		Value("downloadToken").String().NotEmpty().Raw()

	api.E.GET("/api/public/links/"+slug+"/files/"+recID).
		WithQuery("dl", dlToken).Expect().Status(http.StatusOK)

	if status := api.E.POST("/api/public/links/" + slug).Expect().Raw().StatusCode; status < 400 {
		t.Fatalf("expected the second resolve to be refused after the cap, got %d", status)
	}
}

// Files and the file type stay coupled, and a reference record can never be a
// file.
func TestFileRecordValidation(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	textWithFile := fileRecordFields(userID, wsID, "smuggle")
	textWithFile[util.Fields.Record.Type] = util.TypeText
	textWithFile[util.Fields.Record.Value] = "v"
	uploadFileRecord(api, token, textWithFile, "smuggle.txt", []byte("x")).
		Status(http.StatusBadRequest).Body().Contains(util.Errors.FileNotAllowed.ErrorCode)

	api.Create(util.Coll.Records, token, map[string]any{
		util.Fields.Record.Key:       "empty-file",
		util.Fields.Record.Label:     "Empty file",
		util.Fields.Record.Type:      util.TypeFile,
		util.Fields.Record.Format:    util.FormatDefault,
		util.Fields.Record.User:      userID,
		util.Fields.Record.Workspace: wsID,
	}).Expect().Status(http.StatusBadRequest).Body().Contains(util.Errors.FileRequired.ErrorCode)

	parentID := extractID(t, baseURL, util.Coll.Records, token, map[string]any{
		util.Fields.Record.Key:       "alias-parent",
		util.Fields.Record.Value:     "v",
		util.Fields.Record.Label:     "Parent",
		util.Fields.Record.Type:      util.TypeText,
		util.Fields.Record.Format:    util.FormatDefault,
		util.Fields.Record.User:      userID,
		util.Fields.Record.Workspace: wsID,
	})
	aliasFile := fileRecordFields(userID, wsID, "alias-file")
	aliasFile[util.Fields.Record.AliasOf] = parentID
	uploadFileRecord(api, token, aliasFile, "alias.txt", []byte("x")).
		Status(http.StatusBadRequest).Body().Contains(util.Errors.FileAliasUnsupported.ErrorCode)
}

// The operator's env policy is enforced at request time: FILE_MAX_SIZE caps a
// single file, FILE_MAX_STORAGE caps a workspace's total.
func TestFileEnvLimits(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	t.Setenv(util.FileMaxSizeEnv, "1")
	uploadFileRecord(api, token, fileRecordFields(userID, wsID, "too-big"), "big.bin", bytes.Repeat([]byte{7}, 2<<20)).
		Status(http.StatusBadRequest).Body().Contains(util.Errors.FileTooLarge.ErrorCode)
	uploadFileRecord(api, token, fileRecordFields(userID, wsID, "small-enough"), "small.bin", bytes.Repeat([]byte{7}, 100<<10)).
		Status(http.StatusOK)

	t.Setenv(util.FileMaxStorageEnv, "1")
	uploadFileRecord(api, token, fileRecordFields(userID, wsID, "fills-quota"), "fill.bin", bytes.Repeat([]byte{7}, 600<<10)).
		Status(http.StatusOK)
	uploadFileRecord(api, token, fileRecordFields(userID, wsID, "over-quota"), "over.bin", bytes.Repeat([]byte{7}, 600<<10)).
		Status(http.StatusBadRequest).Body().Contains(util.Errors.FileStorageExceeded.ErrorCode)
}

// An audit snapshot keeps the fact that a file exists, never the filename or
// the salt: the filename is content ("kuendigung.pdf" says plenty) and salt
// plus public hash is a guessing oracle for recognizable documents.
func TestFileAuditRedactsFilenameAndSalt(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	created := uploadFileRecord(api, token, fileRecordFields(userID, wsID, "audit-file"), "geheimcanary77f1.pdf", []byte("%PDF-1.4 audit")).
		Status(http.StatusOK).JSON().Object()
	saltHex := created.Value(util.Fields.Record.HashSalt).String().NotEmpty().Raw()

	rows, err := app.FindAllRecords(util.Coll.AuditLogs,
		dbx.HashExp{util.Fields.AuditLog.Workspace: wsID})
	if err != nil {
		t.Fatalf("Failed to read audit logs: %v", err)
	}
	if len(rows) == 0 {
		t.Fatal("expected an audit row for the file record create")
	}
	sawRedaction := false
	for _, row := range rows {
		snapshot := row.GetString(util.Fields.AuditLog.OldData) +
			row.GetString(util.Fields.AuditLog.NewData)
		if bytes.Contains([]byte(snapshot), []byte("geheimcanary77f1")) {
			t.Fatalf("audit snapshot retained the filename: %s", snapshot)
		}
		if bytes.Contains([]byte(snapshot), []byte(saltHex)) {
			t.Fatalf("audit snapshot retained the hash salt: %s", snapshot)
		}
		if bytes.Contains([]byte(snapshot), []byte(util.AuditRedacted)) {
			sawRedaction = true
		}
	}
	if !sawRedaction {
		t.Fatal("expected at least one redaction marker in the audit rows")
	}
}

// A file record is editable like any other: label, visibility and the name the
// reader sees are metadata, and renaming never touches the bytes. The name
// belongs to the record, so replacing the file behind a share keeps serving it
// under the name the recipient already knows.
func TestFileRecordRenameAndMetadataEdits(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	created := uploadFileRecord(api, token, fileRecordFields(userID, wsID, "cv"), "scan_001.pdf", []byte("%PDF-1.4 v1")).
		Status(http.StatusOK).JSON().Object()
	recID := created.Value("id").String().Raw()
	created.Value(util.Fields.Record.Filename).String().IsEqual("scan_001.pdf")
	firstHash := created.Value(util.Fields.Record.ContentHash).String().Raw()

	edited := api.Update(util.Coll.Records, recID, token, map[string]any{
		util.Fields.Record.Filename: "Lebenslauf.pdf",
		util.Fields.Record.Label:    "Mein Lebenslauf",
		util.Fields.Record.Format:   util.FormatHidden,
	}).Expect().Status(http.StatusOK).JSON().Object()
	edited.Value(util.Fields.Record.Filename).String().IsEqual("Lebenslauf.pdf")
	edited.Value(util.Fields.Record.Label).String().IsEqual("Mein Lebenslauf")
	edited.Value(util.Fields.Record.Format).String().IsEqual(util.FormatHidden)
	// A rename is metadata only: the bytes, and therefore the hash, are untouched.
	edited.Value(util.Fields.Record.ContentHash).String().IsEqual(firstHash)

	replaced := api.E.PATCH("/api/collections/"+util.Coll.Records+"/records/"+recID).
		WithHeader("Authorization", token).
		WithMultipart().
		WithFileBytes(util.Fields.Record.File, "irgendwas_v2.pdf", []byte("%PDF-1.4 v2-neue-fassung")).
		Expect().Status(http.StatusOK).JSON().Object()
	replaced.Value(util.Fields.Record.Filename).String().IsEqual("Lebenslauf.pdf")
	if replaced.Value(util.Fields.Record.ContentHash).String().Raw() == firstHash {
		t.Fatal("replacing the file must change the content hash")
	}
}

// A name is a label, never a location.
func TestFileRecordNameCannotTraverse(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	recID := uploadFileRecord(api, token, fileRecordFields(userID, wsID, "doc"), "doc.txt", []byte("x")).
		Status(http.StatusOK).JSON().Object().Value("id").String().Raw()

	for _, bad := range []string{"../../etc/passwd", `..\\windows\\system32`, "", "   "} {
		api.Update(util.Coll.Records, recID, token, map[string]any{
			util.Fields.Record.Filename: bad,
		}).Expect().Status(http.StatusBadRequest).
			Body().Contains(util.Errors.FileNameInvalid.ErrorCode)
	}

	// The stored name is unchanged by every rejected attempt.
	api.Get(util.Coll.Records, recID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Record.Filename).String().IsEqual("doc.txt")
}
