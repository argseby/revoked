import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:revoked_app/core/widgets/qr_sheet.dart';
import 'package:revoked_app/features/shell/store/link_search_store.dart';

/// The QR pair: showing a link as a code another device scans, and the
/// scanned side landing in the open-link drawer through the store.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the sheet renders the code and copies the link', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });

    const link = 'revoked://s/api.revoked.link/abc123';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showQrSheet(
                context: context,
                title: 'Share link',
                link: link,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text(link), findsOneWidget);

    await tester.tap(find.text('Copy link'));
    expect(copied, link);
  });

  test('a scanned code lands in the drawer without the clipboard notice', () {
    final store = LinkSearchStore();

    expect(store.adoptLink('revoked://r/api.revoked.link/xyz'), isTrue);
    expect(store.controller.text, 'r/api.revoked.link/xyz');
    expect(
      store.fromClipboard,
      isFalse,
      reason: 'the scan is not a clipboard adoption; that notice would lie',
    );

    expect(store.adoptLink('https://not-a-revoked-link.example'), isFalse);
    expect(store.controller.text, 'r/api.revoked.link/xyz');
  });
}
