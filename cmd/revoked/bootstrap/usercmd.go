package bootstrap

import (
	"fmt"
	"revoked/util"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/spf13/cobra"
)

// BindUserCommand adds `user upsert EMAIL PASSWORD`, the way to add an account
// to a server that does not accept registrations. It mirrors PocketBase's own
// `superuser upsert`, but for the regular users collection, and writes through
// app.Save so it is not subject to the request-time signup refusal.
func BindUserCommand(app *pocketbase.PocketBase) {
	cmd := &cobra.Command{
		Use:   "user",
		Short: "Manage regular user accounts",
	}

	cmd.AddCommand(&cobra.Command{
		Use:   "upsert EMAIL PASSWORD",
		Short: "Create a user, or reset the password of an existing one",
		Args:  cobra.ExactArgs(2),
		RunE: func(_ *cobra.Command, args []string) error {
			email, password := args[0], args[1]

			if err := app.Bootstrap(); err != nil {
				return err
			}

			users, err := app.FindCollectionByNameOrId(util.Coll.Users)
			if err != nil {
				return fmt.Errorf("users collection: %w", err)
			}

			record, err := app.FindAuthRecordByEmail(users, email)
			if err != nil || record == nil {
				record = core.NewRecord(users)
				record.Set(util.Fields.User.Email, email)
			}
			record.Set(util.Fields.User.Verified, true)
			record.SetPassword(password)

			if err := app.Save(record); err != nil {
				return err
			}

			fmt.Printf("Saved user %q.\n", email)
			return nil
		},
	})

	app.RootCmd.AddCommand(cmd)
}
