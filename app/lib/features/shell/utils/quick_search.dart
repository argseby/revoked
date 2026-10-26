import 'package:flutter/widgets.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/router/app_router.dart';

/// One thing the search drawer found, and where it opens.
class QuickSearchHit {
  final IconData icon;
  final String title;

  /// What kind of thing it is, said plainly: "Record", "File", "Link".
  final String kind;
  final String location;

  const QuickSearchHit({
    required this.icon,
    required this.title,
    required this.kind,
    required this.location,
  });
}

/// Records and links whose name matches [query], names starting with it
/// first. Only names are searched — a record's label, key or file name and a
/// link's label or slug — never a value, hidden or not.
List<QuickSearchHit> quickSearch(
  String query, {
  required Iterable<models.Record> records,
  required Iterable<Link> links,
  int limit = 8,
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

  final hits = <(int, QuickSearchHit)>[];
  for (final r in records) {
    final title = r.label.isNotEmpty
        ? r.label
        : (r.isFile && r.displayName.isNotEmpty ? r.displayName : r.key);
    final score = rank([r.label, r.key, if (r.isFile) r.displayName]);
    if (score == null) continue;
    hits.add((
      score,
      QuickSearchHit(
        icon: r.isFile ? AppIcons.fileEarmark : AppIcons.key,
        title: title,
        kind: r.isFile ? 'File' : 'Record',
        location: AppRoutes.recordDetailFor(r.id),
      ),
    ));
  }
  for (final l in links) {
    final score = rank([l.label, l.slug]);
    if (score == null) continue;
    hits.add((
      score,
      QuickSearchHit(
        icon: AppIcons.link,
        title: l.label.isEmpty ? l.slug : l.label,
        kind: 'Link',
        location: AppRoutes.shareDetailFor(l.id),
      ),
    ));
  }
  // Within a rank, records before links, each in store order; List.sort is
  // not stable, so the position breaks ties.
  final order = [for (var i = 0; i < hits.length; i++) (hits[i].$1, i)]
    ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  return [for (final (_, i) in order.take(limit)) hits[i].$2];
}
