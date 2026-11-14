package routes

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/security"
	"net/http"
	"regexp"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"slices"
	"strings"
)

var toolSectionKey = regexp.MustCompile(`^[a-z0-9_]{1,55}$`)

// Groups stay within a connection's own-section grant. They never grant an
// owner session or reach another connection's sections.
func bindConnectionSections(e *core.ServeEvent, app core.App) {
	credential := func(re *core.RequestEvent) (services.Credential, bool) {
		c, ok := vaultReader(app, re)
		if !ok {
			return c, false
		}
		if c.Kind != services.CredentialConnection || c.ToolSectionPrefix() == "" || !c.SectionInReach(app, c.Record.GetString(util.Fields.Connection.Section)) {
			return c, denyGate(re, http.StatusForbidden, &util.Errors.ConnectionNotPermitted)
		}
		return c, true
	}
	e.Router.GET("/api/connection/sections", func(re *core.RequestEvent) error {
		c, ok := credential(re)
		if !ok {
			return nil
		}
		sections := []map[string]any{}
		records := []map[string]any{}
		seen := map[string]bool{}
		for _, section := range c.ReachedSections(app) {
			if !strings.HasPrefix(section.GetString(util.Fields.Section.Key), c.ToolSectionPrefix()) || section.GetString(util.Fields.Section.User) != c.User {
				continue
			}
			sections = append(sections, map[string]any{"id": section.Id, "key": strings.TrimPrefix(section.GetString(util.Fields.Section.Key), c.ToolSectionPrefix()), "name": section.GetString(util.Fields.Section.Name), "records": section.GetStringSlice(util.Fields.Section.Records)})
			for _, id := range section.GetStringSlice(util.Fields.Section.Records) {
				if seen[id] {
					continue
				}
				seen[id] = true
				rec, err := app.FindRecordById(util.Coll.Records, id)
				if err != nil || !c.RecordInReach(app, rec) {
					continue
				}
				view := vaultRecordView(app, c, rec)
				valueRecord, ok := sourceRecord(app, rec)
				if !ok {
					continue
				}
				view["value"] = valueRecord.GetString(util.Fields.Record.Value)
				records = append(records, view)
			}
		}
		auditCredential(app, re, c, auditToolListedVault, map[string]any{"count": len(records)})
		return re.JSON(http.StatusOK, map[string]any{"sections": sections, "records": records})
	})
	e.Router.POST("/api/connection/sections", func(re *core.RequestEvent) error {
		c, ok := credential(re)
		if !ok {
			return nil
		}
		if !c.WritesVault() {
			return appErrorResponse(re, http.StatusForbidden, &util.Errors.VaultSectionNotWritable)
		}
		if !allowRequest(re, vaultWriteLimiter, c.Id) {
			return rateLimitedResponse(re)
		}
		var body struct {
			Name string `json:"name"`
			Key  string `json:"key"`
		}
		if err := re.BindBody(&body); err != nil {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.InvalidRequestBody)
		}
		body.Name = strings.TrimSpace(body.Name)
		if body.Name == "" || len([]rune(body.Name)) > 100 || !toolSectionKey.MatchString(body.Key) {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.InvalidRequestBody)
		}
		key := strings.ToLower(c.ToolSectionPrefix() + body.Key + "_" + security.RandomString(8))
		if len(key) > 100 {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.InvalidRequestBody)
		}
		coll, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}
		section := core.NewRecord(coll)
		f := util.Fields.Section
		section.Set(f.Key, key)
		section.Set(f.Name, body.Name)
		section.Set(f.User, c.User)
		section.Set(f.Workspace, c.Workspace)
		section.Set(f.AudienceKind, util.AudiencePrivate)
		section.Set(f.Editing, util.EditingOwner)
		if err := app.Save(section); err != nil {
			return re.BadRequestError("Could not create the section.", err)
		}
		auditConnection(app, re, c.Record, util.AuditActionCreate, map[string]any{"section": section.Id})
		return re.JSON(http.StatusCreated, map[string]any{"id": section.Id, "key": strings.TrimPrefix(key, c.ToolSectionPrefix()), "name": body.Name, "records": []string{}})
	})
	e.Router.PATCH("/api/connection/sections/{id}", func(re *core.RequestEvent) error {
		c, ok := credential(re)
		if !ok {
			return nil
		}
		if !c.WritesVault() {
			return appErrorResponse(re, http.StatusForbidden, &util.Errors.VaultSectionNotWritable)
		}
		if !allowRequest(re, vaultWriteLimiter, c.Id) {
			return rateLimitedResponse(re)
		}
		id := re.Request.PathValue("id")
		prefix := c.ToolSectionPrefix()
		section, err := app.FindRecordById(util.Coll.Sections, id)
		if err != nil || !c.CanWriteSection(app, id) || !strings.HasPrefix(section.GetString(util.Fields.Section.Key), prefix) || section.GetString(util.Fields.Section.User) != c.User {
			return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
		}
		var body struct {
			Name   *string  `json:"name"`
			Add    []string `json:"records+"`
			Remove []string `json:"records-"`
		}
		if err := re.BindBody(&body); err != nil {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.InvalidRequestBody)
		}
		if body.Name != nil && (strings.TrimSpace(*body.Name) == "" || len([]rune(*body.Name)) > 100) {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.InvalidRequestBody)
		}
		for _, recordID := range body.Add {
			rec, err := app.FindRecordById(util.Coll.Records, recordID)
			if err != nil || !c.RecordInReach(app, rec) || !c.Wrote(rec) {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.VaultReadOnly)
			}
		}
		err = app.RunInTransaction(func(tx core.App) error {
			fresh, err := tx.FindRecordById(util.Coll.Sections, id)
			if err != nil {
				return err
			}
			ids := fresh.GetStringSlice(util.Fields.Section.Records)
			ids = slices.DeleteFunc(ids, func(id string) bool { return slices.Contains(body.Remove, id) })
			for _, add := range body.Add {
				if !slices.Contains(ids, add) {
					ids = append(ids, add)
				}
			}
			fresh.Set(util.Fields.Section.Records, ids)
			if body.Name != nil {
				fresh.Set(util.Fields.Section.Name, strings.TrimSpace(*body.Name))
			}
			return tx.Save(fresh)
		})
		if err != nil {
			return re.BadRequestError("Could not update the section.", err)
		}
		auditConnection(app, re, c.Record, util.AuditActionUpdate, map[string]any{"section": id})
		return re.NoContent(http.StatusNoContent)
	})
}
