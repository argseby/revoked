import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/router/app_router.dart';

/// The documentation page for each place in the app, by route prefix. The
/// longest matching prefix wins, so a settings page beats Settings itself.
const _pages = <String, String>{
  AppRoutes.overview: '/guide/overview/',
  AppRoutes.templates: '/guide/templates/',
  AppRoutes.vault: '/guide/vault/',
  AppRoutes.shared: '/guide/sharing/',
  AppRoutes.requests: '/guide/requests/',
  AppRoutes.attestations: '/guide/attestations/',
  AppRoutes.contacts: '/guide/contacts/',
  AppRoutes.notifications: '/guide/notifications/',
  AppRoutes.settings: '/guide/#navigation',
  '/settings/appearance': '/guide/appearance/',
  '/settings/features': '/guide/features/',
  '/settings/passkeys': '/guide/passkeys/',
  '/settings/encryption': '/guide/encryption/',
  '/settings/workspaces': '/guide/workspaces/',
  '/settings/members': '/guide/workspaces/#member-permissions',
  '/settings/invites': '/guide/workspaces/#invites',
  '/settings/identities': '/guide/identities/',
  '/settings/domain': '/guide/identities/#domain-verification',
  AppRoutes.connectedTools: '/guide/tools/#managing-connected-tools',
  '/settings/signed-in': '/guide/tools/#sign-in-services',
  AppRoutes.apiKeys: '/guide/tools/#api-keys-for-scripts',
  AppRoutes.webhooks: '/api/webhooks/',
  AppRoutes.settingsTemplates: '/guide/templates/',
};

/// The documentation URL for [path], or null where there is none.
String? docsUrlFor(String path) {
  String? best;
  for (final prefix in _pages.keys) {
    if ((path == prefix || path.startsWith('$prefix/')) &&
        (best == null || prefix.length > best.length)) {
      best = prefix;
    }
  }
  return best == null ? null : '${AppConfig.docsUrl}${_pages[best]}';
}
