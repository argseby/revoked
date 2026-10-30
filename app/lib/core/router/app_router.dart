import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/models/attestation_ask.dart';
import 'package:revoked_app/core/models/presentation_request.dart';
import 'package:revoked_app/core/models/share_proposal.dart';
import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/router/resume_location.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/attestations/view/attestation_offer_screen.dart';
import 'package:revoked_app/features/attestations/view/attestations_screen.dart';
import 'package:revoked_app/features/attestations/view/presentation_screen.dart';
import 'package:revoked_app/features/auth/view/login_screen.dart';
import 'package:revoked_app/features/shell/view/app_shell.dart';
import 'package:revoked_app/features/settings/view/settings_pages.dart';
import 'package:revoked_app/features/settings/view/settings_screen.dart';
import 'package:revoked_app/features/shell/view/splash_screen.dart';
import 'package:revoked_app/features/vault/view/record_detail_screen.dart';
import 'package:revoked_app/features/vault/view/vault_screen.dart';
import 'package:revoked_app/features/shares/view/share_detail_screen.dart';
import 'package:revoked_app/features/shares/view/shared_split.dart';
import 'package:revoked_app/features/shares/view/public_share_screen.dart';
import 'package:revoked_app/features/shares/view/share_proposal_screen.dart';
import 'package:revoked_app/features/connections/view/connect_screen.dart';
import 'package:revoked_app/features/connections/view/sign_in_approval_screen.dart';
import 'package:revoked_app/features/connections/view/connections_section.dart';
import 'package:revoked_app/features/requests/view/inbox_screen.dart';
import 'package:revoked_app/features/requests/view/request_detail_screen.dart';
import 'package:revoked_app/features/requests/view/public_request_screen.dart';
import 'package:revoked_app/features/data/view/data_screen.dart';
import 'package:revoked_app/features/requests/view/request_sheet_screen.dart';
import 'package:revoked_app/features/invites/view/invite_accept_screen.dart';
import 'package:revoked_app/features/onboarding/view/tour_screen.dart';
import 'package:revoked_app/features/onboarding/view/workspace_onboarding_screen.dart';
import 'package:revoked_app/features/overview/view/overview_screen.dart';

abstract class AppRoutes {
  static const login = '/login';

  /// What needs the person's attention, and who can read their data. Where
  /// the app lands after sign-in.
  static const overview = '/overview';
  static const vault = '/vault';

  /// One record's detail page, opened from the Vault list.
  static String recordDetailFor(String id) => '$vault/records/$id';

  /// The one-minute walk through records, links and revoking.
  static const tour = '$vault/tour';

  /// Blueprints for records and requests. They used to be a settings topic.
  static const templates = '$vault/templates';

  /// The links the person gave out.
  static const shared = '/shared';

  /// One link's detail page, opened from the Shared list.
  static String shareDetailFor(String id) => '$shared/$id';

  /// The person's requests, and what came back.
  static const requests = '/requests';

  /// Links other people gave the person, under Requests.
  static const requestsReceived = '$requests?tab=received';

  /// One request's detail page, opened from the Requests list.
  static String requestDetailFor(String id) => '$requests/$id';

  /// What one request collected, as a list or as a spreadsheet.
  static String requestDataFor(String id) => '$requests/$id/data';
  static String requestSheetFor(String id) => '$requests/$id/sheet';

  /// What others attested about the person, and what they attested.
  static const attestations = '/attestations';

  /// The people the person asked to show an attestation.
  static const attestationsChecked = '$attestations?tab=checked';
  static const settings = '/settings';

  /// Each settings topic is a page of its own under Settings.
  static String settingsPage(String slug) => '$settings/$slug';
  static const settingsWorkspace = '/settings/workspaces';
  static const apiKeys = '/settings/api-keys';
  static const connectedTools = '/settings/connected-tools';
  static String connectedToolFor(String id) => '$connectedTools/$id';
  static const share = '/share/:slug';
  static const request = '/request/:slug';
  // Short, canonical public paths (the deep links generate these).
  static const shortShare = '/s/:slug';
  static const shortRequest = '/r/:slug';
  static const invite = '/i/:token';
  // A share a tool proposes; created only after the owner confirms it.
  static const proposal = '/p';
  // A tool asking to be connected; nothing is connected until the owner agrees.
  static const connect = '/connect';
  // A service asking to sign its user in; continued in the browser, on the
  // server the app is signed into.
  static const signIn = '/signin';
  // An offer to attest something about one of the person's identities.
  // Accepting needs one of those identities, so it needs their session.
  static const attestationOffer = '/a/:token';
  // A service asking to be shown an attestation the person holds.
  static const present = '/present';
  static const onboarding = '/onboarding';

  /// Shown while the stored session is being checked.
  static const splash = '/splash';

  // Legacy aliases — kept so any deep-links or bookmarks still resolve
  static const inbox = '/inbox';
  static const data = '/data';
  static const shares = '/shares';
  static const requestData = '/request-data';
  static const requestSheet = '/request-sheet';
  static const settingsTemplates = '/settings/templates';
  static const connections = '/connections';
  static const receivedVault = '/received-vault';

  /// The places the shell's navigation leads to, in order.
  static const destinations = [overview, vault, shared, requests, attestations];

  /// Which of [destinations] a location belongs to, or null outside them
  /// (Settings, and every screen without the shell).
  static int? destinationOf(String location) {
    final path = Uri.tryParse(location)?.path ?? location;
    for (var i = 0; i < destinations.length; i++) {
      final root = destinations[i];
      if (path == root || path.startsWith('$root/')) return i;
    }
    return null;
  }
}

class AppRouter {
  /// Root navigator, so app-level actions (the global paste shortcut) can
  /// open sheets without a screen's context.
  static final rootNavigatorKey = GlobalKey<NavigatorState>();

  AppRouter._();

  /// Where the app was headed when it was sent to the splash. A deep link
  /// arrives on the first frame, before the stored session has been checked,
  /// so the destination has to survive that wait.
  static String? _pendingLocation;

  static GoRouter create(AuthStore authStore) {
    return GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: AppRoutes.overview,
      refreshListenable: _AuthRefreshNotifier(authStore),
      redirect: (context, state) {
        bool isPublic(String s) =>
            s.startsWith('/share/') ||
            s.startsWith('/request/') ||
            s.startsWith('/s/') ||
            s.startsWith('/r/') ||
            s.startsWith('/i/');
        final isPublicRoute =
            isPublic(state.matchedLocation) || isPublic(state.uri.path);

        // Until the stored session has been checked, "logged out" is not yet
        // true — routing on it would bounce a returning user to the login
        // screen for as long as the refresh takes.
        //
        // A public route is exempt: it needs no session, and sending it to the
        // splash discarded where it was going. That is what stopped a
        // revoked:// link opening the request it named — the link arrives on
        // the first frame, before the session check has finished.
        if (!authStore.isInitialized && !isPublicRoute) {
          if (state.matchedLocation != AppRoutes.splash) {
            _pendingLocation = state.uri.toString();
            return AppRoutes.splash;
          }
          return null;
        }
        if (state.matchedLocation == AppRoutes.splash) {
          // Resume whatever was asked for before the session was known.
          final pending = _pendingLocation;
          _pendingLocation = null;
          if (pending != null && pending != AppRoutes.splash) return pending;
          return authStore.isAuthenticated
              ? AppRoutes.overview
              : AppRoutes.login;
        }

        final isLoggedIn = authStore.isAuthenticated;
        final isAuthRoute = state.matchedLocation == AppRoutes.login;

        // A link that meets the login screen or onboarding is held and taken
        // up again once they are done, rather than dropped for the vault -
        // that made someone new go back to the tool and start over.
        if (!isLoggedIn && !isAuthRoute && !isPublicRoute) {
          ResumeLocation.hold(state.uri.toString());
          return AppRoutes.login;
        }

        // Ahead of the workspace check, so an invite that waited for the
        // sign-in is shown before onboarding offers to create a workspace.
        if (isLoggedIn && isAuthRoute) {
          return ResumeLocation.take() ?? AppRoutes.overview;
        }

        // An account has no workspace until it creates or joins one, and every
        // other screen is scoped to a workspace, so onboarding comes first.
        final needsWorkspace =
            isLoggedIn && (authStore.activeWorkspace ?? '').isEmpty;
        final onOnboarding = state.matchedLocation == AppRoutes.onboarding;
        if (needsWorkspace && !onOnboarding && !isPublicRoute) {
          ResumeLocation.hold(state.uri.toString());
          return AppRoutes.onboarding;
        }
        if (!needsWorkspace && onOnboarding) {
          // Onboarding finishes setting up (the signing identity) after the
          // workspace exists, and moves on by itself once that is done.
          if (Stores.onboarding.isBusy) return null;
          return ResumeLocation.take() ?? AppRoutes.overview;
        }
        return null;
      },
      routes: [
        GoRoute(
          path: AppRoutes.splash,
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: AppRoutes.share,
          builder: (context, state) => PublicShareScreen(
            shareSlug: state.pathParameters['slug'] ?? '',
            origin: state.uri.queryParameters['o'],
          ),
        ),
        GoRoute(
          path: AppRoutes.request,
          builder: (context, state) => PublicRequestScreen(
            requestSlug: state.pathParameters['slug'] ?? '',
            origin: state.uri.queryParameters['o'],
          ),
        ),
        // Short canonical aliases.
        GoRoute(
          path: AppRoutes.shortShare,
          builder: (context, state) => PublicShareScreen(
            shareSlug: state.pathParameters['slug'] ?? '',
            origin: state.uri.queryParameters['o'],
          ),
        ),
        GoRoute(
          path: AppRoutes.shortRequest,
          builder: (context, state) => PublicRequestScreen(
            requestSlug: state.pathParameters['slug'] ?? '',
            origin: state.uri.queryParameters['o'],
          ),
        ),
        // Readable while signed out so the recipient can see what an invite
        // grants before deciding to create or use an account; accepting still
        // requires a session.
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (context, state) => const WorkspaceOnboardingScreen(),
        ),
        GoRoute(
          path: AppRoutes.invite,
          builder: (context, state) => InviteAcceptScreen(
            token: state.pathParameters['token'] ?? '',
            origin: state.uri.queryParameters['o'],
          ),
        ),
        // Not public: it creates a share, so it needs the owner's session.
        GoRoute(
          path: AppRoutes.proposal,
          builder: (context, state) => ShareProposalScreen(
            proposal: ShareProposal.fromQuery(state.uri.queryParameters),
          ),
        ),
        GoRoute(
          path: AppRoutes.connect,
          builder: (context, state) => ConnectScreen(
            request: ConnectRequest.fromQuery(state.uri.queryParameters),
          ),
        ),
        // Not public: the server to continue on is the one signed into.
        GoRoute(
          path: AppRoutes.signIn,
          builder: (context, state) => SignInApprovalScreen(
            request: SignInRequest.fromQuery(state.uri.queryParameters),
          ),
        ),
        // Not public: the identity an offer is accepted with, and the
        // credentials a presentation draws on, are the signed-in person's.
        GoRoute(
          path: AppRoutes.attestationOffer,
          builder: (context, state) => AttestationOfferScreen(
            token: state.pathParameters['token'] ?? '',
            origin: state.uri.queryParameters['o'],
          ),
        ),
        GoRoute(
          path: AppRoutes.present,
          builder: (context, state) => PresentationScreen(
            request: PresentationRequest.fromQuery(state.uri.queryParameters),
          ),
        ),
        // Fallbacks for public URLs missing slugs
        GoRoute(
          path: '/request',
          redirect: (context, state) => AppRoutes.requests,
        ),
        GoRoute(path: '/share', redirect: (context, state) => AppRoutes.shared),
        // Legacy route redirects. Each keeps what the old path carried, so a
        // bookmark or an old notification still lands on the same thing.
        // Siblings rather than children: a parent's redirect runs first and
        // would send every /inbox/... to the list.
        GoRoute(
          path: AppRoutes.inbox,
          redirect: (context, state) => AppRoutes.requests,
        ),
        GoRoute(
          path: '${AppRoutes.inbox}/:id',
          redirect: (context, state) {
            final id = state.pathParameters['id']!;
            return id == 'create'
                ? AppRoutes.requests
                : AppRoutes.requestDetailFor(id);
          },
        ),
        GoRoute(
          path: AppRoutes.data,
          redirect: (context, state) => _keepQuery(AppRoutes.shared, state),
        ),
        GoRoute(
          path: AppRoutes.shares,
          redirect: (context, state) => _keepQuery(AppRoutes.shared, state),
        ),
        GoRoute(
          path: '${AppRoutes.shares}/:id',
          redirect: (context, state) =>
              AppRoutes.shareDetailFor(state.pathParameters['id']!),
        ),
        GoRoute(
          path: AppRoutes.requestData,
          redirect: (context, state) =>
              switch (state.uri.queryParameters['requestId']) {
                final String id when id.isNotEmpty => AppRoutes.requestDataFor(
                  id,
                ),
                _ => AppRoutes.requests,
              },
        ),
        GoRoute(
          path: AppRoutes.requestSheet,
          redirect: (context, state) =>
              switch (state.uri.queryParameters['requestId']) {
                final String id when id.isNotEmpty => AppRoutes.requestSheetFor(
                  id,
                ),
                _ => AppRoutes.requests,
              },
        ),
        GoRoute(
          path: AppRoutes.connections,
          redirect: (context, state) => AppRoutes.requestsReceived,
        ),
        GoRoute(
          path: AppRoutes.receivedVault,
          redirect: (context, state) => AppRoutes.requestsReceived,
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: AppRoutes.overview,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: OverviewScreen()),
            ),
            GoRoute(
              path: AppRoutes.vault,
              pageBuilder: (context, state) {
                final editShareId = state.uri.queryParameters['editShareId'];
                final shareFilterId =
                    state.uri.queryParameters['shareFilterId'];
                return NoTransitionPage(
                  child: VaultScreen(
                    editingShareId: editShareId,
                    shareFilterId: shareFilterId,
                  ),
                );
              },
              routes: [
                GoRoute(
                  path: 'tour',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: TourScreen()),
                ),
                GoRoute(
                  path: 'templates',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: SettingsPageScreen(
                      key: ValueKey(SettingsPage.templates),
                      page: SettingsPage.templates,
                    ),
                  ),
                ),
                GoRoute(
                  path: 'records/:id',
                  pageBuilder: (context, state) => NoTransitionPage(
                    child: RecordDetailScreen(
                      key: ValueKey(state.pathParameters['id']),
                      recordId: state.pathParameters['id']!,
                    ),
                  ),
                ),
              ],
            ),
            // The links list and the chosen link. A shell of its own, so the
            // list outlives each link opened beside it on a wide window.
            ShellRoute(
              builder: (context, state, child) => SharedSplit(
                selectedId: state.pathParameters['id'],
                filterSlug: state.uri.queryParameters['filterSlug'],
                child: child,
              ),
              routes: [
                GoRoute(
                  path: AppRoutes.shared,
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: SharedPlaceholder()),
                ),
                GoRoute(
                  path: '${AppRoutes.shared}/:id',
                  pageBuilder: (context, state) => NoTransitionPage(
                    child: ShareDetailScreen(
                      key: ValueKey(state.pathParameters['id']),
                      shareId: state.pathParameters['id']!,
                    ),
                  ),
                ),
              ],
            ),
            // One request's data and sheet stand on their own, ahead of
            // /requests/:id, so the detail page is not built beneath them.
            GoRoute(
              path: '${AppRoutes.requests}/:id/data',
              pageBuilder: (context, state) => NoTransitionPage(
                child: DataScreen(
                  key: ValueKey(state.pathParameters['id']),
                  requestId: state.pathParameters['id'],
                ),
              ),
            ),
            GoRoute(
              path: '${AppRoutes.requests}/:id/sheet',
              pageBuilder: (context, state) => NoTransitionPage(
                child: RequestSheetScreen(
                  key: ValueKey(state.pathParameters['id']),
                  requestId: state.pathParameters['id']!,
                ),
              ),
            ),
            GoRoute(
              path: AppRoutes.requests,
              pageBuilder: (context, state) => NoTransitionPage(
                child: InboxScreen(
                  initialTab: state.uri.queryParameters['tab'] == 'received'
                      ? 1
                      : 0,
                ),
              ),
              routes: [
                GoRoute(
                  path: ':id',
                  pageBuilder: (context, state) => NoTransitionPage(
                    child: RequestDetailScreen(
                      key: ValueKey(state.pathParameters['id']),
                      requestId: state.pathParameters['id']!,
                    ),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: AppRoutes.attestations,
              pageBuilder: (context, state) => NoTransitionPage(
                child: AttestationsScreen(
                  ask: AttestationAsk.fromQuery(state.uri.queryParameters),
                  initialTab: switch (state.uri.queryParameters['tab']) {
                    'issued' => 1,
                    'checked' => 2,
                    _ => 0,
                  },
                ),
              ),
            ),
            GoRoute(
              path: AppRoutes.settings,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SettingsScreen()),
              routes: [
                GoRoute(
                  path: 'connected-tools/:id',
                  pageBuilder: (context, state) => NoTransitionPage(
                    child: ConnectedToolPage(
                      key: ValueKey(state.pathParameters['id']),
                      connectionId: state.pathParameters['id']!,
                    ),
                  ),
                ),
                GoRoute(
                  path: ':page',
                  // An unknown topic — or an old ?tab= link — lands on the
                  // list rather than on an empty page.
                  // Templates moved to the vault.
                  redirect: (context, state) => switch (SettingsPage.fromSlug(
                    state.pathParameters['page'],
                  )) {
                    // Attestations became a place of their own.
                    null when state.pathParameters['page'] == 'attestations' =>
                      AppRoutes.attestations,
                    null => AppRoutes.settings,
                    SettingsPage.templates => AppRoutes.templates,
                    _ => null,
                  },
                  pageBuilder: (context, state) {
                    final page = SettingsPage.fromSlug(
                      state.pathParameters['page'],
                    )!;
                    return NoTransitionPage(
                      child: SettingsPageScreen(
                        key: ValueKey(page),
                        page: page,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// [path] with the query the old location carried.
String _keepQuery(String path, GoRouterState state) =>
    state.uri.hasQuery ? '$path?${state.uri.query}' : path;

/// Re-runs the router's [GoRouter.redirect] whenever auth state flips, without
/// recreating the router — so a single stable router instance can also drive
/// deep-link navigation.
class _AuthRefreshNotifier extends ChangeNotifier {
  late final ReactionDisposer _disposer;

  _AuthRefreshNotifier(AuthStore store) {
    // Every observable the redirect reads, not just the login flag. The
    // redirect only re-runs when this notifies - watching isAuthenticated
    // alone froze a signed-out start on the splash forever, because a
    // no-session initialize() completes with the flag still false and
    // nothing ever woke the router to notice isInitialized had flipped.
    _disposer = reaction(
      (_) =>
          (store.isInitialized, store.isAuthenticated, store.activeWorkspace),
      (_) => notifyListeners(),
    );
  }

  @override
  void dispose() {
    _disposer();
    super.dispose();
  }
}
