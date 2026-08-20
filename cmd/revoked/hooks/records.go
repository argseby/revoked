package hooks

import (
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"revoked/util"

	"github.com/go-ozzo/ozzo-validation/v4"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// BindRecordHooks enforces the alias and file invariants on record create and
// update.
func BindRecordHooks(app core.App) {
	app.OnRecordCreate(util.Coll.Records).BindFunc(func(e *core.RecordEvent) error {
		if err := validateAliasRecord(app, e.Record); err != nil {
			return err
		}
		if err := validateFileRecord(app, e.Record); err != nil {
			return err
		}
		return e.Next()
	})

	app.OnRecordUpdate(util.Coll.Records).BindFunc(func(e *core.RecordEvent) error {
		if err := validateAliasRecord(app, e.Record); err != nil {
			return err
		}
		if err := validateFileRecord(app, e.Record); err != nil {
			return err
		}
		return e.Next()
	})
}

// validateFileRecord keeps files and the file type coupled: a file record must
// hold exactly one uploaded file and no text value, and no other type may
// smuggle one in. New uploads are checked against the operator's size policy
// and stamped with a salted content hash — the salt keeps the publicly served
// hash from acting as a guessing oracle for recognizable documents.
func validateFileRecord(app core.App, rec *core.Record) error {
	uploads := rec.GetUnsavedFiles(util.Fields.Record.File)

	if rec.GetString(util.Fields.Record.Type) != util.TypeFile {
		if len(uploads) > 0 || rec.GetString(util.Fields.Record.File) != "" {
			return util.AsFieldValidationError(util.Fields.Record.File, util.Errors.FileNotAllowed)
		}
		// The schema left value optional for the file type's sake; text records
		// still require one. Aliases are exempt — their value is cleared by
		// design and reads resolve through the parent.
		if rec.GetString(util.Fields.Record.Value) == "" && rec.GetString(util.Fields.Record.AliasOf) == "" {
			return validation.Errors{util.Fields.Record.Value: validation.NewError("validation_required", "Cannot be blank.")}
		}
		return nil
	}

	if rec.GetString(util.Fields.Record.AliasOf) != "" {
		return util.AsFieldValidationError(util.Fields.Record.AliasOf, util.Errors.FileAliasUnsupported)
	}
	rec.Set(util.Fields.Record.Value, "")

	if len(uploads) == 0 {
		// A metadata-only update keeps the stored file and its hash; a file
		// record without any file has nothing to grant.
		if rec.GetString(util.Fields.Record.File) == "" {
			return util.AsFieldValidationError(util.Fields.Record.File, util.Errors.FileRequired)
		}
		return nil
	}

	f := uploads[len(uploads)-1]
	if max := util.FileLimitBytes(util.FileMaxSizeEnv); max >= 0 && f.Size > max {
		return util.AsFieldValidationError(util.Fields.Record.File, util.Errors.FileTooLarge)
	}
	if max := util.FileLimitBytes(util.FileMaxStorageEnv); max >= 0 {
		used, err := workspaceFileBytes(app, rec)
		if err != nil {
			return err
		}
		if used+f.Size > max {
			return util.AsFieldValidationError(util.Fields.Record.File, util.Errors.FileStorageExceeded)
		}
	}

	saltHex, err := util.GenerateToken(16)
	if err != nil {
		return err
	}
	salt, err := hex.DecodeString(saltHex)
	if err != nil {
		return err
	}
	r, err := f.Reader.Open()
	if err != nil {
		return err
	}
	defer r.Close()

	head := make([]byte, 512)
	n, readErr := io.ReadFull(r, head)
	if readErr != nil && readErr != io.EOF && readErr != io.ErrUnexpectedEOF {
		return readErr
	}
	h := sha256.New()
	h.Write(salt)
	h.Write(head[:n])
	if _, err := io.Copy(h, r); err != nil {
		return err
	}

	rec.Set(util.Fields.Record.HashSalt, saltHex)
	rec.Set(util.Fields.Record.ContentHash, hex.EncodeToString(h.Sum(nil)))
	rec.Set(util.Fields.Record.Mime, http.DetectContentType(head[:n]))
	rec.Set(util.Fields.Record.Size, f.Size)
	return nil
}

// workspaceFileBytes sums the stored file sizes of the record's workspace,
// excluding the record itself so a replacement is charged only once.
func workspaceFileBytes(app core.App, rec *core.Record) (int64, error) {
	var total float64
	err := app.DB().
		NewQuery("SELECT COALESCE(SUM(size), 0) FROM " + util.Coll.Records +
			" WHERE workspace = {:ws} AND type = {:t} AND id != {:id}").
		Bind(dbx.Params{
			"ws": rec.GetString(util.Fields.Record.Workspace),
			"t":  util.TypeFile,
			"id": rec.Id,
		}).Row(&total)
	return int64(total), err
}

// validateAliasRecord rejects self, missing, cross-workspace and chained alias
// targets, and clears an alias's own value.
func validateAliasRecord(app core.App, rec *core.Record) error {
	parentId := rec.GetString(util.Fields.Record.AliasOf)
	if parentId == "" {
		return nil
	}
	if parentId == rec.Id {
		return util.AsValidationError(util.Errors.AliasCycle)
	}
	parent, err := app.FindRecordById(util.Coll.Records, parentId)
	if err != nil || parent == nil {
		return util.AsValidationError(util.Errors.AliasParentMissing)
	}
	if parent.GetString(util.Fields.Record.Workspace) != rec.GetString(util.Fields.Record.Workspace) {
		return util.AsValidationError(util.Errors.AliasParentMissing)
	}
	if parent.GetString(util.Fields.Record.AliasOf) != "" {
		return util.AsValidationError(util.Errors.AliasCycle)
	}
	// An alias never stores its own value; reads resolve through the parent.
	rec.Set(util.Fields.Record.Value, "")
	return nil
}
