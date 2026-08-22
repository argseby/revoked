// Package bootstrap is the composition root: the only package that knows about
// both the event hooks and the HTTP routes, so neither has to import the other.
package bootstrap

import (
	"revoked/cmd/revoked/hooks"
	"revoked/cmd/revoked/routes"
	"revoked/cmd/revoked/server"

	"github.com/pocketbase/pocketbase/core"
)

// Bind registers every event hook, the API-key auth middleware and the custom
// HTTP routes on app.
//
// Registration order is significant — PocketBase runs handlers in bind order,
// outermost first: identities must bind before tenancy so it still sees the
// client-supplied fields, and audit logging binds last so it runs innermost and
// records only what committed.
func Bind(app core.App, root *server.RootKey) {
	hooks.BindUsersHooks(app)
	hooks.BindWorkspacesHooks(app)
	hooks.BindWorkspaceMembersHooks(app)
	hooks.BindApiKeyHooks(app)
	hooks.BindApiKeyAuthMiddleware(app)
	hooks.BindAccessPreflight(app)
	hooks.BindRequestHooks(app)
	hooks.BindLinkHooks(app)
	hooks.BindIdentitiesHooks(app, root)
	hooks.BindRecordHooks(app)
	hooks.BindInviteHooks(app)
	hooks.RegisterTenancyHooks(app)
	hooks.BindAuditLogHooks(app)

	routes.HealthzRoute(app)
	routes.PublicLinksRoute(app, root)
	routes.PublicRequestsRoute(app, root)
	routes.PublicInvitesRoute(app, root)
	routes.PermissionsRoute(app)
	routes.WorkspaceMembersRoute(app)
	routes.RequestGrantsRoute(app)
	routes.PublicShortRoute(app, root)
	routes.PublicDavRoute(app)
	routes.PublicFilesRoute(app)
	routes.CertificateRoute(app)
	routes.IdentityStatusRoute(app, root)
	routes.ChallengeRoute(app)
	routes.ServerInfoRoute(app, root)
	routes.VerifyPeerRoute(app)
	routes.DeleteAccountRoute(app)
}
