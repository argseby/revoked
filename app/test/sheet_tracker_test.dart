import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/state/sheet_tracker.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';

/// The shell hides its floating buttons while a sheet is open. A sheet opened
/// inside the tabs is thrown away with the tabs' navigator when the app opens
/// a full-screen page — a share link, a request — without ever completing,
/// and counting only completions left the buttons hidden until a restart.
void main() {
  late BuildContext pageContext;

  GoRouter router() => GoRouter(
    initialLocation: '/a',
    routes: [
      GoRoute(
        path: '/a',
        builder: (context, _) {
          pageContext = context;
          return const Scaffold(body: Text('A'));
        },
      ),
      GoRoute(
        path: '/b',
        builder: (_, _) => const Scaffold(body: Text('B')),
      ),
    ],
  );

  testWidgets('a popped sheet is no longer counted', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
    showAppSheet(context: pageContext, builder: (_) => const Text('sheet'));
    await tester.pumpAndSettle();
    expect(SheetTracker.anyOpen, isTrue);

    Navigator.of(pageContext).pop();
    await tester.pumpAndSettle();
    expect(SheetTracker.anyOpen, isFalse);
  });

  testWidgets('a sheet the app navigated away from is no longer counted', (
    tester,
  ) async {
    final r = router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    showAppSheet(context: pageContext, builder: (_) => const Text('sheet'));
    await tester.pumpAndSettle();
    expect(SheetTracker.anyOpen, isTrue);

    // Replaces page A, and the sheet above it goes with it.
    r.go('/b');
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
    expect(SheetTracker.anyOpen, isFalse);
  });

  testWidgets('a sheet opened inside the tabs is released when the tabs go', (
    tester,
  ) async {
    late BuildContext tabContext;
    final r = GoRouter(
      initialLocation: '/vault',
      routes: [
        ShellRoute(
          builder: (_, _, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/vault',
              builder: (context, _) {
                tabContext = context;
                return const Text('Vault');
              },
            ),
          ],
        ),
        // A full-screen page outside the tabs, like an opened share link.
        GoRoute(
          path: '/s/:slug',
          builder: (_, _) => const Scaffold(body: Text('Share')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    showAppSheet(context: tabContext, builder: (_) => const Text('sheet'));
    await tester.pumpAndSettle();
    expect(SheetTracker.anyOpen, isTrue);

    r.go('/s/abc');
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsOneWidget);
    expect(SheetTracker.anyOpen, isFalse);
  });
}
