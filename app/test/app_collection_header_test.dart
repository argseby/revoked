import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_collection_header.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'));
    await font.load();
  });

  Future<void> pumpHeader(
    WidgetTester tester, {
    required double width,
    String title = 'Your sharing',
    String action = 'New link',
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: AppTabs(
            tabs: [
              AppTab(
                label: 'Sent',
                icon: Icons.send,
                description: 'Links you shared with others.',
                view: AppPageBody(
                  children: [
                    AppCollectionHeader(
                      title: title,
                      description: 'Manage the information you share.',
                      action: AppButton(
                        label: action,
                        icon: Icons.add,
                        onTap: () {},
                      ),
                    ),
                    const Text('List content'),
                  ],
                ),
              ),
              const AppTab(
                label: 'Received',
                icon: Icons.bookmark,
                description: 'Items others shared with you.',
                view: SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 375.0, 1200.0]) {
    testWidgets('sharing title and action share a row at $width', (
      tester,
    ) async {
      await pumpHeader(tester, width: width);
      final title = tester.getRect(find.text('Your sharing'));
      final action = tester.getRect(find.byType(AppButton));
      expect(title.center.dy, closeTo(action.center.dy, 1));
      expect(title.right, lessThan(action.left));
      final tabsBottom = tester.getRect(find.byType(InkWell).first).bottom;
      final headerTop = tester.getRect(find.byType(AppCollectionHeader)).top;
      expect(headerTop - tabsBottom, 12);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (title, action) in [
    ('Your requests', 'New request'),
    ('Your vault', 'New record'),
    ('Your contacts', 'New contact'),
    ('Shared with you', 'Open a link'),
  ]) {
    testWidgets('$title keeps its action beside the title on a phone', (
      tester,
    ) async {
      await pumpHeader(tester, width: 375, title: title, action: action);
      expect(
        tester.getRect(find.text(title)).center.dy,
        closeTo(tester.getRect(find.byType(AppButton)).center.dy, 1),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('enlarged text can move the action below the title', (
    tester,
  ) async {
    await pumpHeader(tester, width: 320, textScale: 2);
    expect(
      tester.getRect(find.byType(AppButton)).top,
      greaterThan(tester.getRect(find.text('Your sharing')).bottom),
    );
    expect(find.text('New link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
