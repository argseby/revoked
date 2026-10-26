import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/design/motion.dart';
import 'package:revoked_app/core/state/display_preferences.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/attention_card.dart';
import 'package:revoked_app/core/widgets/detail_gate.dart';
import 'package:revoked_app/core/widgets/ledger_header.dart';
import 'package:revoked_app/core/widgets/redacted_value.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The pieces the redesigned screens are built from. Each carries one
/// accessibility promise: a hidden value never reaches the screen reader, a
/// status is never colour alone, a section is announced as a heading, and the
/// keyboard always shows where it is.
void main() {
  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
    theme: AppTheme.build(Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('a hidden value is a bar until shown', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(const RedactedValue('DE89370400440532013000')),
    );
    expect(find.text('DE89370400440532013000'), findsNothing);
    expect(find.bySemanticsLabel('Hidden value'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('DE89')), findsNothing);

    await tester.tap(find.byTooltip('Show value'));
    await tester.pump();
    expect(find.text('DE89370400440532013000'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide value'));
    await tester.pump();
    expect(find.text('DE89370400440532013000'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a value that must stay hidden offers no show button', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const RedactedValue('1234', revealable: false)),
    );
    expect(find.byTooltip('Show value'), findsNothing);
  });

  testWidgets('a status has an icon and a word, not just a colour', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(const StatusLabel('paused')));
    expect(find.text('Paused'), findsOneWidget);
    expect(find.byType(Icon), findsOneWidget);
    expect(find.bySemanticsLabel('Status: Paused'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a section header is announced as a heading', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(const LedgerHeader('Who can see this', count: '3')),
    );
    final node = tester.getSemantics(find.text('Who can see this'));
    expect(node.flagsCollection.isHeader, isTrue);
    expect(find.text('3'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('an attention card reads as one sentence', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        AttentionCard(
          tone: AttentionTone.warning,
          icon: Icons.schedule,
          label: 'Ends soon',
          value: '1 link',
          detail: 'Car insurer, in 3 days',
          onTap: () {},
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Ends soon: 1 link. Car insurer, in 3 days'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  group('detail gate', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('shows the expert part only at Full', (tester) async {
      await DisplayPreferences.setDetailLevel(DetailLevel.essentials);
      await tester.pumpWidget(
        host(
          const DetailGate(
            essentials: Text('Plain'),
            child: Text('example.org/s/k7m2p9'),
          ),
        ),
      );
      expect(find.text('Plain'), findsOneWidget);
      expect(find.text('example.org/s/k7m2p9'), findsNothing);

      await DisplayPreferences.setDetailLevel(DetailLevel.full);
      await tester.pump();
      expect(find.text('example.org/s/k7m2p9'), findsOneWidget);
      expect(find.text('Plain'), findsNothing);
    });

    test('the choice survives a restart', () async {
      await DisplayPreferences.setDetailLevel(DetailLevel.full);
      await DisplayPreferences.setDetailLevel(DetailLevel.essentials);
      await DisplayPreferences.setDetailLevel(DetailLevel.full);
      await DisplayPreferences.load();
      expect(DisplayPreferences.detailLevel, DetailLevel.full);
    });
  });

  testWidgets('keyboard focus draws a ring; a tap does not', (tester) async {
    BoxDecoration ring() =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(AppFocusRing),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;

    await tester.pumpWidget(
      host(
        AppFocusRing(
          child: Material(
            child: InkWell(onTap: () {}, child: const Text('Row')),
          ),
        ),
      ),
    );
    expect(ring().border, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ring().border, isNotNull);
  });

  testWidgets('a button rings on keyboard focus', (tester) async {
    await tester.pumpWidget(host(AppButton(label: 'Revoke', onTap: () {})));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    final side = button.style!.side!.resolve({WidgetState.focused});
    expect(side, isNotNull);
    expect(side!.width, 2);
    expect(button.style!.side!.resolve({}), isNull);
  });

  testWidgets('reduced motion turns animation off', (tester) async {
    late Duration normal, reduced;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            normal = AppMotion.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            reduced = AppMotion.of(context);
            return const SizedBox();
          },
        ),
        reduceMotion: true,
      ),
    );
    expect(normal, AppMotion.duration);
    expect(reduced, Duration.zero);
  });

  testWidgets('buttons are big enough to hit', (tester) async {
    await tester.pumpWidget(host(AppButton(label: 'Pause', onTap: () {})));
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(44),
    );
  });
}
