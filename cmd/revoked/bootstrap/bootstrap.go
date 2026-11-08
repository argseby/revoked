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
	hooks.BindConnectionLimit(app)
	hooks.BindMailSettings(app)
	hooks.BindOutboundMailLimit(app)
	hooks.BindUsersHooks(app)
	hooks.BindWorkspacesHooks(app)
	hooks.BindWorkspaceMembersHooks(app)
	hooks.BindSharedSectionHooks(app)
	hooks.BindApiKeyHooks(app)
	hooks.BindApiKeyAuthMiddleware(app)
	hooks.BindAccessPreflight(app)
	routes.BindTwoFactorGate(app)
	hooks.BindRequestHooks(app)
	hooks.BindLinkHooks(app)
	hooks.BindIdentitiesHooks(app, root)
	hooks.BindRecordHooks(app)
	hooks.BindSealedHooks(app)
	hooks.BindReminderHooks(app)
	hooks.BindGrantHooks(app, root)
	hooks.BindAttestationHooks(app)
	hooks.BindConnectedHooks(app)
	hooks.BindInviteHooks(app)
	hooks.BindBookmarkHooks(app)
	hooks.BindContactHooks(app)
	hooks.BindContactBlockHooks(app)
	hooks.BindWebhookHooks(app)
	hooks.RegisterTenancyHooks(app)
	hooks.BindAuditLogHooks(app)
	hooks.BindBuiltinTemplateSync(app)

	routes.HealthzRoute(app)
	routes.PublicLinksRoute(app, root)
	routes.PublicRequestsRoute(app, root)
	routes.PublicInvitesRoute(app, root)
	routes.PermissionsRoute(app)
	routes.FeaturesRoute(app)
	routes.AccountFeaturesRoute(app)
	routes.WorkspaceMembersRoute(app)
	routes.RequestGrantsRoute(app)
	routes.ContactGrantsRoute(app, root)
	routes.RemoteGrantsRoute(app, root)
	routes.CallbackTestRoute(app)
	routes.WebhooksRoute(app)
	routes.PublicShortRoute(app, root)
	routes.PublicDavRoute(app)
	routes.PublicFilesRoute(app)
	routes.SealedRoute(app)
	routes.OwnerFilesRoute(app)
	routes.CertificateRoute(app)
	routes.IdentityStatusRoute(app, root)
	routes.ChallengeRoute(app)
	routes.ServerInfoRoute(app, root)
	routes.VerifyPeerRoute(app)
	routes.DeleteAccountRoute(app)
	routes.ConnectionsRoute(app, root)
	routes.ConnectionDraftsRoute(app)
	routes.VaultRoute(app)
	routes.SharedVaultRoute(app)
	routes.ConnectionCreateRoute(app, root)
	routes.PasskeysRoute(app, root)
	routes.TwoFactorRoute(app)
	routes.AppPageRoute(app, root)
	routes.OIDCRoute(app, root)
	routes.AttestationsRoute(app, root)
	routes.AttestationChecksRoute(app, root)
	routes.AttestationSharesRoute(app, root)
	routes.SignupEmailRoute(app, root)
}
