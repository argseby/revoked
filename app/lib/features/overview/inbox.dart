/// What the Overview lists as its inbox: the things that need the person,
/// one row per concrete thing, and what changed lately. Plain functions over
/// what the stores already hold, so the wording can be tested without a
/// widget tree.
library;

import 'package:flutter/widgets.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/api_key.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/notification.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/models/webhook.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/utils/deadline.dart';
import 'package:revoked_app/features/shares/utils/record_access.dart';
import 'package:revoked_app/features/shares/view/link_groups.dart';

/// The server's notification type for "someone answered your request".
const requestResponseType = 'request_response';

/// How a row in "Needs you" is tinted. The icon and the words carry the
/// meaning too, so colour is never the only signal.
enum NeedTone { info, warning }

/// One thing that needs the person: "2 new answers to Payroll".
class NeedItem {
  final IconData icon;
  final String text;
  final String route;
  final NeedTone tone;

  const NeedItem({
    required this.icon,
    required this.text,
    required this.route,
    this.tone = NeedTone.warning,
  });

  @override
  String toString() => 'NeedItem($text → $route)';
}

/// Everything that needs the person, most pressing first: new answers, links
/// about to stop working, failing webhooks, keys about to expire, then paused
/// links. One row per concrete thing; the screen caps how many it shows.
List<NeedItem> needsYouItems({
  required Iterable<Link> links,
  required Iterable<AppNotification> notifications,
  required Iterable<DataRequest> requests,
  required Iterable<WebhookEndpoint> webhooks,
  required Iterable<ApiKey> apiKeys,
  required DateTime now,
  bool showAnswers = true,
}) {
  final items = <NeedItem>[];

  if (showAnswers) {
    // Unread answers per request, in the order the newest arrived.
    final counts = <String, int>{};
    final titles = <String, String>{};
    for (final n in notifications) {
      if (n.read || n.type != requestResponseType) continue;
      final id = n.refId ?? '';
      counts[id] = (counts[id] ?? 0) + 1;
      titles.putIfAbsent(id, () => n.title);
    }
    final labels = {for (final r in requests) r.id: r.label};
    for (final MapEntry(key: id, value: count) in counts.entries) {
      final label = labels[id] ?? '';
      final noun = count == 1 ? 'new answer' : 'new answers';
      items.add(
        NeedItem(
          icon: AppIcons.inboxFill,
          tone: NeedTone.info,
          text: label.isNotEmpty
              ? '$count $noun to $label'
              : id.isEmpty
              ? '$count $noun'
              : '$count $noun to a request',
          route: id.isEmpty
              ? AppRoutes.requests
              : AppRoutes.requestDetailFor(id),
        ),
      );
    }
  }

  // Links about to stop working on their own, soonest first.
  final ending = <(Link, DateTime?)>[
    for (final l in links)
      if (linkGroup(l, now) == LinkGroup.attention)
        (l, parseInstant(l.expiresAt)),
  ];
  ending.sort((a, b) {
    final ea = a.$2, eb = b.$2;
    if (ea == null && eb == null) return 0;
    if (ea == null) return 1;
    if (eb == null) return -1;
    return ea.compareTo(eb);
  });
  for (final (l, _) in ending) {
    items.add(
      NeedItem(
        icon: AppIcons.clock,
        text: '${linkName(l)} link ${_linkEnding(l, now)}',
        route: AppRoutes.shareDetailFor(l.id),
      ),
    );
  }

  for (final w in webhooks) {
    if (!w.isFailing) continue;
    items.add(
      NeedItem(
        icon: AppIcons.send,
        text:
            'Webhook failing: '
            '${w.description.isNotEmpty ? w.description : w.host}',
        route: AppRoutes.webhookFor(w.id),
      ),
    );
  }

  final expiring = <(ApiKey, DateTime)>[
    for (final k in apiKeys)
      if (parseInstant(k.expiresAt) case final end?
          when end.isAfter(now) &&
              end.isBefore(now.add(const Duration(days: 7))))
        (k, end),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  for (final (k, end) in expiring) {
    items.add(
      NeedItem(
        icon: AppIcons.key,
        text: 'API key ${k.label} ${_expires(end, now)}',
        route: AppRoutes.apiKeys,
      ),
    );
  }

  for (final l in links) {
    if (l.status != 'paused') continue;
    items.add(
      NeedItem(
        icon: AppIcons.pauseCircle,
        text: '${linkName(l)} link is paused',
        route: AppRoutes.shareDetailFor(l.id),
      ),
    );
  }

  return items;
}

/// What a link is called in a sentence.
String linkName(Link l) => l.label.trim().isEmpty ? 'Untitled' : l.label.trim();

/// "ends tomorrow", "has 1 view left" — why [l] is about to stop working.
String _linkEnding(Link l, DateTime now) {
  final end = parseInstant(l.expiresAt);
  // The same window the Links list flags, from deadline.dart.
  if (end != null && end.difference(now) < expiryWarning) {
    return end.isAfter(now) ? _ends(end, now) : 'is past its expiry date';
  }
  final left = l.maxViews - l.viewCount;
  if (l.maxViews > 0 && left <= 0) return 'has used all ${l.maxViews} views';
  if (l.maxViews > 0) return 'has $left ${left == 1 ? 'view' : 'views'} left';
  return 'ends soon';
}

/// "ends within the hour", "ends today", "ends tomorrow", "ends in 3 days".
String _ends(DateTime end, DateTime now) =>
    'ends ${_relativeDay(end, now, sameHour: 'within the hour')}';

/// The same, for a key: "expires tomorrow".
String _expires(DateTime end, DateTime now) =>
    'expires ${_relativeDay(end, now, sameHour: 'within the hour')}';

String _relativeDay(DateTime end, DateTime now, {required String sameHour}) {
  if (end.difference(now) < const Duration(hours: 1)) return sameHour;
  final e = end.toLocal(), n = now.toLocal();
  final days = DateTime(
    e.year,
    e.month,
    e.day,
  ).difference(DateTime(n.year, n.month, n.day)).inDays;
  return switch (days) {
    <= 0 => 'today',
    1 => 'tomorrow',
    _ => 'in $days days',
  };
}

/// One line in "Recent": a record, a link or an answer that changed lately.
class RecentItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final DateTime at;
  final String route;

  const RecentItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.at,
    required this.route,
  });

  @override
  String toString() => 'RecentItem($title · $subtitle)';
}

/// Records, links and answers mixed by when they last changed, newest first,
/// at most [limit] of them.
List<RecentItem> recentItems({
  required Iterable<models.Record> records,
  required Iterable<Section> sections,
  required Iterable<Link> links,
  required Iterable<AppNotification> notifications,
  required Iterable<DataRequest> requests,
  bool showAnswers = true,
  int limit = 8,
}) {
  // Gather cheap candidates first; only the few shown work out their reach.
  final candidates = <(DateTime, RecentItem Function(DateTime))>[];

  final open = [
    for (final l in links)
      if (l.status == 'active') l,
  ];
  for (final r in records) {
    if (r.isAlias) continue;
    final created = parseInstant(r.created);
    final updated = parseInstant(r.updated) ?? created;
    if (updated == null) continue;
    candidates.add((
      updated,
      (at) => RecentItem(
        icon: r.isFile ? AppIcons.fileEarmark : AppIcons.key,
        title: r.label.isEmpty ? r.key : r.label,
        subtitle: [
          _changed(created, updated) ? 'edited' : 'added',
          _reach(
            accessForRecord(
              r.id,
              links: open,
              sections: sections,
              records: records,
            ),
          ),
        ].join(' · '),
        at: at,
        route: AppRoutes.recordDetailFor(r.id),
      ),
    ));
  }

  for (final l in links) {
    final created = parseInstant(l.created);
    final updated = parseInstant(l.updated) ?? created;
    if (updated == null) continue;
    candidates.add((
      updated,
      (at) => RecentItem(
        icon: AppIcons.link,
        title: linkName(l),
        subtitle: [
          'Link',
          _linkVerb(l, created, updated),
          ?_linkContents(l),
        ].join(' · '),
        at: at,
        route: AppRoutes.shareDetailFor(l.id),
      ),
    ));
  }

  if (showAnswers) {
    final labels = {for (final r in requests) r.id: r.label};
    for (final n in notifications) {
      if (n.type != requestResponseType) continue;
      final at = parseInstant(n.created);
      if (at == null) continue;
      final id = n.refId ?? '';
      final label = labels[id] ?? '';
      candidates.add((
        at,
        (at) => RecentItem(
          icon: AppIcons.inboxFill,
          title: label.isNotEmpty ? label : n.title,
          subtitle: n.read ? 'answer received' : 'new answer',
          at: at,
          route: id.isEmpty
              ? AppRoutes.requests
              : AppRoutes.requestDetailFor(id),
        ),
      ));
    }
  }

  candidates.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final (at, build) in candidates.take(limit)) build(at)];
}

/// Whether [updated] is a later change rather than the creation itself.
bool _changed(DateTime? created, DateTime updated) =>
    created != null && updated.difference(created).inSeconds.abs() > 1;

/// "reaches 3 people", "reaches 1 person", "not shared". People are told
/// apart by the label on their link, as on the People list.
String _reach(List<RecordAccess> access) {
  final people = {
    for (final a in access)
      if (a.isOpen) a.link.label.trim().toLowerCase(),
  }.length;
  if (people == 0) return 'not shared';
  return 'reaches $people ${people == 1 ? 'person' : 'people'}';
}

String _linkVerb(Link l, DateTime? created, DateTime updated) {
  if (!_changed(created, updated)) return 'shared';
  return switch (l.status) {
    'active' => 'changed',
    'paused' => 'paused',
    'revoked' => 'revoked',
    'expired' => 'expired',
    final s => s,
  };
}

/// "2 records", "1 section", or null when the link carries nothing listed.
String? _linkContents(Link l) {
  final parts = [
    if (l.records.isNotEmpty)
      '${l.records.length} ${l.records.length == 1 ? 'record' : 'records'}',
    if (l.sections.isNotEmpty)
      '${l.sections.length} '
          '${l.sections.length == 1 ? 'section' : 'sections'}',
  ];
  return parts.isEmpty ? null : parts.join(', ');
}

/// How long ago [at] was, short enough for the end of a row: "now", "5 min",
/// "3 h", "2 d", then the day itself.
String ageLabel(DateTime at, DateTime now) {
  final ago = now.difference(at);
  if (ago.inMinutes < 1) return 'now';
  if (ago.inHours < 1) return '${ago.inMinutes} min';
  if (ago.inDays < 1) return '${ago.inHours} h';
  if (ago.inDays < 7) return '${ago.inDays} d';
  return formatDay(at);
}
