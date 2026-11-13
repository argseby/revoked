import 'dart:math' as math;

import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/features/vault/views/view_spec.dart';

/// The records a view draws from, found by key: the section's own first,
/// then the rest of the owner's vault. A template spreads a card over
/// several sections (the emergency contact, the doctor), and a key names
/// one record per account, so the lookup is never ambiguous.
class ViewData {
  final Map<String, models.Record> _byKey;

  /// Records found by id, for an alias to reach the record it points at.
  final Map<String, models.Record> _byId;

  /// The section's own keys: only these decide whether a view applies.
  final Set<String> _own;

  ViewData._(this._byKey, this._byId, this._own);

  factory ViewData({
    required List<models.Record> section,
    List<models.Record> vault = const [],
  }) {
    final byKey = <String, models.Record>{
      for (final r in vault)
        if (r.requestedBy == null) r.key: r,
      // The section's own win over a same-named one elsewhere.
      for (final r in section) r.key: r,
    };
    return ViewData._(
      byKey,
      {
        for (final r in [...vault, ...section]) r.id: r,
      },
      {for (final r in section) r.key},
    );
  }

  bool has(String key) => (value(key) ?? '').trim().isNotEmpty;

  /// Whether there is nothing to draw from at all, as for a new section.
  bool get isEmpty => _byKey.isEmpty;

  /// Stand-in values for every key [view] names, so a view can be previewed
  /// before any record exists: each key's own name, readable.
  factory ViewData.sample(Map<String, dynamic> view) {
    final keys = <String>{};
    void walk(Object? node) {
      if (node is Map) {
        for (final entry in node.entries) {
          if (entry.key == 'key' && entry.value is String) {
            keys.add(entry.value as String);
          }
          walk(entry.value);
        }
      } else if (node is List) {
        node.forEach(walk);
      } else if (node is String) {
        keys.addAll(_placeholder.allMatches(node).map((m) => m[1]!));
      }
    }

    walk(view['blocks']);
    for (final m in (view['match'] as List?) ?? const []) {
      if (m is String && !m.startsWith('group:')) keys.add(m);
    }
    return ViewData(
      section: [
        for (final key in keys)
          models.Record(
            id: 'sample-$key',
            key: key,
            value: key.replaceAll(RegExp('[_-]'), ' '),
            label: key,
            type: 'text',
            format: 'default',
            user: '',
            workspace: '',
          ),
      ],
    );
  }

  models.Record? record(String key) => _byKey[key];

  /// The value as this device can read it; null when there is none or it is
  /// encrypted for other devices. An alias reads its target.
  String? value(String key) {
    final r = _byKey[key];
    if (r == null || r.isLocked) return null;
    if (!r.isAlias) return r.value;
    final target = _byId[r.aliasOf];
    return target == null || target.isLocked ? null : target.value;
  }

  bool isHidden(String key) => _byKey[key]?.isHidden ?? false;

  bool isLocked(String key) => _byKey[key]?.isLocked ?? false;

  /// Whether a section qualifies for [spec]: every key it asks for is held,
  /// and every `group:` it names has at least one member.
  bool matches(ViewSpec spec) => spec.match.every(
    (m) => m.startsWith('group:')
        ? _own.any((k) => k.startsWith('${m.substring(6)}-'))
        : _own.contains(m),
  );

  bool test(ViewCondition? c) {
    if (c == null) return true;
    final v = (value(c.key) ?? '').trim();
    return c.equals == null ? v.isNotEmpty : v == c.equals;
  }

  /// Fills `{key}` and `{key|filter}` in [text]. A hidden value reads as
  /// dots unless its key is in [revealed]; one this device cannot read, as
  /// nothing.
  String fill(String text, {Set<String> revealed = const {}}) =>
      text.replaceAllMapped(_placeholder, (m) {
        final key = m[1]!;
        var v = value(key) ?? '';
        if (v.isNotEmpty && isHidden(key) && !revealed.contains(key)) {
          return '••••••';
        }
        for (final f in (m[2] ?? '').split('|').skip(1)) {
          v = ViewText.apply(f, v);
        }
        return v;
      });

  /// The record keys [text] names in its placeholders.
  Iterable<String> keysIn(String text) =>
      _placeholder.allMatches(text).map((m) => m[1]!);

  /// Whether [text] has every placeholder it names filled.
  bool complete(String text) =>
      _placeholder.allMatches(text).every((m) => has(m[1]!));

  static final _placeholder = RegExp(r'\{([a-z0-9_-]+)((?:\|[a-z]+)*)\}');

  /// The members of record group [name], in order: records keyed
  /// `<name>-<n>-<field>` gathered by `n`. A member with no fields filled is
  /// left out.
  List<ViewGroupMember> group(String name) {
    final members = <int, Map<String, String>>{};
    final prefix = RegExp('^${RegExp.escape(name)}-(\\d+)-([a-z0-9_-]+)\$');
    for (final key in _byKey.keys) {
      final m = prefix.firstMatch(key);
      if (m == null) continue;
      final v = (value(key) ?? '').trim();
      if (v.isEmpty) continue;
      (members[int.parse(m[1]!)] ??= {})[m[2]!] = v;
    }
    final order = members.keys.toList()..sort();
    return [for (final i in order) ViewGroupMember(i, members[i]!)];
  }
}

/// One member of a record group, such as one medicine of a plan.
class ViewGroupMember {
  final int index;
  final Map<String, String> fields;
  const ViewGroupMember(this.index, this.fields);

  String operator [](String field) => fields[field] ?? '';
}

/// The filters text may apply: a fixed list, so a view never computes.
abstract final class ViewText {
  static const filters = ['upper', 'lower', 'date', 'wifi'];

  static String apply(String filter, String v) => switch (filter) {
    'upper' => v.toUpperCase(),
    'lower' => v.toLowerCase(),
    'date' => switch (DateTime.tryParse(v)) {
      final t? => formatCalendarDay(t),
      null => v,
    },
    // The escaping a Wi-Fi join code needs around its separators.
    'wifi' => v.replaceAllMapped(RegExp(r'[\;,:"]'), (m) => '\\${m[0]}'),
    _ => v,
  };
}

/// Days from [now] until [date], counted in whole calendar days.
int daysUntil(DateTime date, DateTime now) {
  final a = DateTime(now.year, now.month, now.day);
  final b = DateTime(date.year, date.month, date.day);
  return b.difference(a).inDays;
}

/// How much of a dose a schedule cell asks for: "1", "½", "1/2", "1,5".
/// Empty, "-" and "0" are none.
double scheduleAmount(String raw) {
  final v = raw.trim().replaceAll(',', '.');
  if (v.isEmpty || v == '-' || v == '–') return 0;
  const fractions = {'½': 0.5, '¼': 0.25, '¾': 0.75, '⅓': 1 / 3};
  if (fractions[v] case final f?) return f;
  final slash = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(v);
  if (slash != null) {
    final d = int.parse(slash[2]!);
    return d == 0 ? 0 : int.parse(slash[1]!) / d;
  }
  return double.tryParse(v) ?? 0;
}

/// A member of a schedule as of a day: still running or ended.
bool scheduleActive(ViewGroupMember m, ScheduleBlock b, DateTime now) {
  if (b.until.isEmpty) return true;
  final end = DateTime.tryParse(m[b.until]);
  return end == null || daysUntil(end, now) >= 0;
}

/// The doses due next: the earliest time from [now] on, today or tomorrow,
/// at which any running member takes something.
({DateTime at, List<ViewGroupMember> members})? nextDose(
  List<ViewGroupMember> members,
  ScheduleBlock b,
  DateTime now,
) {
  ({DateTime at, List<ViewGroupMember> members})? best;
  for (final day in [0, 1]) {
    for (final c in b.columns) {
      final parts = c.time.split(':');
      final hour = int.tryParse(parts.first) ?? 8;
      final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      final at = DateTime(now.year, now.month, now.day + day, hour, minute);
      if (!at.isAfter(now)) continue;
      final due = [
        for (final m in members)
          if (scheduleActive(m, b, at) && scheduleAmount(m[c.field]) > 0) m,
      ];
      if (due.isEmpty) continue;
      if (best == null || at.isBefore(best.at)) best = (at: at, members: due);
    }
    if (best != null) return best;
  }
  return best;
}

/// Whole days the stock of [m] lasts at its daily amount; null when either
/// is unknown.
int? daysOfStock(ViewGroupMember m, ScheduleBlock b) {
  final field = b.refillStock;
  if (field == null) return null;
  final stock = scheduleAmount(m[field]);
  final daily = b.columns.fold<double>(
    0,
    (sum, c) => sum + scheduleAmount(m[c.field]),
  );
  if (daily <= 0 || m[field].trim().isEmpty) return null;
  return math.max(0, (stock / daily).floor());
}
