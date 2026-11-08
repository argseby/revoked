package bootstrap

import (
	"errors"
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
//
// `user reset-2fa EMAIL` removes an authenticator app someone lost.
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

	cmd.AddCommand(&cobra.Command{
		Use:   "reset-2fa EMAIL",
		Short: "Remove a user's authenticator app and end all of their sessions",
		Long: "Removes the authenticator app from an account, for someone who lost it. " +
			"Every session the account has ends, and an audit entry is written. " +
			"The passkey stays the way in; where REQUIRE_2FA is on, the app asks for a new authenticator after the next sign-in.",
		Args: cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			email := args[0]

			if err := app.Bootstrap(); err != nil {
				return err
			}

			reset, err := services.ResetTwoFactor(app, email, "revoked user reset-2fa")
			if errors.Is(err, services.ErrTwoFactorAccountMissing) {
				return fmt.Errorf("no user with the address %q", email)
			}
			if err != nil {
				return err
			}

			switch {
			case reset.Enabled:
				fmt.Printf("Removed the authenticator app from %q.\n", email)
			case reset.Pending:
				fmt.Printf("%q had no authenticator app turned on; discarded one that was being set up.\n", email)
			default:
				fmt.Printf("%q had no authenticator app turned on.\n", email)
			}
			fmt.Println("Ended every session of this account and wrote an audit entry.")
			return nil
		},
	})

	app.RootCmd.AddCommand(cmd)
}
