import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/private_address.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A webhook at this machine or a private network gets nothing from a server
/// that doesn't deliver there, so the app says so while the address is typed.
void main() {
  test('local and private addresses are recognised', () {
    for (final url in [
      'http://127.0.0.1:47381/',
      'http://localhost:8000/hook',
      'http://api.localhost/',
      'http://10.0.0.5/',
      'http://192.168.1.20/hook',
      'http://172.20.0.3/',
      'http://printer.local/',
      'http://svc.internal/',
      'http://[::1]:8000/',
      'http://[fd12::1]/',
    ]) {
      expect(isPrivateAddress(url), isTrue, reason: url);
    }
    for (final url in [
      'https://example.com/hooks/revoked',
      'http://172.32.0.1/',
      'http://8.8.8.8/',
      'not a url',
      '',
    ]) {
      expect(isPrivateAddress(url), isFalse, reason: url);
    }
  });

  test(
    'the store warns only while the server refuses private addresses',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await Stores.init();
      final store = Stores.webhooks;
      store.draftUrl.text = 'http://127.0.0.1:47381/';
      expect(store.draftUnreachable, isFalse);
      runInAction(() => store.privateCallbacks = false);
      expect(store.draftUnreachable, isTrue);
      store.draftUrl.text = 'https://example.com/hook';
      expect(store.draftUnreachable, isFalse);
    },
  );
}
