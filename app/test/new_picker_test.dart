import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/utils/shell_shortcuts.dart';
import 'package:revoked_app/features/shell/utils/new_actions.dart';
import 'package:revoked_app/features/shell/view/new_picker.dart';

/// One "New" button replaced a create button per tab plus a second button for
/// opening links. The picker has to offer all of it, start where the person
/// is, and answer the keyboard; the shell's own keys must never take a letter
/// typed into a field.
void main() {
  test('starts on the row that fits the destination', () {
    expect(NewKind.firstFor(0), NewKind.record);
    expect(NewKind.firstFor(1), NewKind.record);
    expect(NewKind.firstFor(2), NewKind.link);
    expect(NewKind.firstFor(3), NewKind.request);
    expect(NewKind.firstFor(null), NewKind.record);
  });

  test('every row has its own key', () {
    final keys = NewKind.values.map((k) => k.key).toSet();
    expect(keys, hasLength(NewKind.values.length));
    // N opens the picker itself and / opens search, so no row may take them.
    expect(keys, isNot(contains('n')));
    expect(keys, isNot(contains('/')));
  });

  Future<List<NewKind>> pumpPicker(WidgetTester tester, NewKind first) async {
    final picked = <NewKind>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NewPickerList(first: first, onPick: picked.add),
        ),
      ),
    );
    await tester.pump();
    return picked;
  }

  testWidgets('lists every kind under its group', (tester) async {
    await pumpPicker(tester, NewKind.record);
    for (final group in NewGroup.values) {
      expect(find.text(group.title), findsOneWidget);
    }
    for (final kind in NewKind.values) {
      expect(find.text(kind.label), findsOneWidget);
      expect(find.text(kind.description), findsOneWidget);
    }
  });

  testWidgets('a row\'s letter picks it', (tester) async {
    final picked = await pumpPicker(tester, NewKind.record);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    expect(picked, [NewKind.link]);
  });

  testWidgets('Enter picks the row it started on', (tester) async {
    final picked = await pumpPicker(tester, NewKind.request);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(picked, [NewKind.request]);
  });

  testWidgets('a tap picks the row', (tester) async {
    final picked = await pumpPicker(tester, NewKind.record);
    await tester.tap(find.text('Section'));
    expect(picked, [NewKind.section]);
  });

  group('shell keys', () {
    Future<List<String>> pumpShortcuts(
      WidgetTester tester, {
      bool enabled = true,
    }) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ShellShortcuts(
            enabled: () => enabled,
            onSearch: () => calls.add('search'),
            onNew: () => calls.add('new'),
            onDestination: (i) => calls.add('go $i'),
            child: const Scaffold(
              body: Column(
                children: [
                  Focus(autofocus: true, child: SizedBox()),
                  TextField(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return calls;
    }

    testWidgets('act while no field has focus', (tester) async {
      final calls = await pumpShortcuts(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(calls, ['new', 'search', 'go 2']);
    });

    testWidgets('leave a focused field its letters', (tester) async {
      final calls = await pumpShortcuts(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      expect(calls, isEmpty);
    });

    testWidgets('do nothing while the shell is not in front', (tester) async {
      final calls = await pumpShortcuts(tester, enabled: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      expect(calls, isEmpty);
    });
  });
}
