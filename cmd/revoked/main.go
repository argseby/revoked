// Command revoked runs the revoked API server.
package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"revoked/cmd/revoked/bootstrap"
	"revoked/cmd/revoked/hooks"
	"revoked/cmd/revoked/server"
	_ "revoked/migrations"
	"revoked/util"

	"github.com/joho/godotenv"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"
)

func main() {
	err := godotenv.Load()
	if err != nil {
		log.Println("No .env file found, falling back to system environment variables")
	}

	app := pocketbase.New()

	// DOMAIN anchors the whole DNS trust chain: booting without it would issue
	// identities every remote verifier rejects, so fail fast instead.
	domain := os.Getenv("DOMAIN")
	if domain == "" {
		log.Fatal("DOMAIN environment variable is required. Set it to the externally-facing hostname this server is reachable at (e.g. DOMAIN=bmw.com). Without it identities cannot be DNS-verified by peers.")
	}

	keyPath := os.Getenv("SERVER_KEY_PATH")
	if keyPath == "" {
		keyPath = filepath.Join("pb_data", "server_root.pem")
	}

	root, err := server.Load(domain, keyPath)
	if err != nil {
		log.Fatalf("failed to initialize server root key: %v", err)
	}
	fmt.Print(root.SetupInstructions())

	if _, err := util.LoadOrGenerateCertificate(filepath.Dir(keyPath)); err != nil {
		log.Fatalf("failed to load or generate server certificate: %v", err)
	}

	adminEmail := os.Getenv("ADMIN_EMAIL")
	adminPass := os.Getenv("ADMIN_PASSWORD")

	if adminEmail != "" && adminPass != "" {
		hooks.BindCreateSuperuserAccount(app, adminEmail, adminPass)
	}

	userEmail := os.Getenv("USER_EMAIL")
	userPass := os.Getenv("USER_PASSWORD")

	if userEmail != "" && userPass != "" {
		hooks.BindCreateUserAccount(app, userEmail, userPass)
	}

	migratecmd.MustRegister(app, app.RootCmd, migratecmd.Config{
		Automigrate: true,
	})

	bootstrap.Bind(app, root)
	bootstrap.BindUserCommand(app)

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
