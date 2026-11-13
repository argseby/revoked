package routes

import (
	"errors"
	"net/http"
	"slices"
	"strings"
	"time"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/dbx"
	validation "github.com/pocketbase/ozzo-validation/v4"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/filesystem"
)

// vaultReadLimiter bounds what one key or tool reads per minute, so one gone
// wrong cannot drain the vault faster than its owner notices.
var vaultReadLimiter = util.NewRateLimiter(util.LimitFromEnv("RATELIMIT_CONNECTION_VAULT_READS", 120), time.Minute)

var vaultWriteLimiter = util.NewRateLimiter(util.LimitFromEnv("RATELIMIT_VAULT_WRITES", 60), time.Minute)

// VaultRoute is the one way a key or a connected tool reaches the vault:
//
//	GET    /api/vault             the records within reach: id, key, label, type
//	GET    /api/vault/{id}        one record with its current value
//	GET    /api/vault/{id}/file   a file record's bytes
//	POST   /api/vault             write a record into a section it may write to
//	PATCH  /api/vault/{id}        change a record it wrote
//	DELETE /api/vault/{id}        delete a record it wrote
//
// /api/connection/vault[/{id}] answer as the first two did before keys had a
// reach. Reach is checked here on every request and never in a collection
// rule: a rule cannot follow a record into the sections that hold it, and a
// key's record scopes would otherwise open the whole workspace (ACCESS.md).
// Never an encrypted record, whose value this server cannot read.
func VaultRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		list := func(re *core.RequestEvent) error { return listVault(app, re) }
		read := func(re *core.RequestEvent) error { return readVaultRecord(app, re) }
		e.Router.GET("/api/vault", list)
		e.Router.GET("/api/vault/{id}", read)
		e.Router.GET("/api/connection/vault", list)
		e.Router.GET("/api/connection/vault/{id}", read)
		e.Router.GET("/api/vault/{id}/file", func(re *core.RequestEvent) error {
			return serveVaultFile(app, re)
		})
		e.Router.POST("/api/vault", func(re *core.RequestEvent) error {
			return writeVaultRecord(app, re, nil)
		})
		e.Router.PATCH("/api/vault/{id}", func(re *core.RequestEvent) error {
			c, rec, ok := ownVaultRecord(app, re)
			if !ok {
				return nil
			}
			return writeVaultRecord(app, re, &vaultTarget{c: c, rec: rec})
		})
		e.Router.DELETE("/api/vault/{id}", func(re *core.RequestEvent) error {
			c, rec, ok := ownVaultRecord(app, re)
			if !ok {
				return nil
			}
			old := rec.PublicExport()
			if err := app.Delete(rec); err != nil {
				return re.InternalServerError("Failed to delete the record", err)
			}
			auditVaultWrite(app, re, c, util.AuditActionDelete, rec.Id, old, nil)
			return re.NoContent(http.StatusNoContent)
		})
		return e.Next()
	})
}

// vaultCredential resolves the key or tool asking, or writes the refusal.
func vaultCredential(app core.App, re *core.RequestEvent) (services.Credential, bool) {
	if strings.TrimSpace(re.Request.Header.Get(util.ConnectionHeader)) != "" {
		token, conn, _, ok := connectionTokenFromRequest(app, re)
		if !ok {
			return services.Credential{}, false
		}
		return services.ConnectionCredential(conn, token), true
	}
	if re.Auth != nil && re.Auth.Collection().Name == util.Coll.ApiKeys {
		return services.ApiKeyCredential(re.Auth), true
	}
	return services.Credential{}, denyGate(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
}

// vaultReader is vaultCredential for a read: it must reach some of the vault,
// and stays within the read limit.
func vaultReader(app core.App, re *core.RequestEvent) (services.Credential, bool) {
	c, ok := vaultCredential(app, re)
	if !ok {
		return c, false
	}
	if !c.ReadsVault() {
		switch {
		case c.Kind == services.CredentialApiKey:
			return c, denyGate(re, http.StatusForbidden, &util.Errors.VaultNotAllowed)
		case c.Record.GetBool(util.Fields.Connection.AllowVaultRead) && len(c.Sections) == 0:
			return c, denyGate(re, http.StatusForbidden, &util.Errors.ConnectionVaultPolled)
		default:
			return c, denyGate(re, http.StatusForbidden, &util.Errors.ConnectionVaultNotAllowed)
		}
	}
	if !allowRequest(re, vaultReadLimiter, c.Id) {
		_ = rateLimitedResponse(re)
		return c, false
	}
	return c, true
}

func listVault(app core.App, re *core.RequestEvent) error {
	c, ok := vaultReader(app, re)
	if !ok {
		return nil
	}
	rows, err := c.RecordsInReach(app)
	if err != nil {
		return re.InternalServerError("Failed to list the vault", err)
	}
	out := make([]map[string]any, 0, len(rows))
	for _, rec := range rows {
		out = append(out, vaultRecordView(app, c, rec))
	}
	auditCredential(app, re, c, auditToolListedVault, map[string]any{"count": len(out)})
	return re.JSON(http.StatusOK, map[string]any{"records": out})
}

// reachedRecord finds a record within reach, or answers 404: a record out of
// reach looks exactly like a missing one.
func reachedRecord(app core.App, re *core.RequestEvent, c services.Credential) (*core.Record, bool) {
	rec, err := app.FindRecordById(util.Coll.Records, re.Request.PathValue("id"))
	if err != nil || !c.RecordInReach(app, rec) {
		return nil, denyGate(re, http.StatusNotFound, &util.Errors.RecordNotFound)
	}
	return rec, true
}

// sourceRecord is where an alias reads its value from.
func sourceRecord(app core.App, rec *core.Record) (*core.Record, bool) {
	parentID := rec.GetString(util.Fields.Record.AliasOf)
	if parentID == "" {
		return rec, true
	}
	parent, err := app.FindRecordById(util.Coll.Records, parentID)
	return parent, err == nil && parent != nil
}

func readVaultRecord(app core.App, re *core.RequestEvent) error {
	c, ok := vaultReader(app, re)
	if !ok {
		return nil
	}
	rec, ok := reachedRecord(app, re, c)
	if !ok {
		return nil
	}
	source, ok := sourceRecord(app, rec)
	if !ok {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
	}
	view := vaultRecordView(app, c, rec)
	if source.GetString(util.Fields.Record.Type) == util.TypeFile {
		view["filename"] = source.GetString(util.Fields.Record.Filename)
		view["mime"] = source.GetString(util.Fields.Record.Mime)
		view["size"] = source.GetInt(util.Fields.Record.Size)
	} else {
		view["value"] = source.GetString(util.Fields.Record.Value)
	}
	auditCredential(app, re, c, auditToolReadRecord, map[string]any{
		"record": rec.Id,
		"key":    rec.GetString(util.Fields.Record.Key),
	})
	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(http.StatusOK, view)
}

func serveVaultFile(app core.App, re *core.RequestEvent) error {
	c, ok := vaultReader(app, re)
	if !ok {
		return nil
	}
	rec, ok := reachedRecord(app, re, c)
	if !ok {
		return nil
	}
	stored := rec.GetString(util.Fields.Record.File)
	if rec.GetString(util.Fields.Record.Type) != util.TypeFile || stored == "" {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
	}
	fsys, err := app.NewFilesystem()
	if err != nil {
		return re.InternalServerError("Failed to open storage.", err)
	}
	defer fsys.Close()
	name := rec.GetString(util.Fields.Record.Filename)
	if name == "" {
		name = stored
	}
	auditCredential(app, re, c, auditToolReadRecord, map[string]any{
		"record": rec.Id,
		"key":    rec.GetString(util.Fields.Record.Key),
	})
	// An attachment, never sniffed, as on the public file route.
	h := re.Response.Header()
	h.Set("Content-Disposition", attachmentDisposition(name))
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Cache-Control", "no-store")
	if mime := rec.GetString(util.Fields.Record.Mime); mime != "" {
		h.Set("Content-Type", mime)
	}
	return fsys.Serve(re.Response, re.Request, rec.BaseFilesPath()+"/"+stored, stored)
}

// ownVaultRecord finds a record this credential wrote and may still change.
// One it can read but did not write is the owner's, and stays read-only to it.
func ownVaultRecord(app core.App, re *core.RequestEvent) (services.Credential, *core.Record, bool) {
	c, ok := vaultCredential(app, re)
	if !ok {
		return c, nil, false
	}
	if c.VaultAccess != util.VaultAccessWrite {
		return c, nil, denyGate(re, http.StatusForbidden, &util.Errors.VaultSectionNotWritable)
	}
	rec, ok := reachedRecord(app, re, c)
	if !ok {
		return c, nil, false
	}
	if !c.Wrote(rec) {
		return c, nil, denyGate(re, http.StatusForbidden, &util.Errors.VaultReadOnly)
	}
	if !allowRequest(re, vaultWriteLimiter, c.Id) {
		_ = rateLimitedResponse(re)
		return c, nil, false
	}
	return c, rec, true
}

// vaultTarget is the record a PATCH changes, with who is changing it.
type vaultTarget struct {
	c   services.Credential
	rec *core.Record
}

// vaultWrite is what a key or tool may set on a record. Everything else —
// owner, workspace, who wrote it, sealing — is the server's.
type vaultWrite struct {
	Key      string `json:"key"`
	Label    string `json:"label"`
	Type     string `json:"type"`
	Format   string `json:"format"`
	Value    string `json:"value"`
	Filename string `json:"filename"`
	Section  string `json:"section"`
	set      map[string]bool
	file     *filesystem.File
}

func bindVaultWrite(re *core.RequestEvent) (vaultWrite, error) {
	var in vaultWrite
	in.set = map[string]bool{}
	if strings.HasPrefix(re.Request.Header.Get("Content-Type"), "multipart/form-data") {
		if err := re.Request.ParseMultipartForm(32 << 20); err != nil {
			return in, err
		}
		for name, dst := range map[string]*string{
			"key": &in.Key, "label": &in.Label, "type": &in.Type, "format": &in.Format,
			"value": &in.Value, "filename": &in.Filename, "section": &in.Section,
		} {
			if vals, ok := re.Request.MultipartForm.Value[name]; ok && len(vals) > 0 {
				*dst = vals[0]
				in.set[name] = true
			}
		}
		if files, err := re.FindUploadedFiles(util.Fields.Record.File); err == nil && len(files) > 0 {
			in.file = files[0]
		}
		return in, nil
	}
	raw := map[string]any{}
	if err := re.BindBody(&raw); err != nil {
		return in, err
	}
	for name := range raw {
		in.set[name] = true
	}
	str := func(name string) string { s, _ := raw[name].(string); return s }
	in.Key, in.Label, in.Type, in.Format = str("key"), str("label"), str("type"), str("format")
	in.Value, in.Filename, in.Section = str("value"), str("filename"), str("section")
	return in, nil
}

// writeVaultRecord creates a record in a section the credential may write to,
// or changes one it wrote (target set).
func writeVaultRecord(app core.App, re *core.RequestEvent, target *vaultTarget) error {
	var c services.Credential
	if target != nil {
		c = target.c
	} else {
		var ok bool
		if c, ok = vaultCredential(app, re); !ok {
			return nil
		}
		if !c.WritesVault() {
			return appErrorResponse(re, http.StatusForbidden, &util.Errors.VaultSectionNotWritable)
		}
		if !allowRequest(re, vaultWriteLimiter, c.Id) {
			return rateLimitedResponse(re)
		}
	}
	in, err := bindVaultWrite(re)
	if err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.InvalidRequestBody)
	}

	var section *core.Record
	if target == nil {
		id := in.Section
		if id == "" {
			id = c.Writable[0]
		}
		if !slices.Contains(c.Writable, id) {
			return appErrorResponse(re, http.StatusForbidden, &util.Errors.VaultSectionNotWritable)
		}
		for _, s := range c.ReachedSections(app) {
			if s.Id == id {
				section = s
			}
		}
		if section == nil {
			return appErrorResponse(re, http.StatusForbidden, &util.Errors.VaultSectionNotWritable)
		}
	}

	added := int64(len(in.Value))
	if in.file != nil {
		added += in.file.Size
	}
	except := ""
	if target != nil {
		except = target.rec.Id
	}
	if limit := util.ConnectionStorageLimit(); limit >= 0 {
		used, err := c.StoredBytes(app, except)
		if err != nil {
			return re.InternalServerError("Failed to check storage", err)
		}
		if used+added > limit {
			return appErrorResponse(re, http.StatusRequestEntityTooLarge, &util.Errors.VaultStorageExceeded)
		}
	}

	f := util.Fields.Record
	var rec *core.Record
	var old map[string]any
	if target != nil {
		rec = target.rec
		old = rec.PublicExport()
		if in.set["label"] {
			rec.Set(f.Label, in.Label)
		}
		if in.set["format"] {
			rec.Set(f.Format, in.Format)
		}
		if in.set["value"] && rec.GetString(f.Type) != util.TypeFile {
			rec.Set(f.Value, in.Value)
		}
		if in.set["filename"] {
			rec.Set(f.Filename, in.Filename)
		}
	} else {
		coll, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return re.InternalServerError("Records collection missing", err)
		}
		typ := in.Type
		if typ == "" {
			typ = util.TypeText
			if in.file != nil {
				typ = util.TypeFile
			}
		}
		format := in.Format
		if format == "" {
			format = util.FormatDefault
		}
		label := in.Label
		if label == "" {
			label = strings.TrimSpace(in.Key)
		}
		rec = core.NewRecord(coll)
		rec.Set(f.Key, strings.TrimSpace(in.Key))
		rec.Set(f.Label, label)
		rec.Set(f.Type, typ)
		rec.Set(f.Format, format)
		rec.Set(f.Value, in.Value)
		rec.Set(f.Filename, in.Filename)
		rec.Set(f.User, c.User)
		rec.Set(f.Workspace, c.Workspace)
		rec.Set(f.WrittenBy, c.Id)
		name := []rune(c.Name)
		if len(name) > 80 {
			name = name[:80]
		}
		rec.Set(f.WrittenByName, string(name))
		taken, _ := app.FindFirstRecordByFilter(util.Coll.Records,
			"workspace = {:ws} && user = {:user} && key = {:key}",
			dbx.Params{"ws": c.Workspace, "user": c.User, "key": rec.GetString(f.Key)})
		if taken != nil {
			return appErrorResponse(re, http.StatusConflict, &util.Errors.VaultKeyTaken)
		}
	}
	if in.file != nil {
		rec.Set(f.File, in.file)
	}

	err = app.RunInTransaction(func(tx core.App) error {
		if err := tx.Save(rec); err != nil {
			return err
		}
		if section == nil {
			return nil
		}
		fresh, err := tx.FindRecordById(util.Coll.Sections, section.Id)
		if err != nil {
			return err
		}
		fresh.Set(util.Fields.Section.Records, append(fresh.GetStringSlice(util.Fields.Section.Records), rec.Id))
		return tx.Save(fresh)
	})
	if err != nil {
		var verr validation.Errors
		if errors.As(err, &verr) {
			return re.BadRequestError("The record could not be saved.", verr)
		}
		return re.InternalServerError("Failed to save the record", err)
	}

	action := util.AuditActionCreate
	status := http.StatusCreated
	if target != nil {
		action = util.AuditActionUpdate
		status = http.StatusOK
	}
	auditVaultWrite(app, re, c, action, rec.Id, old, rec.PublicExport())
	return re.JSON(status, vaultRecordView(app, c, rec))
}

func vaultRecordView(app core.App, c services.Credential, rec *core.Record) map[string]any {
	f := util.Fields.Record
	view := map[string]any{
		"id":            rec.Id,
		"key":           rec.GetString(f.Key),
		"label":         rec.GetString(f.Label),
		"type":          rec.GetString(f.Type),
		"format":        rec.GetString(f.Format),
		"updated":       rec.GetString(f.Updated),
		"writtenByName": rec.GetString(f.WrittenByName),
		"writable":      c.VaultAccess == util.VaultAccessWrite && c.Wrote(rec),
	}
	if !c.WholeVault {
		view["sections"] = c.SectionsHolding(app, rec)
	}
	return view
}

// auditCredential records something a key or tool did, as auditConnection
// does for a tool.
func auditCredential(app core.App, re *core.RequestEvent, c services.Credential, action string, extra map[string]any) {
	if c.Kind == services.CredentialConnection {
		auditConnection(app, re, c.Record, action, extra)
		return
	}
	fields := map[string]any{util.Fields.ApiKey.Label: c.Name}
	for k, v := range extra {
		fields[k] = v
	}
	saveAuditRow(app, re, auditRow{
		user:       c.User,
		workspace:  c.Workspace,
		action:     action,
		collection: util.Coll.ApiKeys,
		recordID:   c.Id,
		fields:     fields,
	})
}

// auditVaultWrite logs a record a key or tool wrote. A direct save skips the
// audit hook, so this is its row; the snapshots pass through the redaction
// catalogue like every other.
func auditVaultWrite(app core.App, re *core.RequestEvent, c services.Credential, action, id string, old, new map[string]any) {
	entry := services.AuditEntry{
		Action:     action,
		Collection: util.Coll.Records,
		RecordId:   id,
		Workspace:  c.Workspace,
		User:       c.User,
		Ip:         re.Request.RemoteAddr,
		UserAgent:  re.Request.UserAgent(),
		OldData:    old,
		NewData:    new,
	}
	if c.Kind == services.CredentialApiKey {
		entry.ApiKey = c.Id
	}
	services.RecordAudit(app, entry)
}
