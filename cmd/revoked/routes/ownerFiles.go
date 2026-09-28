package routes

import (
	"net/http"
	"path/filepath"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"strings"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// OwnerFilesRoute lets a signed-in owner see what a stamp does to a file before
// sharing it, and download a share's files as they would be handed out. Access
// is decided by the collections' own view rules, so anything these routes
// return is something the caller could already read.
func OwnerFilesRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.POST("/api/stamp-preview", func(re *core.RequestEvent) error {
			if re.Auth == nil {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			if !stampLimiter.Allow(re.Auth.Id) {
				return rateLimitedResponse(re)
			}
			var body struct {
				Record string `json:"record"`
				Text   string `json:"text"`
				Link   string `json:"link"`
			}
			if err := re.BindBody(&body); err != nil {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ValidationFieldRequired)
			}
			info, err := re.RequestInfo()
			if err != nil {
				return re.InternalServerError("Failed to read the request.", nil)
			}

			rec := viewableRecord(app, info, util.Coll.Records, body.Record)
			if rec == nil || rec.GetString(util.Fields.Record.Type) != util.TypeFile ||
				rec.GetString(util.Fields.Record.File) == "" {
				return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
			}

			var line string
			if body.Link != "" {
				link := viewableRecord(app, info, util.Coll.Links, body.Link)
				if link == nil {
					return appErrorResponse(re, http.StatusNotFound, &util.Errors.LinkNotFound)
				}
				if !services.LinkGrantsRecord(link, rec.Id) {
					return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
				}
				line = services.WatermarkLine(link, time.Now())
			} else {
				text, ok := services.ValidWatermarkText(body.Text)
				if !ok {
					return appErrorResponse(re, http.StatusBadRequest, &util.Errors.WatermarkTextInvalid)
				}
				line = services.PreviewWatermarkLine(text, time.Now())
			}

			fsys, err := app.NewFilesystem()
			if err != nil {
				return re.InternalServerError("Failed to open storage.", nil)
			}
			defer fsys.Close()
			name := services.FileDownloadName(rec)
			previewName := strings.TrimSuffix(name, filepath.Ext(name)) + "-preview" + filepath.Ext(name)
			return serveWatermarked(re, fsys, rec.BaseFilesPath()+"/"+rec.GetString(util.Fields.Record.File),
				services.SafeFileName(previewName), line)
		})

		// The owner's copy of what a share hands out. It claims no view: the
		// cap limits the people the share was sent to, not its owner.
		e.Router.GET("/api/links/{id}/archive", func(re *core.RequestEvent) error {
			if re.Auth == nil {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			if !stampLimiter.Allow(re.Auth.Id) {
				return rateLimitedResponse(re)
			}
			info, err := re.RequestInfo()
			if err != nil {
				return re.InternalServerError("Failed to read the request.", nil)
			}
			link := viewableRecord(app, info, util.Coll.Links, re.Request.PathValue("id"))
			if link == nil {
				return appErrorResponse(re, http.StatusNotFound, &util.Errors.LinkNotFound)
			}
			// A key allowed to read links is not thereby allowed to read the
			// records behind them.
			var files []*core.Record
			for _, rec := range services.LinkFileRecords(app, link) {
				if ok, err := app.CanAccessRecord(rec, info, rec.Collection().ViewRule); err == nil && ok {
					files = append(files, rec)
				}
			}
			return serveLinkArchive(re, app, link, files)
		})

		return e.Next()
	})
}

// viewableRecord loads a record only if the caller passes its collection's
// view rule. Missing and hidden are the same nil, so neither answer reveals
// whether the id exists.
func viewableRecord(app core.App, info *core.RequestInfo, collection, id string) *core.Record {
	if id == "" {
		return nil
	}
	rec, err := app.FindRecordById(collection, id)
	if err != nil || rec == nil {
		return nil
	}
	if ok, err := app.CanAccessRecord(rec, info, rec.Collection().ViewRule); err != nil || !ok {
		return nil
	}
	return rec
}
