import 'package:flutter/widgets.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:revoked_app/core/models/contact.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/router/app_router.dart';

/// What kind of thing a hit is, in the order its group is listed when several
/// kinds match equally well.
enum QuickSearchKind {
  record('Record'),
  file('File'),
  section('Section'),
  share('Link'),
  request('Request'),
  contact('Contact'),
  credential('Held attestation'),
  attestation('Issued attestation'),
  bookmark('Saved link'),
  template('Template');

  const QuickSearchKind(this.label);

  /// What kind it is, said plainly, for the group heading and the row.
  final String label;
}

/// One thing the search drawer found, and where it opens.
class QuickSearchHit {
  final IconData icon;
  final String title;
  final QuickSearchKind kind;
  final String location;

  /// A second line where the title alone does not say which one this is — a
  /// contact's address, the server a saved link lives on.
  final String? subtitle;

  const QuickSearchHit({
    required this.icon,
    required this.title,
    required this.kind,
    required this.location,
    this.subtitle,
  });
}

/// Everything whose name matches [query], grouped by kind, names starting
/// with the query first.
///
/// Only names are searched — a record's label, key or file name, a link's
/// label or slug, a contact's name or address — never a value, hidden or not.
/// A value is what someone chose not to show; typing half of one and having
/// the app complete it would undo that.
///
/// Each collection is optional so a caller can search a subset, and so the
/// whole thing stays testable without stores. [perKind] bounds any one kind
/// so a crowded vault cannot push every contact off the list; [limit] bounds
/// the lot.
List<QuickSearchHit> quickSearch(
  String query, {
  Iterable<models.Record> records = const [],
  Iterable<Section> sections = const [],
  Iterable<Link> links = const [],
  Iterable<DataRequest> requests = const [],
  Iterable<Contact> contacts = const [],
  Iterable<Credential> credentials = const [],
  Iterable<Attestation> attestations = const [],
  Iterable<Bookmark> bookmarks = const [],
  Iterable<Template> templates = const [],
  int perKind = 5,
  int limit = 24,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  // 0 when a name starts with the query, 1 when it only contains it.
  int? rank(Iterable<String> names) {
    int? best;
    for (final name in names) {
      final n = name.toLowerCase();
      if (n.startsWith(q)) return 0;
      if (n.contains(q)) best = 1;
    }
    return best;
  }

  // Keyed by kind so one kind cannot crowd out the others, and so the panel
  // can head each group. The position is kept because List.sort is not
  // stable, so it breaks ties within a rank.
  final found = <QuickSearchKind, List<(int, int, QuickSearchHit)>>{};
  var position = 0;
  void add(Iterable<String> names, QuickSearchHit Function() build) {
    final score = rank(names);
    if (score == null) return;
    final hit = build();
    (found[hit.kind] ??= []).add((score, position++, hit));
  }

  for (final r in records) {
    add([r.label, r.key, if (r.isFile) r.displayName], () {
      final named = r.isFile && r.displayName.isNotEmpty;
      return QuickSearchHit(
        icon: r.isFile ? AppIcons.fileEarmark : AppIcons.key,
        title: r.label.isNotEmpty ? r.label : (named ? r.displayName : r.key),
        kind: r.isFile ? QuickSearchKind.file : QuickSearchKind.record,
        location: AppRoutes.recordDetailFor(r.id),
      );
    });
  }
  for (final s in sections) {
    add([s.name, s.key], () {
      final count = s.records.length;
      return QuickSearchHit(
        icon: AppIcons.folder,
        title: s.name.isEmpty ? s.key : s.name,
        kind: QuickSearchKind.section,
        location: AppRoutes.vault,
        subtitle: '$count ${count == 1 ? 'record' : 'records'}',
      );
    });
  }
  for (final l in links) {
    add([l.label, l.slug], () {
      return QuickSearchHit(
        icon: AppIcons.link,
        title: l.label.isEmpty ? l.slug : l.label,
        kind: QuickSearchKind.share,
        location: AppRoutes.shareDetailFor(l.id),
      );
    });
  }
  for (final r in requests) {
    add([r.label, r.slug], () {
      return QuickSearchHit(
        icon: AppIcons.inboxFill,
        title: r.label.isEmpty ? r.slug : r.label,
        kind: QuickSearchKind.request,
        location: AppRoutes.requestDetailFor(r.id),
      );
    });
  }
  for (final c in contacts) {
    add([c.name, c.email], () {
      return QuickSearchHit(
        icon: AppIcons.person,
        title: c.name,
        kind: QuickSearchKind.contact,
        location: AppRoutes.contacts,
        subtitle: c.where.isEmpty ? null : c.where,
      );
    });
  }
  for (final c in credentials) {
    add([c.type, c.issuer], () {
      return QuickSearchHit(
        icon: AppIcons.shieldCheck,
        title: c.type,
        kind: QuickSearchKind.credential,
        location: AppRoutes.attestations,
        subtitle: 'From ${c.issuer}',
      );
    });
  }
  for (final a in attestations) {
    add([a.label, a.type], () {
      return QuickSearchHit(
        icon: AppIcons.shieldLock,
        title: a.title,
        kind: QuickSearchKind.attestation,
        location: AppRoutes.attestationsIssued,
        subtitle: a.subject.isEmpty ? null : a.subject,
      );
    });
  }
  for (final b in bookmarks) {
    add([b.label, b.slug], () {
      return QuickSearchHit(
        icon: AppIcons.bookmark,
        title: b.title,
        kind: QuickSearchKind.bookmark,
        location: b.location,
        subtitle: b.origin.isEmpty ? 'This server' : b.origin,
      );
    });
  }
  for (final t in templates) {
    add([t.name], () {
      return QuickSearchHit(
        icon: AppIcons.cardList,
        title: t.name,
        kind: QuickSearchKind.template,
        location: AppRoutes.templates,
      );
    });
  }

  // A group's place is its best match, so typing a contact's name does not
  // list every loosely-matching record above them; the enum's order settles
  // kinds that match equally well.
  int best(QuickSearchKind kind) =>
      found[kind]!.map((e) => e.$1).reduce((a, b) => a < b ? a : b);
  final kinds = found.keys.toList()
    ..sort((a, b) {
      final byScore = best(a) - best(b);
      return byScore != 0 ? byScore : a.index - b.index;
    });

  final out = <QuickSearchHit>[];
  for (final kind in kinds) {
    final hits = found[kind]!
      ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    out.addAll(hits.take(perKind).map((e) => e.$3));
    if (out.length >= limit) break;
  }
  return out.take(limit).toList();
}
