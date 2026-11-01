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

	// Confirming addresses without a way to send mail would refuse every
	// signup with an error the person cannot do anything about.
	if util.SignupEmailVerification() {
		if smtp, ok := util.SMTPFromEnv(); !ok || smtp.SenderAddress == "" {
			log.Fatalf("%s is on, but no mail server is configured. Set %s and %s (and usually %s/%s), or turn %s off.",
				util.SignupVerifyEmailEnv, util.SMTPHostEnv, util.SMTPSenderAddressEnv,
				util.SMTPUsernameEnv, util.SMTPPasswordEnv, util.SignupVerifyEmailEnv)
		}
	}

	// Same reasoning for grant email: every send would fail with something
	// the sender cannot act on.
	if policy := util.GrantEmailRecipients(); policy != util.MailRecipientsOff {
		if smtp, ok := util.SMTPFromEnv(); !ok || smtp.SenderAddress == "" {
			log.Fatalf("%s is %s, but no mail server is configured. Set %s and %s (and usually %s/%s), or set %s=off.",
				util.GrantEmailRecipientsEnv, policy, util.SMTPHostEnv, util.SMTPSenderAddressEnv,
				util.SMTPUsernameEnv, util.SMTPPasswordEnv, util.GrantEmailRecipientsEnv)
		}
		// The per-workspace and global caps live in this process's memory, so
		// a second instance doubles both. The per-address cap counts rows and
		// is exact either way.
		log.Printf("%s is %s. The hourly send caps are per instance, so running more than one multiplies them.",
			util.GrantEmailRecipientsEnv, policy)
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

	if userEmail := os.Getenv("USER_EMAIL"); userEmail != "" {
		hooks.BindCreateUserAccount(app, userEmail, domain)
	}

	migratecmd.MustRegister(app, app.RootCmd, migratecmd.Config{
		Automigrate: true,
	})

	bootstrap.Bind(app, root)
	bootstrap.BindUserCommand(app, domain)

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
