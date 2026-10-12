import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/section.dart';

/// Who a link hands a record to, in the terms the owner thinks in.
enum AccessKind {
  /// A link made in the app: anyone who holds it.
  link,

  /// An answer to someone's request, given from the vault.
  requestAnswer,

  /// A link a connected tool proposed and the owner confirmed.
  tool,
}

AccessKind accessKindOf(Link l) {
  if (l.request.isNotEmpty) return AccessKind.requestAnswer;
  if (l.connection.isNotEmpty || l.proposedBy.isNotEmpty) {
    return AccessKind.tool;
  }
  return AccessKind.link;
}

/// One way a record can be read from outside: a link, and how the record got
/// into it — directly, through a section, or through an alias that forwards
/// the record's value.
class RecordAccess {
  final Link link;
  final AccessKind kind;

  /// The section that carries the record into the link, if any.
  final String? viaSection;

  /// The alias record that carries the value into the link, if any.
  final String? viaAlias;

  const RecordAccess({
    required this.link,
    required this.kind,
    this.viaSection,
    this.viaAlias,
  });

  /// Readable right now. A paused link refuses reads until it is resumed,
  /// a revoked or expired one for good.
  bool get isOpen => link.status == 'active';

  /// How the record got into the link, for a subtitle.
  String get route {
    if (viaAlias != null) return 'Through the alias $viaAlias';
    if (viaSection != null) return 'Through the section $viaSection';
    return 'Shared directly';
  }

  /// Who receives it, for a subtitle.
  String get audience => switch (kind) {
    AccessKind.link => 'Anyone with the link',
    AccessKind.requestAnswer => 'Answer to a request',
    AccessKind.tool =>
      link.proposedBy.isEmpty
          ? 'A connected tool'
          : 'Connected tool ${link.proposedBy}',
  };
}

String _sectionName(Section s) => s.name.isEmpty ? s.key : s.name;
String _recordName(models.Record r) => r.label.isEmpty ? r.key : r.label;

/// Every link that exposes [recordId], open ones first. A link reaches a
/// record when it lists the record, lists a section holding it, or does
/// either for an alias of it — an alias forwards the value, so sharing the
/// alias shares the record.
List<RecordAccess> accessForRecord(
  String recordId, {
  required Iterable<Link> links,
  required Iterable<Section> sections,
  required Iterable<models.Record> records,
}) {
  // The record itself, then every alias pointing at it.
  final carriers = <String, String?>{recordId: null};
  for (final r in records) {
    if (r.aliasOf == recordId) carriers[r.id] = _recordName(r);
  }

  final result = <String, RecordAccess>{};
  void add(Link l, {String? viaSection, String? viaAlias}) {
    result.putIfAbsent(
      l.id,
      () => RecordAccess(
        link: l,
        kind: accessKindOf(l),
        viaSection: viaSection,
        viaAlias: viaAlias,
      ),
    );
  }

  for (final entry in carriers.entries) {
    final holding = sections.where((s) => s.records.contains(entry.key));
    for (final l in links) {
      if (l.records.contains(entry.key)) {
        add(l, viaAlias: entry.value);
        continue;
      }
      for (final s in holding) {
        if (l.sections.contains(s.id)) {
          add(l, viaSection: _sectionName(s), viaAlias: entry.value);
          break;
        }
      }
    }
  }

  // Open first, newest first; ties keep the order they were found in.
  final found = result.values.toList();
  final order = {for (final (i, a) in found.indexed) a.link.id: i};
  return found..sort((a, b) {
    if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
    final byDate = (b.link.created ?? '').compareTo(a.link.created ?? '');
    if (byDate != 0) return byDate;
    return order[a.link.id]!.compareTo(order[b.link.id]!);
  });
}

/// The records someone else can read right now, with the open links that
/// reach each, most widely shared first. Records nobody can read are left
/// out.
List<(models.Record, List<RecordAccess>)> openAccessByRecord({
  required Iterable<Link> links,
  required Iterable<Section> sections,
  required Iterable<models.Record> records,
}) {
  final open = links.where((l) => l.status == 'active').toList();
  final rows = <(models.Record, List<RecordAccess>)>[];
  for (final r in records) {
    // An alias is listed under the record whose value it forwards.
    if (r.isAlias) continue;
    final access = accessForRecord(
      r.id,
      links: open,
      sections: sections,
      records: records,
    );
    if (access.isNotEmpty) rows.add((r, access));
  }
  rows.sort((a, b) => b.$2.length.compareTo(a.$2.length));
  return rows;
}
