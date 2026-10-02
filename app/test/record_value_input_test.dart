import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/features/vault/view/record_value_input.dart';

/// A record's value is entered the way its type is: a yes/no is switched,
/// a date is picked, and everything else is typed — always with the eye that
/// masks it right behind the field.
void main() {
  Future<({ObservableTextController controller, List<bool> hidden})> pump(
    WidgetTester tester, {
    required String type,
    String value = '',
  }) async {
    final controller = ObservableTextController(text: value);
    final hidden = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordValueField(
            type: type,
            controller: controller,
            hidden: false,
            onHiddenChanged: hidden.add,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    return (controller: controller, hidden: hidden);
  }

  testWidgets('a boolean is a switch that writes true or false', (
    tester,
  ) async {
    final field = await pump(tester, type: 'boolean', value: 'false');
    expect(find.byType(AppSwitch), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('False'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(field.controller.text, 'true');
    expect(find.text('True'), findsOneWidget);
  });

  testWidgets('a datetime is picked, not typed, and reads as a date', (
    tester,
  ) async {
    await pump(tester, type: 'datetime', value: '1991-04-12T14:30');
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(AppIcons.calendar), findsOneWidget);
    expect(find.text('12 April 1991, 14:30'), findsOneWidget);
  });

  testWidgets('text is typed, with the eye behind the field', (tester) async {
    final field = await pump(tester, type: 'text', value: 'secret');
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.eye));
    expect(field.hidden, [true]);
  });

  test('picking boolean leaves only true or false behind', () {
    expect(recordValueForType('boolean', 'TRUE'), 'true');
    expect(recordValueForType('boolean', 'hello'), 'false');
    expect(recordValueForType('text', 'hello'), 'hello');
  });

  test('a plain date reads without a time', () {
    expect(recordDateTimeLabel('1991-04-12'), '12 April 1991');
    expect(recordDateTimeLabel('not a date'), 'not a date');
  });
}
