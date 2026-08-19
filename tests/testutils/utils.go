package testutils

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"revoked/util"
	"strings"
	"time"

	"github.com/gavv/httpexpect/v2"
	"github.com/google/uuid"
)

// CreateRandomUser registers a user over the HTTP API and returns its record id
// and a real JWT for authenticating later requests.
func CreateRandomUser(baseURL string) (id string, token string, err error) {
	email := fmt.Sprintf("test-%s@example.com", uuid.New().String()[:8])
	password := "password12345"

	createData := map[string]any{
		"email":           email,
		"password":        password,
		"passwordConfirm": password,
	}
	createBody, _ := json.Marshal(createData)

	createURL := fmt.Sprintf("%s/api/collections/%s/records", baseURL, util.Coll.Users)
	resp, err := http.Post(createURL, "application/json", bytes.NewBuffer(createBody))
	if err != nil {
		return "", "", fmt.Errorf("failed to send create request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errBody any
		json.NewDecoder(resp.Body).Decode(&errBody)
		return "", "", fmt.Errorf("create user failed with status %d: %v", resp.StatusCode, errBody)
	}

	var createResult struct {
		Id string `json:"id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&createResult); err != nil {
		return "", "", fmt.Errorf("failed to decode create response: %w", err)
	}

	authData := map[string]any{
		"identity": email,
		"password": password,
	}
	authBody, _ := json.Marshal(authData)
	authURL := fmt.Sprintf("%s/api/collections/%s/auth-with-password", baseURL, util.Coll.Users)

	for i := 0; i < 5; i++ {
		authResp, err := http.Post(authURL, "application/json", bytes.NewBuffer(authBody))
		if err == nil && authResp.StatusCode == http.StatusOK {
			var authResult struct {
				Token string `json:"token"`
			}
			if err := json.NewDecoder(authResp.Body).Decode(&authResult); err == nil {
				authResp.Body.Close()
				if err := provisionWorkspace(baseURL, createResult.Id, authResult.Token); err != nil {
					return "", "", err
				}
				return createResult.Id, authResult.Token, nil
			}
		}
		if authResp != nil {
			authResp.Body.Close()
		}
		time.Sleep(200 * time.Millisecond)
	}

	return "", "", fmt.Errorf("failed to authenticate user after creation at %s", authURL)
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
