package migrations

import (
	"encoding/json"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Audit snapshots written before redaction existed still hold every secret
// verbatim — vault values, submitted gate passwords, collected request data.
// Scrub them in place with the same catalogue the hook now applies on write.
// Naturally idempotent: redacting a redacted snapshot changes nothing.
func init() {
	migrations.Register(func(app core.App) error {
		for collName := range util.AuditSecretFields {
			rows, err := app.FindAllRecords(util.Coll.AuditLogs,
				dbx.HashExp{util.Fields.AuditLog.Collection: collName})
			if err != nil {
				return err
			}
			for _, row := range rows {
				changed := false
				for _, field := range []string{util.Fields.AuditLog.OldData, util.Fields.AuditLog.NewData} {
					raw := row.GetString(field)
					if raw == "" {
						continue
					}
					var data map[string]any
					if json.Unmarshal([]byte(raw), &data) != nil {
						continue
					}
					redacted, err := json.Marshal(util.RedactAuditData(collName, data))
					if err != nil {
						continue
					}
					if string(redacted) != raw {
						row.Set(field, string(redacted))
						changed = true
					}
				}
				if changed {
					if err := app.Save(row); err != nil {
						return err
					}
				}
			}
		}
		return nil
	}, func(app core.App) error {
		// The scrubbed values are unrecoverable by design; nothing to restore.
		return nil
	})
}
