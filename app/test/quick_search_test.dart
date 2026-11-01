import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:revoked_app/core/models/contact.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/features/shell/utils/quick_search.dart';

/// The one search in the app finds things by name, across every kind. It must
/// never match a value — a hidden IBAN is not something to type half of and
/// see completed.
void main() {
  models.Record record(String id, String key, String value, {String? label}) =>
      models.Record.fromJson({
        'id': id,
        'key': key,
        'value': value,
        'label': label ?? '',
        'type': 'text',
        'format': 'hidden',
        'user': 'u1',
        'workspace': 'w1',
      });

  Link link(String id, String label, String slug) => Link.fromJson({
    'id': id,
    'label': label,
    'slug': slug,
    'status': 'active',
  });

  Section section(String id, String key, String name) => Section.fromJson({
    'id': id,
    'key': key,
    'name': name,
    'records': <String>[],
    'user': 'u1',
    'workspace': 'w1',
  });

  DataRequest request(String id, String label, String slug) =>
      DataRequest.fromJson({'id': id, 'label': label, 'slug': slug});

  Contact contact(String id, String name, String email) =>
      Contact.fromJson({'id': id, 'name': name, 'email': email});

  final records = [
    record('r1', 'iban', 'DE89370400440532013000', label: 'Main IBAN'),
    record('r2', 'full_name', 'Ada Lovelace'),
    record('r3', 'old_iban', 'DE02120300000000202051'),
  ];
  final links = [link('l1', 'Property manager', 'k7m2p9')];

  test('matches names, never values', () {
    expect(quickSearch('DE89', records: records, links: links), isEmpty);
    expect(quickSearch('lovelace', records: records, links: links), isEmpty);
  });

  test('names starting with the query come first', () {
    // "iban" starts the first record's key, and is only inside "old_iban".
    final hits = quickSearch('iban', records: records, links: links);
    expect(hits.map((h) => h.title), ['Main IBAN', 'old_iban']);
  });

  test('links are found by label and by slug', () {
    expect(
      quickSearch('property', records: records, links: links).single.kind,
      QuickSearchKind.share,
    );
    expect(
      quickSearch('k7m2', records: records, links: links).single.location,
      '/shared/l1',
    );
  });

  test('a record opens its own page', () {
    final hit = quickSearch('full', records: records, links: links).single;
    expect(hit.location, '/vault/records/r2');
    expect(hit.kind, QuickSearchKind.record);
  });

  test('an empty query finds nothing', () {
    expect(quickSearch('  ', records: records, links: links), isEmpty);
  });

  test('every kind is searched, by its own names', () {
    final hits = quickSearch(
      'move',
      records: [
        record('r9', 'move_date', '2027-01-01'),
        models.Record.fromJson({
          'id': 'r10',
          'key': 'inventory',
          'value': '',
          'label': '',
          'type': 'file',
          'format': 'default',
          'filename': 'move-inventory.pdf',
          'user': 'u1',
          'workspace': 'w1',
        }),
      ],
      sections: [section('s1', 'moving', 'Move papers')],
      links: [link('l9', 'Move-in pack', 'aaa111')],
      requests: [request('q1', 'Move-in details', 'bbb222')],
      contacts: [contact('c1', 'Movers Ltd', 'hi@movers.test')],
      templates: [
        Template.fromJson({'id': 't1', 'name': 'Move-in form'}),
      ],
      bookmarks: [
        Bookmark.fromJson({
          'id': 'b1',
          'label': 'Movers quote',
          'slug': 'ccc333',
        }),
      ],
      credentials: [
        Credential.fromJson({
          'id': 'cr1',
          'type': 'movers_licence',
          'issuer': 'trade.test',
        }),
      ],
      attestations: [
        Attestation.fromJson({
          'id': 'a1',
          'type': 'move_out',
          'label': 'Move-out confirmed',
        }),
      ],
    );

    expect(
      hits.map((h) => h.kind).toSet(),
      QuickSearchKind.values.toSet(),
      reason: 'each kind contributes its match',
    );
  });

  test('a contact is found by address as well as by name', () {
    final hits = quickSearch(
      'movers.test',
      contacts: [contact('c1', 'Pat', 'hi@movers.test')],
    );
    expect(hits.single.title, 'Pat');
    expect(hits.single.kind, QuickSearchKind.contact);
  });

  test('the kind with the best match is listed first', () {
    // "ada" starts the contact's name and only sits inside the record's.
    final hits = quickSearch(
      'ada',
      records: [record('r1', 'notes_ada', 'x')],
      contacts: [contact('c1', 'Ada Lovelace', 'ada@example.com')],
    );
    expect(hits.first.kind, QuickSearchKind.contact);
  });

  test('one crowded kind cannot push the others out', () {
    final many = [for (var i = 0; i < 40; i++) record('r$i', 'move_$i', 'v')];
    final hits = quickSearch(
      'move',
      records: many,
      contacts: [contact('c1', 'Movers Ltd', 'hi@movers.test')],
      perKind: 5,
    );
    expect(hits.where((h) => h.kind == QuickSearchKind.record), hasLength(5));
    expect(hits.any((h) => h.kind == QuickSearchKind.contact), isTrue);
  });

  test('the overall ceiling is honoured', () {
    final hits = quickSearch(
      'move',
      records: [for (var i = 0; i < 40; i++) record('r$i', 'move_$i', 'v')],
      sections: [for (var i = 0; i < 40; i++) section('s$i', 'move_$i', '')],
      perKind: 5,
      limit: 7,
    );
    expect(hits, hasLength(7));
  });
}
