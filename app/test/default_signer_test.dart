import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/identity.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Forms that sign — requests, shares, asks — preselect an identity. It has
/// to be one that can sign on this device, or the form starts on a choice
/// the picker itself refuses.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Identity id(
    String name, {
    bool primary = false,
    String status = 'active',
    String domain = 'example.com',
  }) => Identity(
    id: name,
    name: name,
    certificate: 'cert',
    fingerprint: 'f' * 64,
    user: 'u',
    workspace: 'w',
    isPrimary: primary,
    status: status,
    domainAtIssue: domain,
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Stores.init();
  });

  void given(List<Identity> ids, Set<String> local) {
    Stores.identities.identities
      ..clear()
      ..addAll(ids);
    Stores.identities.localKeyIds
      ..clear()
      ..addAll(local);
  }

  test('the primary identity when its key is here', () {
    given([id('a'), id('b', primary: true)], {'a', 'b'});
    expect(Stores.identities.defaultSigner()?.id, 'b');
  });

  test('the first that can sign when the primary key is elsewhere', () {
    given([id('a', primary: true), id('b'), id('c')], {'b', 'c'});
    expect(Stores.identities.defaultSigner()?.id, 'b');
    expect(Stores.identities.canSign('a'), isFalse);
    expect(Stores.identities.canSign('b'), isTrue);
  });

  test('a revoked identity is never the default', () {
    given([id('a', status: 'revoked'), id('b')], {'a', 'b'});
    expect(Stores.identities.defaultSigner()?.id, 'b');
    expect(Stores.identities.canSign('a'), isFalse);
  });

  test('none when no identity can sign here', () {
    given([id('a', primary: true), id('b')], {});
    expect(Stores.identities.defaultSigner(), isNull);
  });

  test('a filter narrows the candidates', () {
    given(
      [id('a', primary: true), id('b', domain: 'root.example')],
      {'a', 'b'},
    );
    expect(
      Stores.identities
          .defaultSigner(where: (i) => i.domainAtIssue == 'root.example')
          ?.id,
      'b',
    );
  });
}
