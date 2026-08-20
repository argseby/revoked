import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/features/shell/store/link_search_store.dart';

/// Opening the drawer reads the clipboard once: a revoked:// link there
/// replaces the drawer's stale text and says so. Anything else on the
/// clipboard is none of our business and must change nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? clip;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': clip};
          return null;
        });
  });

  test(
    'a revoked link on the clipboard replaces stale text, with notice',
    () async {
      final store = LinkSearchStore();
      store.controller.text = 's/old-server.example/stale';
      clip = 'revoked://r/api.revoked.link/fresh123';

      await store.adoptClipboardLink();

      expect(store.controller.text, 'r/api.revoked.link/fresh123');
      expect(store.fromClipboard, isTrue);
    },
  );

  test('arbitrary clipboard text changes nothing', () async {
    final store = LinkSearchStore();
    store.controller.text = 's/keep-me';
    clip = 'https://example.com/not-a-revoked-link';

    await store.adoptClipboardLink();

    expect(store.controller.text, 's/keep-me');
    expect(store.fromClipboard, isFalse);
  });

  test('an empty clipboard changes nothing', () async {
    final store = LinkSearchStore();
    store.controller.text = 's/keep-me';
    clip = null;

    await store.adoptClipboardLink();

    expect(store.controller.text, 's/keep-me');
    expect(store.fromClipboard, isFalse);
  });

  test('the same link already in the field raises no notice', () async {
    final store = LinkSearchStore();
    store.controller.text = 'r/api.revoked.link/fresh123';
    clip = 'revoked://r/api.revoked.link/fresh123';

    final adoption = await store.adoptClipboardLink();

    // The other entry point already adopted it; a second toast would lie.
    expect(adoption, ClipboardAdoption.alreadyPresent);
    expect(store.fromClipboard, isFalse);
  });

  test('editing the adopted text withdraws the notice', () async {
    final store = LinkSearchStore();
    clip = 'revoked://s/api.revoked.link/abc';
    await store.adoptClipboardLink();
    expect(store.fromClipboard, isTrue);

    store.controller.text = 's/api.revoked.link/abc-edited';

    expect(store.fromClipboard, isFalse);
  });

  test('an adopted link invalidates a previous verdict', () async {
    // The verdict on screen must always describe the text in the field.
    final store = LinkSearchStore();
    store.controller.text = 's/api.revoked.link/verified-one';
    store.startVerifying();
    store.failVerifying(Exception('x'));
    expect(store.verifyError, isNotNull);

    clip = 'revoked://s/api.revoked.link/other';
    await store.adoptClipboardLink();

    expect(store.verifyError, isNull);
    expect(store.verdict, isNull);
  });
}
