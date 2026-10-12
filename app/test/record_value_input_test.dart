import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/features/vault/view/record_value_input.dart';

/// A record's value is entered the way its type is: a yes/no is switched,
/// a date is picked, and everything else is typed. Masking is a labelled
/// switch of its own, never an eye on the field.
void main() {
  Future<ObservableTextController> pump(
    WidgetTester tester, {
    required String type,
    String value = '',
  }) async {
    final controller = ObservableTextController(text: value);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordValueField(
            type: type,
            controller: controller,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('a boolean is a switch that writes true or false', (
    tester,
  ) async {
    final controller = await pump(tester, type: 'boolean', value: 'false');
    expect(find.byType(AppSwitch), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('False'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(controller.text, 'true');
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

  testWidgets('text is typed, with no eye on the field', (tester) async {
    await pump(tester, type: 'text', value: 'secret');
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(AppIcons.eye), findsNothing);
    expect(find.byIcon(AppIcons.eyeSlash), findsNothing);
  });

  testWidgets('hiding is a labelled switch the whole row toggles', (
    tester,
  ) async {
    final changes = <bool>[];
    Future<void> show({required bool isFile}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordHiddenToggle(
            hidden: false,
            isFile: isFile,
            onChanged: changes.add,
          ),
        ),
      ),
    );

    await show(isFile: false);
    expect(find.text('Hide value'), findsOneWidget);
    expect(find.byType(AppSwitch), findsOneWidget);
    await tester.tap(find.text('Hide value'));
    expect(changes, [true]);

    await show(isFile: true);
    expect(find.text('Hide file name'), findsOneWidget);
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
