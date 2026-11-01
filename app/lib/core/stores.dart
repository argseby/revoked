import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/router/resume_location.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/services/device_unlock.dart';
import 'package:revoked_app/core/services/domain_verification_service.dart';
import 'package:revoked_app/core/services/handshake_service.dart';
import 'package:revoked_app/core/services/workspace_context.dart';
import 'package:revoked_app/core/theme/theme_store.dart';
import 'package:revoked_app/features/api_keys/store/api_keys_store.dart';
import 'package:revoked_app/features/attestations/store/attestations_store.dart';
import 'package:revoked_app/features/attestations/store/attestation_checks_store.dart';
import 'package:revoked_app/features/attestations/store/credentials_store.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/auth/store/server_settings_store.dart';
import 'package:revoked_app/features/bookmarks/store/bookmarks_store.dart';
import 'package:revoked_app/features/connections/sign_in_approval.dart';
import 'package:revoked_app/features/connections/store/connections_store.dart';
import 'package:revoked_app/features/contacts/store/contacts_store.dart';
import 'package:revoked_app/features/identities/store/identities_store.dart';
import 'package:revoked_app/features/invites/store/invites_store.dart';
import 'package:revoked_app/features/notifications/store/notifications_store.dart';
import 'package:revoked_app/features/onboarding/store/onboarding_store.dart';
import 'package:revoked_app/features/passkeys/store/passkeys_store.dart';
import 'package:revoked_app/features/reminders/store/reminders_store.dart';
import 'package:revoked_app/features/requests/store/requests_store.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';
import 'package:revoked_app/features/settings/store/settings_store.dart';
import 'package:revoked_app/features/shares/store/shares_store.dart';
import 'package:revoked_app/features/shell/store/link_search_store.dart';
import 'package:revoked_app/features/templates/store/templates_store.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';

/// The one access point for every store and stateless service.
///
/// Singleton stores live here; state that lasts only as long as a page (a
/// create flow, a table) is a store the page constructs and disposes itself.
abstract final class Stores {
  static late ApiClient api;
  static late CryptoService crypto;
  static late HandshakeService handshake;
  static late DomainVerificationService domainVerification;
  static late DeviceUnlock deviceUnlock;
  static late SignInApproval signInApproval;
  static const WorkspaceContext workspaceContext = WorkspaceContext();

  static late ThemeStore theme;
  static late AuthStore auth;
  static late KeysStore keys;
  static late VaultStore vault;
  static late SharesStore shares;
  static late BookmarksStore bookmarks;
  static late ConnectionsStore connections;
  static late ContactsStore contacts;
  static late PasskeysStore passkeys;
  static late RequestsStore requests;
  static late TemplatesStore templates;
  static late ApiKeysStore apiKeys;
  static late IdentitiesStore identities;
  static late CredentialsStore credentials;
  static late AttestationsStore attestations;
  static late AttestationChecksStore attestationChecks;
  static late NotificationsStore notifications;
  static late RemindersStore reminders;
  static late SettingsStore settings;
  static late InvitesStore invites;
  static late ServerSettingsStore serverSettings;
  static late LinkSearchStore linkSearch;
  static late OnboardingStore onboarding;

  /// [httpClient] replaces the network, for tests that play a server, and
  /// [unlock] the system's fingerprint, face or PIN prompt.
  ///
  /// Callable more than once, which is why the fields above are not `final`:
  /// a MobX `AsyncAction` forks and caches a zone the first time it runs, so
  /// a store that outlives the zone it was first used in runs every later
  /// async action in a dead one — the body's awaits are queued on a
  /// microtask queue nobody drains again. A widget test gets its own zone per
  /// case, so each one has to build its own stores.
  static Future<void> init({
    http.Client? httpClient,
    DeviceUnlock? unlock,
  }) async {
    api = ApiClient(httpClient: httpClient);
    await api.loadServerConfig();

    crypto = CryptoService();
    handshake = HandshakeService(api, crypto);
    domainVerification = DomainVerificationService(
      httpClient: httpClient,
      crypto: crypto,
    );
    // Awaited, not fired off: a deep link can mount its screen in the same
    // frame as init finishes, and an unloaded cache reads as "no verdict"
    // - which is exactly the spinner it exists to avoid. Bounded so a
    // stalled preferences plugin cannot hold up startup.
    await domainVerification.loadCache().timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );

    theme = ThemeStore();
    await theme.load();
    // A link held while someone signed up in the browser, in case the system
    // closed the app meanwhile. Bounded like the cache above.
    await ResumeLocation.load().timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );

    auth = AuthStore(api);
    keys = KeysStore(api, currentUser: () => auth.userId);
    // Decrypted values go with the keys: nothing readable outlives the session.
    auth.onLoggedOut = () {
      keys.forgetSession();
      vault.records.clear();
    };
    // A rejected session drops to the login screen from wherever it happened.
    api.onUnauthorized = () => unawaited(auth.handleSessionExpired());
    vault = VaultStore(api);
    shares = SharesStore(api);
    bookmarks = BookmarksStore(api);
    connections = ConnectionsStore(api);
    contacts = ContactsStore(api);
    passkeys = PasskeysStore(api);
    requests = RequestsStore(api);
    templates = TemplatesStore(api);
    apiKeys = ApiKeysStore(api);
    identities = IdentitiesStore(api, crypto);
    deviceUnlock = unlock ?? SystemDeviceUnlock();
    signInApproval = SignInApproval(api, crypto, identities, deviceUnlock);
    credentials = CredentialsStore(api, crypto, handshake, domainVerification);
    attestations = AttestationsStore(api);
    attestationChecks = AttestationChecksStore(api);
    notifications = NotificationsStore(api);
    reminders = RemindersStore(api);
    settings = SettingsStore(api);
    invites = InvitesStore(api, domainVerification);
    serverSettings = ServerSettingsStore(api);
    linkSearch = LinkSearchStore();
    onboarding = OnboardingStore();

    // Deliberately not awaited here: restoring the session is a network call,
    // and awaiting it before runApp meant the first frame waited on the
    // server. The router shows a splash until isInitialized flips.
    unawaited(auth.initialize());
  }
}
