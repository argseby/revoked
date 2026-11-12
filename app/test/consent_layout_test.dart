import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_consent_layout.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/features/connections/view/sign_in_picker.dart';
import 'package:revoked_app/features/connections/view/tool_permissions.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget child, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 1040.0]) {
    testWidgets('choices and context have distinct positions at width $width', (
      tester,
    ) async {
      await show(
        tester,
        const AppConsentLayout(
          requester: Text('Requester'),
          decisions: [Text('Decision')],
          information: [Text('Information')],
        ),
        Size(width, 800),
      );
      final choice = tester.getTopLeft(find.text('Decision'));
      final info = tester.getTopLeft(find.text('Information'));
      final requester = tester.getTopLeft(find.text('Requester'));
      if (width > 880) {
        expect(info.dx, greaterThan(choice.dx + width / 2));
        expect(requester.dy, choice.dy);
      } else {
        expect(requester.dy, lessThan(choice.dy));
        expect(info.dy, greaterThan(choice.dy));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'two permissions remain two compact choices with reasons on demand',
    (tester) async {
      await show(
        tester,
        ToolPermissions(
          name: 'Showdown',
          requester: const AppConsentRequester(address: 'showdown.example'),
          allowRevoke: true,
          allowHandOver: true,
          onAllowRevoke: (_) {},
          onAllowHandOver: (_) {},
          reasons: const ToolReasons(links: 'To put the link on your profile.'),
        ),
        const Size(1040, 800),
      );
      expect(find.byType(AppSwitch), findsNWidgets(2));
      expect(find.text('What this allows'), findsNothing);
      expect(find.text('“To put the link on your profile.”'), findsNothing);
      expect(
        tester.getBottomRight(find.text('Turn off its links and requests')).dy,
        lessThan(300),
      );
      await tester.tap(find.text('Why Showdown asks'));
      await tester.pumpAndSettle();
      expect(find.text('“To put the link on your profile.”'), findsOneWidget);
    },
  );

  testWidgets(
    'sign-in previews the choice before offering alternatives and a new field',
    (tester) async {
      final draft = ObservableTextController();
      addTearDown(draft.dispose);
      String? picked;
      const choices = [
        SignInChoice(id: 'r1', value: 'Hunt: Showdown', title: 'Now playing'),
        SignInChoice(id: 'r2', value: 'Chess', title: 'Other game'),
      ];
      await show(
        tester,
        SignInPicker(
          heading: 'Share your game',
          preview: 'Shown to Showdown',
          nothing: 'Nothing',
          newHint: 'New value',
          askedKey: 'game',
          allFit: true,
          selected: 'r1',
          choices: choices,
          draft: draft,
          busy: false,
          onChanged: (id) => picked = id,
          onSwitchWorkspace: (_) {},
          browse: () => const SignInBrowseData(
            choices: choices,
            sections: [],
            selected: 'r1',
            busy: false,
          ),
        ),
        const Size(400, 800),
      );
      expect(find.text('Hunt: Showdown'), findsOneWidget);
      expect(find.text('Chess'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Choose or add an entry'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.text('Chess'));
      expect(picked, 'r2');
    },
  );
}
