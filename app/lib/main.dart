import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/services/deep_link_service.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/utils/deep_links.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Stores.init();
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
    final location = DeepLinks.locationFor(uri);
    if (location != null) _router.go(location);
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
      ),
    );
  }
}
