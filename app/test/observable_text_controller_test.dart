import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';

/// Stores own their controllers, so a view that gates a button on
/// `controller.text` is reading state MobX cannot see. A plain controller
/// makes that button freeze at its initial state; these tests pin the fix.
void main() {
  testWidgets('typing rebuilds an Observer that reads the text', (
    tester,
  ) async {
    final controller = ObservableTextController();
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Observer(
            builder: (_) {
              builds++;
              final canSave = controller.text.trim().isNotEmpty;
              return Column(
                children: [
                  TextField(controller: controller),
                  Text(canSave ? 'enabled' : 'disabled'),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('disabled'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    expect(find.text('enabled'), findsOneWidget);
    expect(builds, greaterThan(1));
  });

  testWidgets('moving the caret does not rebuild', (tester) async {
    final controller = ObservableTextController(text: 'hello');
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Observer(
          builder: (_) {
            builds++;
            return Text(controller.text);
          },
        ),
      ),
    );

    final settled = builds;
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    expect(builds, settled);
  });

  test('a write outside a reactive context is allowed', () {
    final controller = ObservableTextController();
    expect(() => controller.text = 'set directly', returnsNormally);
    expect(controller.text, 'set directly');
  });
}
