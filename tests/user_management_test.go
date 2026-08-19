package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"

	"github.com/gavv/httpexpect/v2"
)

func TestUserManagement_Refactored(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	idA, tokenA, _ := testutils.CreateRandomUser(baseURL)
	idB, _, _ := testutils.CreateRandomUser(baseURL)

	tests := []struct {
		name           string
		method         string
		targetID       string
		body           any
		expectedStatus int
	}{
		{"Fail to update activeRole", "PATCH", idA, map[string]any{util.Fields.User.ActiveRole: "admin"}, http.StatusForbidden},
		{"Fail to update activeWorkspace", "PATCH", idA, map[string]any{util.Fields.User.ActiveWorkspace: "123"}, http.StatusForbidden},
		{"Fail to update verified status", "PATCH", idA, map[string]any{util.Fields.User.Verified: true}, http.StatusBadRequest},

		{"User A fails to update User B", "PATCH", idB, map[string]any{"name": "hacker"}, http.StatusNotFound},
		{"User A fails to delete User B", "DELETE", idB, nil, http.StatusNotFound},

		{"User A fails to create another user via standard endpoint", "POST", "", map[string]any{"email": "x@x.com", "password": "123", "passwordConfirm": "123"}, http.StatusBadRequest},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			api := api.T(t)
			var req *httpexpect.Request

			switch tc.method {
			case "PATCH":
				req = api.Update(util.Coll.Users, tc.targetID, tokenA, tc.body)
			case "DELETE":
				req = api.Delete(util.Coll.Users, tc.targetID, tokenA)
			case "POST":
				req = api.Create(util.Coll.Users, tokenA, tc.body)
			}

			api.AssertStatus(req, tc.expectedStatus)
		})
	}
}
