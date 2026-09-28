package tests

import (
	"net/http"
	"strings"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/google/uuid"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

func bookmarkBody(userID, slug string) map[string]any {
	return map[string]any{
		util.Fields.Bookmark.User:   userID,
		util.Fields.Bookmark.Origin: "revoked.example.com:8443",
		util.Fields.Bookmark.Slug:   slug,
		util.Fields.Bookmark.Label:  "Vendor onboarding",
	}
}

func TestBookmarksBelongToTheirOwnerOnly(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	ownerID, ownerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	strangerID, strangerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}

	id := extractID(t, baseURL, util.Coll.Bookmarks, ownerToken,
		bookmarkBody(ownerID, "bm-"+uuid.New().String()[:8]))

	t.Run("the owner lists, renames and deletes it", func(t *testing.T) {
		api := api.T(t)
		api.List(util.Coll.Bookmarks, ownerToken).Expect().Status(http.StatusOK).
			JSON().Object().Value("items").Array().Length().IsEqual(1)
		api.Update(util.Coll.Bookmarks, id, ownerToken, map[string]any{
			util.Fields.Bookmark.Label: "Renamed",
		}).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Bookmark.Label).String().IsEqual("Renamed")
	})

	t.Run("another user can neither see nor touch it", func(t *testing.T) {
		api := api.T(t)
		api.List(util.Coll.Bookmarks, strangerToken).Expect().Status(http.StatusOK).
			JSON().Object().Value("items").Array().Length().IsEqual(0)
		api.Get(util.Coll.Bookmarks, id, strangerToken).Expect().Status(http.StatusNotFound)
		api.Update(util.Coll.Bookmarks, id, strangerToken, map[string]any{
			util.Fields.Bookmark.Label: "hijacked",
		}).Expect().Status(http.StatusNotFound)
		api.Delete(util.Coll.Bookmarks, id, strangerToken).Expect().Status(http.StatusNotFound)
	})

	t.Run("nobody can file one under someone else", func(t *testing.T) {
		api := api.T(t)
		api.Create(util.Coll.Bookmarks, strangerToken,
			bookmarkBody(ownerID, "bm-"+uuid.New().String()[:8])).
			Expect().Status(http.StatusForbidden)
	})

	t.Run("the owner cannot hand it to someone else", func(t *testing.T) {
		api := api.T(t)
		// PocketBase applies an update rule as a filter, so the refusal is a 404.
		api.Update(util.Coll.Bookmarks, id, ownerToken, map[string]any{
			util.Fields.Bookmark.User: strangerID,
		}).Expect().Status(http.StatusNotFound)
		api.List(util.Coll.Bookmarks, strangerToken).Expect().Status(http.StatusOK).
			JSON().Object().Value("items").Array().Length().IsEqual(0)
	})

	t.Run("the same link is bookmarked once", func(t *testing.T) {
		api := api.T(t)
		body := bookmarkBody(ownerID, "bm-dup-"+uuid.New().String()[:8])
		api.Create(util.Coll.Bookmarks, ownerToken, body).Expect().Status(http.StatusOK)
		api.Create(util.Coll.Bookmarks, ownerToken, body).Expect().Status(http.StatusBadRequest)
	})

	t.Run("an origin that is not host[:port] is refused", func(t *testing.T) {
		api := api.T(t)
		body := bookmarkBody(ownerID, "bm-"+uuid.New().String()[:8])
		body[util.Fields.Bookmark.Origin] = "https://evil.example/path"
		api.Create(util.Coll.Bookmarks, ownerToken, body).Expect().Status(http.StatusBadRequest)
	})

	t.Run("the owner deletes it", func(t *testing.T) {
		api := api.T(t)
		api.Delete(util.Coll.Bookmarks, id, ownerToken).Expect().Status(http.StatusNoContent)
	})
}

func TestBookmarksRefuseApiKeys(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	apiKeys, _ := app.FindCollectionByNameOrId(util.Coll.ApiKeys)
	plain := uuid.New().String()
	key := core.NewRecord(apiKeys)
	key.Set("label", "every scope")
	key.Set("token", util.HashToken(plain))
	key.Set("user", userID)
	key.Set("workspace", wsID)
	key.Set("scopes", util.AllScopes)
	if err := app.Save(key); err != nil {
		t.Fatal(err)
	}

	extractID(t, baseURL, util.Coll.Bookmarks, token,
		bookmarkBody(userID, "bm-"+uuid.New().String()[:8]))

	api.List(util.Coll.Bookmarks, plain).Expect().Status(http.StatusOK).
		JSON().Object().Value("items").Array().Length().IsEqual(0)
	api.Create(util.Coll.Bookmarks, plain,
		bookmarkBody(userID, "bm-"+uuid.New().String()[:8])).
		Expect().Status(http.StatusForbidden)
}

// The slug is the capability to someone else's share, so an audit row must
// record that a bookmark was made without keeping the key to it.
func TestBookmarkSlugNeverReachesTheAuditLog(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	canary := "bm-audit-canary-" + uuid.New().String()[:8]
	id := extractID(t, baseURL, util.Coll.Bookmarks, token, bookmarkBody(userID, canary))

	rows, err := app.FindAllRecords(util.Coll.AuditLogs, dbx.HashExp{
		util.Fields.AuditLog.Collection: util.Coll.Bookmarks,
		util.Fields.AuditLog.RecordId:   id,
	})
	if err != nil {
		t.Fatalf("Failed to read audit logs: %v", err)
	}
	if len(rows) == 0 {
		t.Fatal("expected an audit row for the bookmark create")
	}
	for _, row := range rows {
		snapshot := row.GetString(util.Fields.AuditLog.OldData) +
			row.GetString(util.Fields.AuditLog.NewData)
		if strings.Contains(snapshot, canary) {
			t.Fatalf("audit row %s retained the bookmarked slug", row.Id)
		}
	}
}

func TestDeleteAccountRemovesItsBookmarks(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	extractID(t, baseURL, util.Coll.Bookmarks, token,
		bookmarkBody(userID, "bm-"+uuid.New().String()[:8]))

	api.E.DELETE("/api/account").WithHeader("Authorization", token).
		Expect().Status(http.StatusNoContent)

	left, err := app.FindAllRecords(util.Coll.Bookmarks,
		dbx.HashExp{util.Fields.Bookmark.User: userID})
	if err != nil {
		t.Fatalf("Failed to read bookmarks: %v", err)
	}
	if len(left) != 0 {
		t.Fatalf("account deletion left %d bookmarks behind", len(left))
	}
}

func TestBookmarkGroups(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	ownerID, ownerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	strangerID, strangerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}

	newGroup := func(userID, token, name string) string {
		return extractID(t, baseURL, util.Coll.BookmarkGroups, token, map[string]any{
			util.Fields.BookmarkGroup.User: userID,
			util.Fields.BookmarkGroup.Name: name,
		})
	}
	readLater := newGroup(ownerID, ownerToken, "Read later")
	work := newGroup(ownerID, ownerToken, "Work")
	bookmarkID := extractID(t, baseURL, util.Coll.Bookmarks, ownerToken,
		bookmarkBody(ownerID, "bm-"+uuid.New().String()[:8]))

	t.Run("a bookmark sits in several of its owner's groups", func(t *testing.T) {
		api := api.T(t)
		api.Update(util.Coll.Bookmarks, bookmarkID, ownerToken, map[string]any{
			util.Fields.Bookmark.Groups: []string{readLater, work},
		}).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Bookmark.Groups).Array().Length().IsEqual(2)
	})

	t.Run("another user's groups stay invisible", func(t *testing.T) {
		api := api.T(t)
		api.List(util.Coll.BookmarkGroups, strangerToken).Expect().Status(http.StatusOK).
			JSON().Object().Value("items").Array().Length().IsEqual(0)
		api.Update(util.Coll.BookmarkGroups, work, strangerToken, map[string]any{
			util.Fields.BookmarkGroup.Name: "hijacked",
		}).Expect().Status(http.StatusNotFound)
	})

	t.Run("nobody files a bookmark into a stranger's group", func(t *testing.T) {
		api := api.T(t)
		body := bookmarkBody(strangerID, "bm-"+uuid.New().String()[:8])
		body[util.Fields.Bookmark.Groups] = []string{readLater}
		api.Create(util.Coll.Bookmarks, strangerToken, body).
			Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(util.Fields.Bookmark.Groups).Object().
			Value("code").String().IsEqual(util.Errors.BookmarkGroupNotOwned.ErrorCode)
	})

	t.Run("deleting a group keeps its bookmarks", func(t *testing.T) {
		api := api.T(t)
		api.Delete(util.Coll.BookmarkGroups, work, ownerToken).
			Expect().Status(http.StatusNoContent)
		api.Get(util.Coll.Bookmarks, bookmarkID, ownerToken).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Bookmark.Groups).Array().
			IsEqual([]string{readLater})
	})

	t.Run("deleting the account removes its groups", func(t *testing.T) {
		api := api.T(t)
		api.E.DELETE("/api/account").WithHeader("Authorization", ownerToken).
			Expect().Status(http.StatusNoContent)
		left, err := app.FindAllRecords(util.Coll.BookmarkGroups,
			dbx.HashExp{util.Fields.BookmarkGroup.User: ownerID})
		if err != nil {
			t.Fatalf("Failed to read groups: %v", err)
		}
		if len(left) != 0 {
			t.Fatalf("account deletion left %d groups behind", len(left))
		}
	})
}
