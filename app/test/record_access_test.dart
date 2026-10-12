import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';
import 'package:revoked_app/features/shares/utils/record_access.dart';

models.Record record(String id, {String label = '', String? aliasOf}) =>
    models.Record(
      id: id,
      key: id,
      value: 'v',
      label: label,
      type: 'text',
      format: 'default',
      user: 'u',
      workspace: 'w',
      aliasOf: aliasOf,
    );

Link link(
  String id, {
  List<String> records = const [],
  List<String> sections = const [],
  String status = 'active',
  String request = '',
  String proposedBy = '',
}) => Link(
  id: id,
  slug: id,
  label: id,
  sections: sections,
  records: records,
  user: 'u',
  workspace: 'w',
  status: status,
  request: request,
  proposedBy: proposedBy,
);

Section section(String id, List<String> records) => Section(
  id: id,
  key: id,
  name: 'Banking',
  records: records,
  user: 'u',
  workspace: 'w',
);

/// "Who has my data" has to find a record however it reached a link —
/// directly, inside a section, or forwarded by an alias — and say who
/// receives it.
void main() {
  final iban = record('iban', label: 'IBAN');
  final alias = record('bank', label: 'Bank account', aliasOf: 'iban');
  final other = record('phone', label: 'Phone');
  final records = [iban, alias, other];
  final banking = section('banking', ['iban']);

  test('finds direct, section and alias routes, open links first', () {
    final access = accessForRecord(
      'iban',
      links: [
        link('closed', records: ['iban'], status: 'revoked'),
        link('direct', records: ['iban']),
        link('bySection', sections: ['banking']),
        link('byAlias', records: ['bank']),
        link('unrelated', records: ['phone']),
      ],
      sections: [banking],
      records: records,
    );

    expect(access.map((a) => a.link.id), [
      'direct',
      'bySection',
      'byAlias',
      'closed',
    ]);
    expect(access[0].route, 'Shared directly');
    expect(access[1].route, 'Through the section Banking');
    expect(access[2].route, 'Through the alias Bank account');
    expect(access.last.isOpen, isFalse);
  });

  test('names who receives it', () {
    final access = accessForRecord(
      'iban',
      links: [
        link('answer', records: ['iban'], request: 'r1'),
        link('tool', records: ['iban'], proposedBy: 'mietunterlagen.de'),
      ],
      sections: const [],
      records: records,
    );
    final byId = {for (final a in access) a.link.id: a};
    expect(byId['answer']!.kind, AccessKind.requestAnswer);
    expect(byId['tool']!.audience, 'Connected tool mietunterlagen.de');
  });

  test('the overview lists only records readable now, aliases folded in', () {
    final rows = openAccessByRecord(
      links: [
        link('a', records: ['iban']),
        link('b', records: ['bank']),
        link('gone', records: ['phone'], status: 'expired'),
      ],
      sections: const [],
      records: records,
    );
    expect(rows.map((r) => r.$1.id), ['iban']);
    expect(rows.single.$2.length, 2);
  });

  test('a key is made from the label, spelled out and unique', () {
    expect(keyFromLabel('Steuer-ID (privat)', const []), 'steuer_id_privat');
    expect(keyFromLabel('Größe Mütze', const []), 'groesse_muetze');
    expect(keyFromLabel('IBAN', const ['iban', 'iban_2']), 'iban_3');
    expect(keyFromLabel('  ***  ', const []), 'record');
  });
}
