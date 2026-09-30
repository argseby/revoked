package hooks

import (
	"log"
	"net"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// These helpers seed default accounts from environment credentials and must
// only ever be wired up outside production.

// BindCreateSuperuserAccount ensures a superuser exists with the provided credentials.
func BindCreateSuperuserAccount(app core.App, email string, password string) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		admins, err := e.App.FindCollectionByNameOrId("_superusers")
		if err != nil {
			return e.Next()
		}

		admin, _ := e.App.FindAuthRecordByEmail(admins, email)
		if admin == nil {
			log.Printf("Creating default superuser: %s\n", email)
			newAdmin := core.NewRecord(admins)
			newAdmin.Set("email", email)
			newAdmin.SetPassword(password)
			if err := e.App.Save(newAdmin); err != nil {
				log.Printf("Failed to create default superuser: %v\n", err)
			}
		}
		return e.Next()
	})
}

// BindCreateUserAccount ensures an account exists for email. An account has
// no password, so as long as it has no passkey either, every start logs a
// fresh link to add one — the only way into it.
func BindCreateUserAccount(app core.App, email string, domain string) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		user, created, err := services.EnsurePasskeyAccount(e.App, email)
		if err != nil {
			log.Printf("Failed to create default user: %v\n", err)
			return e.Next()
		}
		if created {
			log.Printf("Created default user: %s\n", email)
		}
		if n, err := e.App.CountRecords(util.Coll.Passkeys,
			dbx.HashExp{util.Fields.Passkey.User: user.Id}); err == nil && n == 0 {
			ticket, _, err := services.IssuePasskeyTicket(e.App, user.Id, util.PasskeyOperatorTicketTTL)
			if err != nil {
				log.Printf("Failed to issue a passkey link for %s: %v\n", email, err)
			} else {
				log.Printf("%s has no passkey yet. Add one within 24 hours at:\n  %s\n",
					email, services.PasskeyTicketURL(domain, ticket))
				// The configured domain is not where a development machine
				// reaches this server; a passkey made there binds to localhost.
				if _, port, err := net.SplitHostPort(e.Server.Addr); err == nil {
					log.Printf("On this machine:\n  %s\n",
						services.PasskeyTicketURL("localhost:"+port, ticket))
				}
			}
		}
		return e.Next()
	})
}
