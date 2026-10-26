import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/files/file_opener.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/services/deep_link_service.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/state/display_preferences.dart';
import 'package:revoked_app/core/state/sheet_tracker.dart';
import 'package:revoked_app/core/utils/paste_link_shortcut.dart';
import 'package:revoked_app/core/utils/shell_shortcuts.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/display_scope.dart';
import 'package:revoked_app/core/widgets/window_chrome.dart';
import 'package:revoked_app/features/shell/store/link_search_store.dart';
import 'package:revoked_app/features/shell/view/link_search_sheet.dart';
import 'package:revoked_app/features/shell/view/new_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(purgeOpenedFiles());
  await Stores.init();
  await DisplayPreferences.load();
  runApp(const RevokedApp());
}

class RevokedApp extends StatefulWidget {
  const RevokedApp({super.key});

  @override
  State<RevokedApp> createState() => _RevokedAppState();
}

class _RevokedAppState extends State<RevokedApp> {
  late final GoRouter _router;
  final DeepLinkService _deepLinks = DeepLinkService();

  @override
  void initState() {
    super.initState();
    _router = AppRouter.create(Stores.auth);
    WindowTitleBar.attach();

    // Links delivered while the app is already running.
    _deepLinks.onLink(_handleDeepLink);
    // The link the app was cold-started with (handled after first frame so the
    // router is mounted).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await _deepLinks.initialLink();
      if (initial != null) _handleDeepLink(initial);
    });
  }

  void _handleDeepLink(Uri uri) {
    // The server's sign-in page sending the person back: an answer for the
    // auth store, not a place to go — the router follows the session.
    if (DeepLinks.isSignInReturn(uri)) {
      unawaited(Stores.auth.completeSignIn(uri));
      return;
    }
    final location = DeepLinks.locationFor(uri);
    if (location != null) _router.go(location);
  }

  /// Ctrl+V with no field focused: if the clipboard holds a revoked link,
  /// open the drawer already carrying it. Junk on the clipboard opens
  /// nothing - a paste that goes nowhere is better than a mystery drawer.
  Future<void> _handleGlobalPaste() async {
    final adoption = await Stores.linkSearch.adoptClipboardLink();
    if (adoption == ClipboardAdoption.none) return;
    final ctx = AppRouter.rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    if (adoption == ClipboardAdoption.adopted) {
      AppToast.success(ctx, 'Link taken from your clipboard');
    }
    await openLinkSearchSheet(ctx);
  }

  String get _path => _router.routerDelegate.currentConfiguration.uri.path;

  /// The shell's keys only act on the shell itself, signed in, with nothing
  /// open over it: no sheet, and no dialog on the root navigator.
  bool _shellIsFront() {
    if (!Stores.auth.isAuthenticated || SheetTracker.anyOpen) return false;
    if (AppRouter.rootNavigatorKey.currentState?.canPop() ?? true) {
      return false;
    }
    final path = _path;
    return AppRoutes.destinationOf(path) != null ||
        path.startsWith(AppRoutes.settings);
  }

  void _openSearch() {
    final ctx = AppRouter.rootNavigatorKey.currentContext;
    if (ctx != null) openLinkSearchSheet(ctx);
  }

  void _openNew() {
    final ctx = AppRouter.rootNavigatorKey.currentContext;
    if (ctx == null) return;
    openNewPicker(ctx, destination: AppRoutes.destinationOf(_path));
  }

  @override
  void dispose() {
    _deepLinks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) => MaterialApp.router(
        title: 'Revoked',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(Brightness.light),
        darkTheme: AppTheme.build(Brightness.dark),
        themeMode: Stores.theme.mode,
        routerConfig: _router,
        // No visible scrollbars anywhere: lists scroll by touch, wheel and
        // trackpad, and the bar only covered the content's right edge.
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          scrollbars: false,
        ),
        builder: (context, child) => DisplayScope(
          child: PasteLinkShortcut(
            onTrigger: _handleGlobalPaste,
            child: ShellShortcuts(
              enabled: _shellIsFront,
              onSearch: _openSearch,
              onNew: _openNew,
              onDestination: (i) => _router.go(AppRoutes.destinations[i]),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
