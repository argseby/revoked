import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/utils/paste_link_shortcut.dart';

/// Ctrl+V with no field focused opens the link drawer; Ctrl+V inside a text
/// field must stay an ordinary paste. The second half is the dangerous one:
/// a global shortcut that swallows paste in inputs breaks every form at once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pressCtrlV(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('fires when nothing editable has focus', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PasteLinkShortcut(
          onTrigger: () async => fired++,
          // Key events route along the focus path, so something
          // non-editable must genuinely hold focus.
          child: const Scaffold(
            body: Focus(autofocus: true, child: Text('idle')),
          ),
        ),
      ),
    );
    await tester.pump();

    await pressCtrlV(tester);

    expect(fired, 1);
  });

  testWidgets('a focused text field keeps its own paste', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return {'text': 'pasted-into-field'};
          }
          if (call.method == 'Clipboard.hasStrings') return {'value': true};
          return null;
        });

    var fired = 0;
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: PasteLinkShortcut(
          onTrigger: () async => fired++,
          child: Scaffold(body: TextField(controller: controller)),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await pressCtrlV(tester);
    await tester.pumpAndSettle();

    expect(fired, 0, reason: 'the shortcut must not steal paste from inputs');
    expect(
      controller.text,
      'pasted-into-field',
      reason: 'the field must receive the ordinary paste',
    );
  });
}
