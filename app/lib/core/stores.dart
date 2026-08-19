import 'dart:async';

import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/services/domain_verification_service.dart';
import 'package:revoked_app/core/services/handshake_service.dart';
import 'package:revoked_app/core/services/workspace_context.dart';
import 'package:revoked_app/core/theme/theme_store.dart';
import 'package:revoked_app/features/api_keys/store/api_keys_store.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/identities/store/identities_store.dart';
import 'package:revoked_app/features/invites/store/invites_store.dart';
import 'package:revoked_app/features/notifications/store/notifications_store.dart';
import 'package:revoked_app/features/requests/store/requests_store.dart';
import 'package:revoked_app/features/settings/store/settings_store.dart';
import 'package:revoked_app/features/shares/store/shares_store.dart';
import 'package:revoked_app/features/templates/store/templates_store.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';

/// The one access point for every store and stateless service.
///
/// Singleton stores live here; state that lasts only as long as a page (a
/// create flow, a table) is a store the page constructs and disposes itself.
abstract final class Stores {
  static late final ApiClient api;
  static late final CryptoService crypto;
  static late final HandshakeService handshake;
  static late final DomainVerificationService domainVerification;
  static const WorkspaceContext workspaceContext = WorkspaceContext();

  static late final ThemeStore theme;
  static late final AuthStore auth;
  static late final VaultStore vault;
  static late final SharesStore shares;
  static late final RequestsStore requests;
  static late final TemplatesStore templates;
  static late final ApiKeysStore apiKeys;
  static late final IdentitiesStore identities;
  static late final NotificationsStore notifications;
  static late final SettingsStore settings;
  static late final InvitesStore invites;

  static Future<void> init() async {
    api = ApiClient();
    await api.loadServerConfig();

    crypto = CryptoService();
    handshake = HandshakeService(api, crypto);
    domainVerification = DomainVerificationService(crypto: crypto);

    theme = ThemeStore();
    await theme.load();

    auth = AuthStore(api);
    // A rejected session drops to the login screen from wherever it happened.
    api.onUnauthorized = () => unawaited(auth.handleSessionExpired());
    vault = VaultStore(api);
    shares = SharesStore(api);
    requests = RequestsStore(api);
    templates = TemplatesStore(api);
    apiKeys = ApiKeysStore(api);
    identities = IdentitiesStore(api, crypto);
    notifications = NotificationsStore(api);
    settings = SettingsStore(api);
    invites = InvitesStore(api);

    // Deliberately not awaited here: restoring the session is a network call,
    // and awaiting it before runApp meant the first frame waited on the
    // server. The router shows a splash until isInitialized flips.
    unawaited(auth.initialize());
  }
}
