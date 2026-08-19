package util

import (
	"os"
	"strings"
)

// AllowSignupsEnv opts a deployment into public self-service registration.
const AllowSignupsEnv = "ALLOW_SIGNUPS"

// SignupsAllowed reports whether anyone may create their own account.
//
// Off unless explicitly enabled: an operator who has not thought about it runs
// a server only they can add people to, rather than one the internet can. With
// it off, accounts are made by a superuser — through the dashboard, the
// `user upsert` command, or the USER_EMAIL/USER_PASSWORD seed.
func SignupsAllowed() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(AllowSignupsEnv))) {
	case "1", "true", "yes":
		return true
	default:
		return false
	}
}
