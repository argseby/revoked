import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/features/onboarding/view/tour_screen.dart';

/// The tour opens on its first step with a sample ready to save, and lists
/// the steps that follow, so the whole loop is visible from the start.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Stores.init();
  });

  for (final size in const [Size(360, 800), Size(1280, 900)]) {
    testWidgets('opens on the first step at ${size.width.toInt()} wide', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: const Scaffold(body: TourScreen()),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Wi-Fi password'), findsOneWidget);
      for (final title in [
        'Something to share',
        'A link to it',
        'Opened by the recipient',
        'The value changes',
        'The link is revoked',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      final save = tester.widget<AppButton>(
        find.ancestor(
          of: find.text('Save to the vault'),
          matching: find.byType(AppButton),
        ),
      );
      expect(save.onTap, isNotNull);
    });
  }
}
