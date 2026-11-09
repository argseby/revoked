import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/router/resume_location.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/services/device_unlock.dart';
import 'package:revoked_app/core/services/domain_verification_service.dart';
import 'package:revoked_app/core/services/handshake_service.dart';
import 'package:revoked_app/core/services/workspace_context.dart';
import 'package:revoked_app/core/state/load_state.dart';
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
import 'package:revoked_app/features/connections/store/sign_ins_store.dart';
import 'package:revoked_app/features/contacts/store/contacts_store.dart';
import 'package:revoked_app/features/identities/store/identities_store.dart';
import 'package:revoked_app/features/identities/store/identity_replacement_store.dart';
import 'package:revoked_app/features/invites/store/invites_store.dart';
import 'package:revoked_app/features/notifications/store/notifications_store.dart';
import 'package:revoked_app/features/onboarding/store/onboarding_store.dart';
import 'package:revoked_app/features/passkeys/store/passkeys_store.dart';
import 'package:revoked_app/features/reminders/store/reminders_store.dart';
import 'package:revoked_app/features/requests/store/requests_store.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';
import 'package:revoked_app/features/sealing/store/member_keys_store.dart';
import 'package:revoked_app/features/settings/store/features_store.dart';
import 'package:revoked_app/features/settings/store/settings_store.dart';
import 'package:revoked_app/features/settings/store/updates_store.dart';
import 'package:revoked_app/features/shares/store/shares_store.dart';
import 'package:revoked_app/features/shell/store/link_search_store.dart';
import 'package:revoked_app/features/templates/store/templates_store.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/webhooks/store/webhooks_store.dart';
import 'package:revoked_app/features/works_with/store/works_with_store.dart';

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
  static late MemberKeysStore memberKeys;
  static late VaultStore vault;
  static late SharesStore shares;
  static late BookmarksStore bookmarks;
  static late ConnectionsStore connections;
  static late SignInsStore signIns;
  static late ContactsStore contacts;
  static late PasskeysStore passkeys;
  static late RequestsStore requests;
  static late TemplatesStore templates;
  static late ApiKeysStore apiKeys;
  static late WebhooksStore webhooks;
  static late IdentitiesStore identities;
  static late CredentialsStore credentials;
  static late IdentityReplacementStore identityReplacement;
  static late AttestationsStore attestations;
  static late AttestationChecksStore attestationChecks;
  static late NotificationsStore notifications;
  static late RemindersStore reminders;
  static late SettingsStore settings;
  static late FeaturesStore features;
  static late InvitesStore invites;
  static late ServerSettingsStore serverSettings;
  static late UpdatesStore updates;
  static late LinkSearchStore linkSearch;
  static late OnboardingStore onboarding;
  static late WorksWithStore worksWith;

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
    keys = KeysStore(
      api,
      currentUser: () => auth.userId,
      // Keys cross between people only through lists this device checked.
      membersOf: (workspace, {fresh = false}) =>
          memberKeys.membersOf(workspace, fresh: fresh),
    );
    memberKeys = MemberKeysStore(
      api,
      currentUser: () => auth.userId,
      ownRoot: () => keys.rootHash,
    );
    // Decrypted values go with the keys: nothing readable outlives the session.
    auth.onLoggedOut = () {
      keys.forgetSession();
      memberKeys.forgetSession();
      forgetAccountData();
      settings.forgetDomainCheck();
    };
    auth.onPasskeySignIn = keys.offerPasskeySignIn;
    api.onWrite = invalidateLoads;
    // A rejected session drops to the login screen from wherever it happened.
    api.onUnauthorized = () => unawaited(auth.handleSessionExpired());
    // The server holds the session until an authenticator is set up: the
    // router then shows the setup screen.
    api.onTwoFactorSetupRequired = () =>
        runInAction(() => auth.twoFactorSetupRequired = true);
    vault = VaultStore(api);
    shares = SharesStore(api);
    bookmarks = BookmarksStore(api);
    connections = ConnectionsStore(api);
    signIns = SignInsStore(api);
    contacts = ContactsStore(api);
    passkeys = PasskeysStore(api);
    requests = RequestsStore(api);
    templates = TemplatesStore(api);
    apiKeys = ApiKeysStore(api);
    webhooks = WebhooksStore(api);
    identities = IdentitiesStore(api, crypto);
    deviceUnlock = unlock ?? SystemDeviceUnlock();
    signInApproval = SignInApproval(api, crypto, identities, deviceUnlock);
    credentials = CredentialsStore(api, crypto, handshake, domainVerification);
    identityReplacement = IdentityReplacementStore(identities, credentials);
    attestations = AttestationsStore(api);
    attestationChecks = AttestationChecksStore(api);
    notifications = NotificationsStore(api);
    reminders = RemindersStore(api);
    settings = SettingsStore(api);
    invites = InvitesStore(api, domainVerification);
    features = FeaturesStore(
      api,
      user: () => auth.currentUser,
      userChanged: auth.replaceUser,
      members: () => invites.members,
    );
    serverSettings = ServerSettingsStore(api);
    updates = UpdatesStore(
      httpClient: httpClient,
      serverVersion: () => serverSettings.serverVersion,
    );
    linkSearch = LinkSearchStore();
    onboarding = OnboardingStore();
    // The shipped list, before any proposal screen can open: a deep link may
    // mount one in the frame init finishes. The newer copy follows later.
    worksWith = WorksWithStore(httpClient: httpClient);
    await worksWith.loadLocal().timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );

    // Whenever a session begins, by signing in or by restoring one, the
    // server's DNS check and release are asked for. On a new device nothing
    // else does so until a screen happens to, and until then the domain
    // claim reads as unverified and the server's release as unknown.
    _onSession?.call();
    _onSession = reaction((_) => auth.userId, (String id) {
      if (id.isEmpty) return;
      settings.ensureDomainChecked();
      unawaited(serverSettings.loadServerVersion());
    }, fireImmediately: true);

    // Deliberately not awaited here: restoring the session is a network call,
    // and awaiting it before runApp meant the first frame waited on the
    // server. The router shows a splash until isInitialized flips.
    unawaited(auth.initialize());
  }

  static ReactionDisposer? _onSession;

  static List<LoadState> get _loads => [
    vault.loadState,
    shares.loadState,
    requests.loadState,
    bookmarks.loadState,
    contacts.loadState,
    identities.loadState,
    credentials.loadState,
    attestations.loadState,
    attestationChecks.loadState,
    signIns.loadState,
    features.loadState,
    webhooks.loadState,
  ];

  /// Makes every cached list fetch again the next time a screen asks for it.
  static void invalidateLoads() {
    for (final load in _loads) {
      load.invalidate();
    }
  }

  /// Empties everything scoped to the active workspace, so a failed reload
  /// shows nothing rather than the previous workspace's rows. A load still on
  /// its way can't put them back: see [LoadState.begin].
  static void forgetWorkspaceData() {
    runInAction(() {
      for (final load in _loads) {
        load.reset();
      }
      vault.records.clear();
      vault.sections.clear();
      vault.sharedRecords.clear();
      vault.sharedSections.clear();
      shares.shares.clear();
      requests.requests.clear();
      requests.responsesByRequest.clear();
      bookmarks.bookmarks.clear();
      bookmarks.groups.clear();
      contacts.contacts.clear();
      identities.identities.clear();
      credentials.credentials.clear();
      credentials.verdicts.clear();
      credentials.shares.clear();
      attestations.attestations.clear();
      attestationChecks.checks.clear();
      signIns.services.clear();
      signIns.links.clear();
      templates.templates.clear();
      invites.invites.clear();
      invites.members.clear();
      webhooks.forget();
    });
  }

  /// Empties everything the signed-in account could read, so the next account
  /// on this device starts from nothing.
  static void forgetAccountData() {
    forgetWorkspaceData();
    runInAction(() {
      notifications.notifications.clear();
      connections.connections.clear();
      connections.linksByConnection.clear();
      connections.requestsByConnection.clear();
      connections.attestationsByConnection.clear();
      connections.checksByConnection.clear();
      passkeys.passkeys.clear();
      apiKeys.apiKeys.clear();
      reminders.reminders.clear();
    });
  }
}
