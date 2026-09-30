package bootstrap

import (
	"fmt"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase"
	"github.com/spf13/cobra"
)

// BindUserCommand adds `user upsert EMAIL`, the way to add an account to a
// server that does not accept registrations, and the way back in for someone
// who lost every device holding a passkey. It writes through app.Save, so it
// is not subject to the request-time signup refusal.
//
// An account has no password. The command prints a one-time link instead: the
// person opens it and saves a passkey on their device.
func BindUserCommand(app *pocketbase.PocketBase, domain string) {
	cmd := &cobra.Command{
		Use:   "user",
		Short: "Manage regular user accounts",
	}

	cmd.AddCommand(&cobra.Command{
		Use:   "upsert EMAIL",
		Short: "Create a user if needed, and print a one-time link to add a passkey",
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			email := args[0]

			if err := app.Bootstrap(); err != nil {
				return err
			}

			user, created, err := services.EnsurePasskeyAccount(app, email)
			if err != nil {
				return err
			}
			ticket, expires, err := services.IssuePasskeyTicket(app, user.Id, util.PasskeyOperatorTicketTTL)
			if err != nil {
				return err
			}

			if created {
				fmt.Printf("Created user %q.\n", email)
			}
			fmt.Printf("Link to add a passkey for %q (one use, until %s):\n  %s\n",
				email, expires.Local().Format("2006-01-02 15:04"), services.PasskeyTicketURL(domain, ticket))
			fmt.Println("On a development machine, open it at http://localhost:<port> instead of the domain.")
			return nil
		},
	})

	app.RootCmd.AddCommand(cmd)
}
