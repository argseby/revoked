import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';

/// A refresh can flip loading on and off several times within one fade, so
/// copies of the page and the skeleton may still be fading out when they are
/// shown again.
void main() {
  testWidgets('loading flipping repeatedly mid-fade keeps keys unique', (
    tester,
  ) async {
    final loading = Observable(false);
    final pageKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: AppLoadFade(
          loading: () => loading.value,
          skeleton: const Text('skeleton'),
          builder: (_) => Text('page', key: pageKey),
        ),
      ),
    );

    for (final value in [true, false, true, false]) {
      runInAction(() => loading.value = value);
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull, reason: 'after loading=$value');
    }
    expect(find.text('page'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('page'), findsOneWidget);
    expect(find.text('skeleton'), findsNothing);
  });
}
