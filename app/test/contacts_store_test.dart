import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/contact.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/contacts/store/contacts_store.dart';

/// Whether a contact is proven is the server's to say. These check that the
/// app never claims it, and that it tells the three kinds of contact apart —
/// which is what decides whether a send can reach them in the app at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final posted = <Map<String, dynamic>>[];
  final patched = <Map<String, dynamic>>[];
  final deleted = <String>[];
  final handed = <Map<String, dynamic>>[];
  var listed = <Map<String, dynamic>>[];
  var delivers = true;
  var refuse = false;
  String? mailPolicy;
  var signupsOpen = true;
  var emails = false;

  Future<http.Response> server(http.Request request) async {
    final path = request.url.path;
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

    if (path.startsWith('/api/contacts/')) {
      final parts = path.split('/');
      final action = parts.last;
      handed.add({
        'contact': parts[parts.length - 2],
        'action': action,
        ...jsonDecode(request.body) as Map<String, dynamic>,
      });
      if (refuse) {
        return json({
          'code': 'template_not_owned',
          'message': 'The selected form does not belong to your workspace.',
        }, 403);
      }
      return json({
        'ok': true,
        'id': 'g1',
        'slug': action == 'ask' ? 'r-slug' : 's-slug',
        'kind': action == 'ask' ? 'request' : 'share',
        'delivered': delivers,
        'emailed': emails,
        // What the server sends for a contact it will name a channel for;
        // an unconfirmed one gets 'handed_over' and both flags false.
        'channel': delivers
            ? 'account'
            : emails
            ? 'email'
            : 'manual',
      });
    }
    if (path.startsWith('/api/collections/contacts/records/')) {
      final id = path.split('/').last;
      if (request.method == 'DELETE') {
        deleted.add(id);
        return http.Response('', 204);
      }
      if (request.method == 'GET') {
        return json({
          'id': id,
          'name': 'Ada',
          'email': 'ada@home.test',
          'user': delivers ? 'u2' : '',
          'lastUsedAt': '2026-10-31T12:00:00Z',
        });
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      patched.add(body);
      return json({'id': id, 'name': body['name'], 'email': 'ada@home.test'});
    }
    if (path == '/api/server') {
      return json({
        'domain': 'test.invalid',
        'signups': {'open': signupsOpen},
        if (mailPolicy != null) 'mail': {'recipients': mailPolicy},
      });
    }
    if (path == '/api/collections/contacts/records') {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        posted.add(body);
        return json({
          'id': 'c9',
          'workspace': 'w1',
          ...body,
          'trustState': 'unverified',
        });
      }
      return json({'items': listed});
    }
    return json({'items': <Object>[]});
  }

  // Built per case; a store outliving the zone it was first used in runs every
  // later async action in a dead one.
  setUp(() async {
    posted.clear();
    patched.clear();
    deleted.clear();
    handed.clear();
    listed = <Map<String, dynamic>>[];
    delivers = true;
    refuse = false;
    mailPolicy = null;
    signupsOpen = true;
    emails = false;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server));
    await Stores.api.saveAuthState('session-token', {
      'id': 'u1',
      'activeWorkspace': 'w1',
    });
  });

  ContactsStore store() => Stores.contacts;

  test('the three kinds of contact are told apart', () {
    final here = Contact.fromJson({
      'id': 'c1',
      'name': 'Ada',
      'user': 'u2',
      'email': 'ada@home.test',
      'trustState': 'verified',
    });
    final peer = Contact.fromJson({
      'id': 'c2',
      'name': 'Grace',
      'peerDomain': 'peer.test',
      'trustState': 'verified',
    });
    final byMail = Contact.fromJson({
      'id': 'c3',
      'name': 'Mia',
      'email': 'mia@example.com',
    });

    expect(here.isHere, isTrue);
    expect(here.isPeer, isFalse);
    expect(peer.isPeer, isTrue);
    expect(peer.isHere, isFalse);
    expect(byMail.isEmailOnly, isTrue);
    // Only an account on this server can be reached in the app.
    expect(peer.isHere || byMail.isHere, isFalse);
  });

  test('an unknown trust state reads as unverified, not as proven', () {
    expect(
      Contact.fromJson({'id': 'c1', 'name': 'X', 'email': 'x@y.test'}).trust,
      ContactTrust.unverified,
    );
    expect(
      Contact.fromJson({
        'id': 'c1',
        'name': 'X',
        'email': 'x@y.test',
        'trustState': 'something-new',
      }).trust,
      ContactTrust.unverified,
    );
  });

  test('a contact reaching nobody cannot be saved', () async {
    store().name.text = 'Nobody';
    expect(store().canSave, isFalse);
    expect(await store().create(workspace: 'w1'), isFalse);
    expect(posted, isEmpty, reason: 'nothing is sent that would be refused');

    store().email.text = 'someone@example.com';
    expect(store().canSave, isTrue);
  });

  test('creating one never claims it is verified', () async {
    store().name.text = 'Grace Hopper';
    store().peerDomain.text = 'peer.test';
    expect(await store().create(workspace: 'w1'), isTrue);

    expect(posted.single.containsKey('trustState'), isFalse);
    expect(posted.single.containsKey('verifiedAt'), isFalse);
    expect(posted.single.containsKey('peerFingerprint'), isFalse);
    expect(posted.single['peerDomain'], 'peer.test');
    expect(store().contacts.single.trust, ContactTrust.unverified);
    // The form is left empty, so the next one does not inherit this one.
    expect(store().canSave, isFalse);
  });

  test('renaming one keeps the list in step, and removing drops it', () async {
    listed = [
      {'id': 'c1', 'name': 'Ada', 'user': 'u2', 'trustState': 'verified'},
      {'id': 'c2', 'name': 'Grace', 'peerDomain': 'peer.test'},
    ];
    await store().load();

    store().startRename('c1');
    store().renameName.text = '  Ada Lovelace  ';
    expect(await store().rename('c1'), isTrue);
    expect(patched.single['name'], 'Ada Lovelace');
    expect(store().byId('c1')!.name, 'Ada Lovelace');

    expect(await store().remove('c2'), isTrue);
    expect(deleted, ['c2']);
    expect(store().contacts.map((c) => c.id), ['c1']);
  });

  test(
    'the ones already known to receive in the app are singled out',
    () async {
      listed = [
        {'id': 'c1', 'name': 'Ada', 'user': 'u2', 'trustState': 'verified'},
        {'id': 'c2', 'name': 'Grace', 'peerDomain': 'peer.test'},
        {'id': 'c3', 'name': 'Mia', 'email': 'mia@example.com'},
      ];
      await store().load();

      expect(store().contacts, hasLength(3));
      expect(store().knownHere.map((c) => c.id), ['c1']);
    },
  );

  test('sending hands over entry ids and keeps the owned side here', () async {
    listed = [
      {'id': 'c1', 'name': 'Ada', 'email': 'ada@home.test'},
    ];
    await store().load();

    store().startGrant('c1');
    store().grantLabel.text = '  My bank details  ';
    store().toggleDraftRecord('r1');
    store().toggleDraftRecord('r2');
    store().toggleDraftSection('s1');
    final grant = await store().submitSend();

    expect(grant, isNotNull);
    expect(grant!.delivered, isTrue);
    expect(grant.isRequest, isFalse);
    expect(store().lastGrant, same(grant));
    expect(handed.single, {
      'contact': 'c1',
      'action': 'send',
      'records': ['r1', 'r2'],
      'sections': ['s1'],
      'label': 'My bank details',
    });
    // The server resolved the address, so the row says who it reached.
    expect(store().byId('c1')!.isHere, isTrue);
  });

  test('a grant nobody here could receive still comes back', () async {
    delivers = false;
    listed = [
      {'id': 'c1', 'name': 'Ada', 'email': 'ada@elsewhere.test'},
    ];
    await store().load();

    store().startGrant('c1');
    store().grantLabel.text = 'My number';
    store().toggleDraftRecord('r1');
    final grant = await store().submitSend();

    expect(grant!.delivered, isFalse);
    expect(grant.slug, 's-slug');
    expect(store().byId('c1')!.isHere, isFalse);
    expect(
      store().error,
      isNull,
      reason: 'the grant exists; it just has to be passed on',
    );
  });

  test('asking carries the name they are meant to trust', () async {
    store().startGrant('c1', identityId: 'i1');
    store().grantLabel.text = 'Your new address';
    store().setAskTemplate('t1');
    final grant = await store().submitAsk();

    expect(grant!.isRequest, isTrue);
    expect(handed.single, {
      'contact': 'c1',
      'action': 'ask',
      'label': 'Your new address',
      'identity': 'i1',
      'template': 't1',
    });
  });

  test(
    'an ask without a form leaves it out rather than sending empty',
    () async {
      store().startGrant('c1', identityId: 'i1');
      store().grantLabel.text = 'Anything';
      await store().submitAsk();

      expect(handed.single.containsKey('template'), isFalse);
    },
  );

  test('a form with nothing picked, or no name, hands nothing over', () async {
    store().startGrant('c1');
    expect(store().canSend, isFalse);
    expect(await store().submitSend(), isNull);

    store().grantLabel.text = 'Named but empty';
    expect(store().canSend, isFalse);

    store().toggleDraftRecord('r1');
    expect(store().canSend, isTrue);

    // An ask needs the identity it is signed with, not vault entries.
    expect(store().canAsk, isFalse);
    store().setAskIdentity('i1');
    expect(store().canAsk, isTrue);

    expect(handed, isEmpty);
  });

  test(
    'a server that says nothing about mail is treated as sending none',
    () async {
      listed = [
        {'id': 'c1', 'name': 'Ada', 'email': 'ada@elsewhere.test'},
      ];
      await store().load();

      expect(store().mailRecipients, isNull);
      expect(
        store().emailReason(store().byId('c1')!, isAsk: false),
        isNotNull,
        reason: 'an old server cannot promise to mail, so assume it will not',
      );
    },
  );

  test('the policy decides which addresses an email will reach', () async {
    mailPolicy = 'same-domain';
    listed = [
      {'id': 'c1', 'name': 'Inside', 'email': 'a@test.invalid'},
      {'id': 'c2', 'name': 'Outside', 'email': 'b@elsewhere.test'},
      {'id': 'c3', 'name': 'Here', 'user': 'u2', 'email': 'c@test.invalid'},
      {'id': 'c4', 'name': 'Peer', 'peerDomain': 'peer.test'},
    ];
    await store().load();

    expect(store().mailRecipients, 'same-domain');
    expect(store().emailReason(store().byId('c1')!, isAsk: false), isNull);
    expect(store().emailReason(store().byId('c2')!, isAsk: false), isNotNull);
    // Someone with an account here is reached in the app, not by email.
    expect(store().emailReason(store().byId('c3')!, isAsk: false), isNull);
    // A peer-only contact has no address to mail.
    expect(store().emailReason(store().byId('c4')!, isAsk: false), isNotNull);
  });

  test('an ask cannot be emailed where nobody can make an account', () async {
    mailPolicy = 'all';
    signupsOpen = false;
    listed = [
      {'id': 'c1', 'name': 'Ada', 'email': 'ada@elsewhere.test'},
    ];
    await store().load();

    final ada = store().byId('c1')!;
    expect(store().emailReason(ada, isAsk: false), isNull);
    expect(
      store().emailReason(ada, isAsk: true),
      isNotNull,
      reason: 'answering needs an account, so the email would dead-end',
    );
  });

  test('an emailed grant says so, and is not called delivered', () async {
    delivers = false;
    emails = true;
    listed = [
      {'id': 'c1', 'name': 'Ada', 'email': 'ada@elsewhere.test'},
    ];
    await store().load();

    store().startGrant('c1');
    store().grantLabel.text = 'My number';
    store().toggleDraftRecord('r1');
    final grant = await store().submitSend();

    expect(grant!.emailed, isTrue);
    expect(grant.delivered, isFalse);
  });

  test('a refusal is shown and nothing is claimed to have gone out', () async {
    refuse = true;
    store().startGrant('c1', identityId: 'i1');
    store().grantLabel.text = 'Your address';
    final grant = await store().submitAsk();

    expect(grant, isNull);
    expect(store().lastGrant, isNull);
    expect(store().error?.code, 'template_not_owned');
    expect(store().error?.title, 'Template not found');
  });
}
