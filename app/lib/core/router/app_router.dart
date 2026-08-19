import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:mobx/mobx.dart';

import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/auth/view/login_screen.dart';
import 'package:revoked_app/features/auth/view/register_screen.dart';
import 'package:revoked_app/features/shell/view/app_shell.dart';
import 'package:revoked_app/features/settings/view/settings_screen.dart';
import 'package:revoked_app/features/shell/view/splash_screen.dart';
import 'package:revoked_app/features/vault/view/vault_screen.dart';
import 'package:revoked_app/features/shares/view/shares_screen.dart';
import 'package:revoked_app/features/shares/view/public_share_screen.dart';
import 'package:revoked_app/features/api_keys/view/api_keys_screen.dart';
import 'package:revoked_app/features/templates/view/templates_screen.dart';
import 'package:revoked_app/features/requests/view/inbox_screen.dart';
import 'package:revoked_app/features/requests/view/public_request_screen.dart';
import 'package:revoked_app/features/data/view/data_screen.dart';
import 'package:revoked_app/features/requests/view/request_sheet_screen.dart';
import 'package:revoked_app/features/invites/view/invite_accept_screen.dart';
import 'package:revoked_app/features/onboarding/view/workspace_onboarding_screen.dart';

abstract class AppRoutes {
  static const login = '/login';
  static const register = '/register';
  static const vault = '/vault';
  static const inbox = '/inbox';
  static const data = '/data';
  static const requestData = '/request-data';
  static const requestSheet = '/request-sheet';
  static const shares = '/shares';
  static const settings = '/settings';
  static const apiKeys = '/settings/api-keys';
  static const templates = '/settings/templates';
  static const share = '/share/:slug';
  static const request = '/request/:slug';
  // Short, canonical public paths (the deep links generate these).
  static const shortShare = '/s/:slug';
  static const shortRequest = '/r/:slug';
  static const invite = '/i/:token';
  static const onboarding = '/onboarding';

  /// Shown while the stored session is being checked.
  static const splash = '/splash';

  // Legacy aliases — kept so any deep-links or bookmarks still resolve
  static const requests = '/requests';
  static const connections = '/connections';
  static const receivedVault = '/received-vault';
}

class AppRouter {
  AppRouter._();

  /// Where the app was headed when it was sent to the splash. A deep link
  /// arrives on the first frame, before the stored session has been checked,
  /// so the destination has to survive that wait.
  static String? _pendingLocation;

  static GoRouter create(AuthStore authStore) {
    return GoRouter(
      initialLocation: AppRoutes.vault,
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
          return authStore.isAuthenticated ? AppRoutes.vault : AppRoutes.login;
        }

        final isLoggedIn = authStore.isAuthenticated;
        final isAuthRoute =
            state.matchedLocation == AppRoutes.login ||
            state.matchedLocation == AppRoutes.register;

        if (!isLoggedIn && !isAuthRoute && !isPublicRoute) {
          return AppRoutes.login;
        }

        // An account has no workspace until it creates or joins one, and every
        // other screen is scoped to a workspace, so onboarding comes first.
        final needsWorkspace =
            isLoggedIn && (authStore.activeWorkspace ?? '').isEmpty;
        final onOnboarding = state.matchedLocation == AppRoutes.onboarding;
        if (needsWorkspace && !onOnboarding && !isPublicRoute) {
          return AppRoutes.onboarding;
        }
        if (!needsWorkspace && onOnboarding) return AppRoutes.vault;

        if (isLoggedIn && isAuthRoute) return AppRoutes.vault;
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
          path: AppRoutes.register,
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: AppRoutes.share,
          builder: (context, state) {
            final slug = state.pathParameters['slug'] ?? '';
            return PublicShareScreen(shareSlug: slug);
          },
        ),
        GoRoute(
          path: AppRoutes.request,
          builder: (context, state) {
            final slug = state.pathParameters['slug'] ?? '';
            return PublicRequestScreen(requestSlug: slug);
          },
        ),
        // Short canonical aliases.
        GoRoute(
          path: AppRoutes.shortShare,
          builder: (context, state) =>
              PublicShareScreen(shareSlug: state.pathParameters['slug'] ?? ''),
        ),
        GoRoute(
          path: AppRoutes.shortRequest,
          builder: (context, state) => PublicRequestScreen(
            requestSlug: state.pathParameters['slug'] ?? '',
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
          builder: (context, state) =>
              InviteAcceptScreen(token: state.pathParameters['token'] ?? ''),
        ),
        // Fallbacks for public URLs missing slugs
        GoRoute(
          path: '/request',
          redirect: (context, state) => AppRoutes.inbox,
        ),
        GoRoute(path: '/share', redirect: (context, state) => AppRoutes.shares),
        // Legacy route redirects
        GoRoute(
          path: AppRoutes.requests,
          redirect: (context, state) => AppRoutes.inbox,
        ),
        GoRoute(
          path: AppRoutes.connections,
          redirect: (context, state) => AppRoutes.inbox,
        ),
        GoRoute(
          path: AppRoutes.receivedVault,
          redirect: (context, state) => AppRoutes.inbox,
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
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
            ),
            GoRoute(
              path: AppRoutes.inbox,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: InboxScreen()),
            ),
            // Legacy /inbox/create — old full-screen flow replaced by a
            // multi-step bottom sheet opened from the Inbox header.
            GoRoute(path: '/inbox/create', redirect: (_, _) => AppRoutes.inbox),
            // Share — your outbound links (manual + request-born). /shares is
            // kept below as a legacy alias.
            GoRoute(
              path: AppRoutes.data,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SharesScreen()),
            ),
            // Per-request shipped data, opened from the Inbox "View data" button.
            GoRoute(
              path: AppRoutes.requestData,
              pageBuilder: (context, state) {
                final requestId = state.uri.queryParameters['requestId'];
                return NoTransitionPage(
                  child: DataScreen(requestId: requestId),
                );
              },
            ),
            // Spreadsheet view of one request's responses (one row per
            // responder), opened from the Inbox.
            GoRoute(
              path: AppRoutes.requestSheet,
              pageBuilder: (context, state) {
                final requestId = state.uri.queryParameters['requestId'] ?? '';
                return NoTransitionPage(
                  child: RequestSheetScreen(requestId: requestId),
                );
              },
            ),
            GoRoute(
              path: AppRoutes.shares,
              pageBuilder: (context, state) {
                final filterSlug = state.uri.queryParameters['filterSlug'];
                return NoTransitionPage(
                  child: SharesScreen(filterSlug: filterSlug),
                );
              },
            ),
            GoRoute(
              path: AppRoutes.settings,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SettingsScreen()),
              routes: [
                GoRoute(
                  path: 'api-keys',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: ApiKeysScreen()),
                ),
                GoRoute(
                  path: 'templates',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: TemplatesScreen()),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Re-runs the router's [GoRouter.redirect] whenever auth state flips, without
/// recreating the router — so a single stable router instance can also drive
/// deep-link navigation.
class _AuthRefreshNotifier extends ChangeNotifier {
  late final ReactionDisposer _disposer;

  _AuthRefreshNotifier(AuthStore store) {
    _disposer = reaction(
      (_) => store.isAuthenticated,
      (_) => notifyListeners(),
    );
  }

  @override
  void dispose() {
    _disposer();
    super.dispose();
  }
}
