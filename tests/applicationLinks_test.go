package tests

import (
	"net/http"
	"strings"
	"testing"

	"revoked/util"

	"github.com/google/uuid"
)

func (f watermarkFixture) linkOpenedCount(t *testing.T) int {
	t.Helper()
	return int(f.api.E.GET("/api/collections/"+util.Coll.Notifications+"/records").
		WithHeader("Authorization", f.token).
		WithQuery("filter", util.Fields.Notification.Type+"='"+util.NotificationLinkOpened+"'").
		Expect().Status(http.StatusOK).JSON().Object().Value("totalItems").Number().Raw())
}

func applicationFields() map[string]any {
	return map[string]any{
		util.Fields.Link.Purpose:   util.PurposeApplication,
		util.Fields.Link.Watermark: true,
	}
}

func TestApplicationLinkMustBeWatermarked(t *testing.T) {
	f := newWatermarkFixture(t)

	t.Run("created without a watermark", func(t *testing.T) {
		api := f.api.T(t)
		api.Create(util.Coll.Links, f.token, map[string]any{
			util.Fields.Link.Slug:      "app-" + uuid.New().String()[:8],
			util.Fields.Link.Label:     "Wohnungsbewerbung Musterstr. 5",
			util.Fields.Link.Status:    util.StatusActive,
			util.Fields.Link.User:      f.userID,
			util.Fields.Link.Workspace: f.wsID,
			util.Fields.Link.Records:   []string{f.pngID},
			util.Fields.Link.Purpose:   util.PurposeApplication,
		}).Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(util.Fields.Link.Watermark).Object().
			Value("code").String().IsEqual(util.Errors.ApplicationNeedsWatermark.ErrorCode)
	})

	t.Run("watermark switched off later", func(t *testing.T) {
		api := f.api.T(t)
		_, id := f.share(t, applicationFields())
		api.Update(util.Coll.Links, id, f.token, map[string]any{
			util.Fields.Link.Watermark: false,
		}).Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(util.Fields.Link.Watermark).Object().
			Value("code").String().IsEqual(util.Errors.ApplicationNeedsWatermark.ErrorCode)
	})

	t.Run("unknown purpose", func(t *testing.T) {
		api := f.api.T(t)
		api.Create(util.Coll.Links, f.token, map[string]any{
			util.Fields.Link.Slug:      "app-" + uuid.New().String()[:8],
			util.Fields.Link.Status:    util.StatusActive,
			util.Fields.Link.User:      f.userID,
			util.Fields.Link.Workspace: f.wsID,
			util.Fields.Link.Watermark: true,
			util.Fields.Link.Purpose:   "marketing",
		}).Expect().Status(http.StatusBadRequest)
	})
}

func TestApplicationFirstOpenNotifiesOnce(t *testing.T) {
	f := newWatermarkFixture(t)

	plain, _ := f.share(t, map[string]any{util.Fields.Link.Watermark: true})
	f.resolve(plain)
	if n := f.linkOpenedCount(t); n != 0 {
		t.Fatalf("a plain share emitted %d link_opened notifications", n)
	}

	slug, _ := f.share(t, applicationFields())
	f.resolve(slug)
	if n := f.linkOpenedCount(t); n != 1 {
		t.Fatalf("first open emitted %d link_opened notifications, want 1", n)
	}
	f.resolve(slug)
	if n := f.linkOpenedCount(t); n != 1 {
		t.Fatalf("second open raised the count to %d, want 1", n)
	}
}

func TestApplicationPurposeIsPublished(t *testing.T) {
	f := newWatermarkFixture(t)
	slug, _ := f.share(t, applicationFields())
	plain, _ := f.share(t, nil)

	f.api.E.GET("/api/public/links/" + slug).Expect().Status(http.StatusOK).
		JSON().Object().Value("purpose").String().IsEqual(util.PurposeApplication)
	f.api.E.GET("/api/public/links/" + plain).Expect().Status(http.StatusOK).
		JSON().Object().Value("purpose").String().IsEqual("")

	body, _ := f.resolve(slug)
	if body["purpose"] != util.PurposeApplication {
		t.Fatalf("resolve purpose = %v, want %q", body["purpose"], util.PurposeApplication)
	}
	f.api.E.GET("/s/" + slug + ".json").Expect().Status(http.StatusOK).
		JSON().Object().Value("purpose").String().IsEqual(util.PurposeApplication)

	page := f.api.E.GET("/s/"+slug).WithHeader("Accept", browserAccept).
		Expect().Status(http.StatusOK).Body().Raw()
	if !strings.Contains(page, `data-purpose="application"`) || !strings.Contains(page, "Bewerbung · ") {
		t.Fatal("the application page lacks its layout marker or heading")
	}
	plainPage := f.api.E.GET("/s/"+plain).WithHeader("Accept", browserAccept).
		Expect().Status(http.StatusOK).Body().Raw()
	if strings.Contains(plainPage, `data-purpose="application"`) {
		t.Fatal("a plain share rendered the application layout")
	}
}
