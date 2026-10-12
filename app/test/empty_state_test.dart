import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

AppEmptyState _explainer({VoidCallback? onNew}) => AppEmptyState(
  icon: AppIcons.safe,
  title: 'Records live in the vault',
  subtitle:
      'A record is one piece of data, such as an IBAN or a password. Links '
      'and requests point at it instead of copying it.',
  example: const AppEmptyExample(
    title: 'IBAN',
    detail: 'DE89 •••• •••• 3000',
    badge: 'hidden',
  ),
  steps: const [
    AppEmptyStep('Record', 'A key and a value, optionally masked'),
    AppEmptyStep('Section', 'Records grouped and shared as one'),
    AppEmptyStep('Link', 'Reads the current value and can be revoked'),
  ],
  notice: 'The vault has no records yet, so there is nothing to link to.',
  action: AppButton(icon: AppIcons.plus, label: 'New record', onTap: onNew),
  secondaryAction: AppButton(
    icon: AppIcons.fileText,
    label: 'From template',
    style: AppButtonStyle.accent,
    onTap: () {},
  ),
  learnMoreLabel: 'How the vault works',
  learnMoreUrl: 'https://docs.revoked.link/guide/vault/',
);

void main() {
  for (final size in const [Size(320, 560), Size(1280, 800)]) {
    testWidgets('an explaining empty state fits ${size.width.toInt()} wide', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var created = 0;
      await tester.pumpWidget(_host(_explainer(onNew: () => created++)));

      expect(tester.takeException(), isNull);
      expect(
        find.text('IBAN  ·  DE89 •••• •••• 3000', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('hidden'), findsOneWidget);
      for (final n in ['1', '2', '3']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.textContaining('nothing to link to'), findsOneWidget);
      expect(find.text('How the vault works'), findsOneWidget);

      await tester.ensureVisible(find.text('New record'));
      await tester.tap(find.text('New record'));
      expect(created, 1);
    });
  }

  testWidgets('without steps or an example it stays the short notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AppEmptyState(
          icon: AppIcons.linkSlash,
          title: 'Link not found',
          subtitle: 'It may have been deleted.',
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(AppEmptyExample), findsNothing);
    expect(
      tester.getCenter(find.text('Link not found')).dx,
      moreOrLessEquals(400, epsilon: 1),
    );
  });
}
