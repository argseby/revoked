package testutils

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"revoked/util"
	"strings"

	"github.com/gavv/httpexpect/v2"
	"github.com/google/uuid"
)

// CreateRandomUser registers a user over the HTTP API, the way a person does —
// with a passkey — and returns its record id and a real JWT for authenticating
// later requests.
func CreateRandomUser(baseURL string) (id string, token string, err error) {
	email := fmt.Sprintf("test-%s@example.com", uuid.New().String()[:8])
	device := NewPasskeyDevice(baseURL)
	session, err := device.Register(map[string]any{"email": email})
	if err != nil {
		return "", "", err
	}
	if err := provisionWorkspace(baseURL, session.UserID, session.Token); err != nil {
		return "", "", err
	}
	return session.UserID, session.Token, nil
}

// ExtractString grabs a top-level string field from a JSON response.
func ExtractString(res *httpexpect.Response, key string) string {
	return res.JSON().Object().Value(key).String().Raw()
}

// List fetches a page of records from a collection.
func (c *PBClient) List(collection string, token string) *httpexpect.Request {
	req := c.Request("GET", collection, "/records")
	return applyAuth(req, token)
}

// provisionWorkspace gives a freshly created account a workspace and makes it
// active. Accounts no longer get one automatically — the client asks on first
// run whether to create or join — so the harness does what onboarding does,
// leaving every workspace-scoped test meaningful.
func provisionWorkspace(baseURL, userId, token string) error {
	body, _ := json.Marshal(map[string]any{
		"name": "Test Workspace",
		"slug": "ws-" + strings.ToLower(uuid.New().String()[:8]),
	})
	req, _ := http.NewRequest("POST",
		fmt.Sprintf("%s/api/collections/%s/records", baseURL, util.Coll.Workspaces),
		bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to create workspace: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		var errBody any
		json.NewDecoder(resp.Body).Decode(&errBody)
		return fmt.Errorf("create workspace failed with status %d: %v", resp.StatusCode, errBody)
	}
	var created struct {
		Id string `json:"id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&created); err != nil {
		return fmt.Errorf("failed to decode workspace: %w", err)
	}

	patch, _ := json.Marshal(map[string]any{
		"activeWorkspace": created.Id,
		"activeRole":      util.RoleAdmin,
	})
	patchReq, _ := http.NewRequest("PATCH",
		fmt.Sprintf("%s/api/collections/%s/records/%s", baseURL, util.Coll.Users, userId),
		bytes.NewBuffer(patch))
	patchReq.Header.Set("Content-Type", "application/json")
	patchReq.Header.Set("Authorization", token)

	patchResp, err := http.DefaultClient.Do(patchReq)
	if err != nil {
		return fmt.Errorf("failed to set active workspace: %w", err)
	}
	defer patchResp.Body.Close()
	if patchResp.StatusCode != http.StatusOK {
		return fmt.Errorf("set active workspace failed with status %d", patchResp.StatusCode)
	}
	return nil
}
