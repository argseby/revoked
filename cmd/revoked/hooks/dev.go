package hooks

import (
	"log"

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

// BindCreateUserAccount ensures a test user exists with the provided credentials.
func BindCreateUserAccount(app core.App, email string, password string) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		users, err := e.App.FindCollectionByNameOrId("users")
		if err != nil {
			return e.Next()
		}

		user, err := e.App.FindAuthRecordByEmail(users, email)
		if err != nil || user == nil {
			log.Printf("Creating default user: %s\n", email)
			newUser := core.NewRecord(users)
			newUser.Set("email", email)
			newUser.SetPassword(password)
			newUser.Set("verified", true)
			if err := e.App.Save(newUser); err != nil {
				log.Printf("Failed to create default user: %v\n", err)
			}
		}
		return e.Next()
	})
}
