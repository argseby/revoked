package hooks

import (
	"net/http"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// BindSharedSectionHooks keeps sharing a section with members a person's own
// act: an API key or a connected tool may hold the section-update scope, and
// must not use it to widen who reads the vault. Each change is audited.
func BindSharedSectionHooks(app core.App) {
	// On create the owner is bound to the caller by the tenancy hook, which may
	// run after this one, so only who is asking is checked there.
	guard := func(e *core.RecordRequestEvent, before, isCreate bool) error {
		after := e.Record.GetBool(util.Fields.Section.Shared)
		if after == before {
			return e.Next()
		}
		if e.Auth == nil || e.Auth.Collection().Name != util.Coll.Users ||
			(!isCreate && e.Auth.Id != e.Record.GetString(util.Fields.Section.User)) {
			appErr := util.Errors.SectionShareByPersonOnly
			return e.RequestEvent.JSON(http.StatusForbidden, map[string]any{
				"code": appErr.ErrorCode, "message": appErr.ErrorText, "status": http.StatusForbidden,
			})
		}
		if err := e.Next(); err != nil {
			return err
		}
		services.RecordAudit(app, services.AuditEntry{
			Action:     util.AuditActionUpdate,
			Collection: util.Coll.Sections,
			RecordId:   e.Record.Id,
			Workspace:  e.Record.GetString(util.Fields.Section.Workspace),
			User:       e.Auth.Id,
			Ip:         e.RequestEvent.Request.RemoteAddr,
			UserAgent:  e.RequestEvent.Request.UserAgent(),
		})
		return nil
	}
	app.OnRecordCreateRequest(util.Coll.Sections).BindFunc(func(e *core.RecordRequestEvent) error {
		if e.RequestEvent.HasSuperuserAuth() {
			return e.Next()
		}
		return guard(e, false, true)
	})
	app.OnRecordUpdateRequest(util.Coll.Sections).BindFunc(func(e *core.RecordRequestEvent) error {
		if e.RequestEvent.HasSuperuserAuth() {
			return e.Next()
		}
		return guard(e, e.Record.Original().GetBool(util.Fields.Section.Shared), false)
	})
}
