import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/features/shell/utils/quick_search.dart';

/// The search drawer finds things by name. It must never match a value —
/// a hidden IBAN is not something to type half of and see completed.
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
      'Link',
    );
    expect(
      quickSearch('k7m2', records: records, links: links).single.location,
      '/shared/l1',
    );
  });

  test('a record opens its own page', () {
    final hit = quickSearch('full', records: records, links: links).single;
    expect(hit.location, '/vault/records/r2');
    expect(hit.kind, 'Record');
  });

  test('an empty query finds nothing', () {
    expect(quickSearch('  ', records: records, links: links), isEmpty);
  });
}
