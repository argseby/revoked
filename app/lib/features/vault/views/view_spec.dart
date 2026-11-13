/// The section view format: a layout written as data, drawn by the app with
/// widgets it already has. A view never runs code and never loads anything
/// from outside; every value it shows comes from a record, named by its key.
///
/// ```json
/// { "version": 1, "id": "wifi", "name": "Wi-Fi", "accent": "teal",
///   "match": ["network_name", "wifi_password"],
///   "blocks": [ { "type": "header", "title": "{network_name}" } ] }
/// ```
///
/// Text may hold `{key}` or `{key|filter}`; the filters are a fixed list
/// ([ViewText.filters]), never expressions. Anything clever — the next dose
/// of a medicine, days until an inspection — lives inside a block written
/// once in Dart, which the view only configures.
library;

/// The newest format this app reads. A view asking for more is not shown.
const viewFormatVersion = 1;

class ViewSpec {
  final String id;
  final String name;

  /// A colour name from the design tokens: teal, blue, red, amber, green,
  /// violet. Never a raw colour value.
  final String accent;

  /// The record keys a section must hold for this view to apply. A
  /// `group:<name>` entry asks for at least one member of that group.
  final List<String> match;
  final List<ViewBlock> blocks;

  const ViewSpec({
    required this.id,
    required this.name,
    required this.accent,
    required this.match,
    required this.blocks,
  });

  /// Null when [json] is not a view this app can draw.
  static ViewSpec? parse(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int || version < 1 || version > viewFormatVersion) {
      return null;
    }
    final id = json['id'];
    final match = json['match'];
    if (id is! String || id.isEmpty || match is! List || match.isEmpty) {
      return null;
    }
    final blocks = ViewBlock.parseAll(json['blocks']);
    if (blocks.isEmpty) return null;
    return ViewSpec(
      id: id,
      name: json['name'] is String ? json['name'] as String : id,
      accent: json['accent'] is String ? json['accent'] as String : 'blue',
      match: [
        for (final m in match)
          if (m is String && m.isNotEmpty) m,
      ],
      blocks: blocks,
    );
  }
}

/// Shows a block only when a record holds a value, or a given one.
class ViewCondition {
  final String key;

  /// Null asks only that the value is there and not empty.
  final String? equals;

  const ViewCondition(this.key, this.equals);

  static ViewCondition? parse(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    if (key is! String || key.isEmpty) return null;
    final equals = json['is'];
    return ViewCondition(key, equals is String ? equals : null);
  }
}

/// One column of a [ScheduleBlock]: the record field holding the amount and
/// the time of day it is taken.
class ScheduleColumn {
  final String field;
  final String label;

  /// `HH:mm`, local time.
  final String time;

  const ScheduleColumn(this.field, this.label, this.time);
}

/// One label and value in a [FactsBlock].
class FactItem {
  final String label;
  final String value;
  final bool mono;
  const FactItem(this.label, this.value, {this.mono = false});
}

sealed class ViewBlock {
  final ViewCondition? when;
  const ViewBlock(this.when);

  static List<ViewBlock> parseAll(Object? json) => [
    if (json is List)
      for (final entry in json)
        if (entry is Map) ?parse(entry.cast<String, dynamic>()),
  ];

  /// Null for a block type this app does not know: a newer view still shows
  /// everything else it holds.
  static ViewBlock? parse(Map<String, dynamic> j) {
    String str(String key, [String fallback = '']) =>
        j[key] is String ? j[key] as String : fallback;
    int integer(String key, int fallback) =>
        j[key] is int ? j[key] as int : fallback;
    final when = ViewCondition.parse(j['when']);
    switch (j['type']) {
      case 'header':
        return HeaderBlock(
          when,
          eyebrow: str('eyebrow'),
          title: str('title'),
          subtitle: str('subtitle'),
          icon: str('icon', 'folder'),
        );
      case 'text':
        return TextBlock(when, text: str('text'), tone: str('tone', 'muted'));
      case 'badges':
        return BadgesBlock(
          when,
          items: [
            for (final b in (j['items'] as List?) ?? const [])
              if (b is Map && b['text'] is String)
                (
                  text: b['text'] as String,
                  tone: b['tone'] is String ? b['tone'] as String : 'neutral',
                  when: ViewCondition.parse(b['when']),
                ),
          ],
        );
      case 'facts':
        return FactsBlock(
          when,
          items: [
            for (final f in (j['items'] as List?) ?? const [])
              if (f is Map && f['label'] is String && f['value'] is String)
                FactItem(
                  f['label'] as String,
                  f['value'] as String,
                  mono: f['mono'] == true,
                ),
          ],
        );
      case 'secret':
        final key = str('key');
        if (key.isEmpty) return null;
        return SecretBlock(when, label: str('label'), key: key);
      case 'qr':
        return QrBlock(
          when,
          data: str('data'),
          revealWith: str('revealWith'),
          caption: str('caption'),
        );
      case 'actions':
        return ActionsBlock(
          when,
          items: [
            for (final a in (j['items'] as List?) ?? const [])
              if (a is Map && a['label'] is String && a['key'] is String)
                (
                  label: a['label'] as String,
                  key: a['key'] as String,
                  kind: a['kind'] is String ? a['kind'] as String : 'url',
                ),
          ],
        );
      case 'countdown':
        final key = str('key');
        if (key.isEmpty) return null;
        return CountdownBlock(
          when,
          label: str('label'),
          key: key,
          warnDays: integer('warnDays', 30),
        );
      case 'split':
        return SplitBlock(
          when,
          main: parseAll(j['main']),
          side: parseAll(j['side']),
        );
      case 'schedule':
        final group = str('group');
        if (group.isEmpty) return null;
        final refill = j['refill'];
        return ScheduleBlock(
          when,
          group: group,
          heading: str('heading', 'Item'),
          label: str('label', 'name'),
          detail: str('detail'),
          note: str('note'),
          until: str('until'),
          columns: [
            for (final c in (j['columns'] as List?) ?? const [])
              if (c is Map && c['field'] is String)
                ScheduleColumn(
                  c['field'] as String,
                  c['label'] is String ? c['label'] as String : c['field'],
                  c['time'] is String ? c['time'] as String : '08:00',
                ),
          ],
          showNext: j['next'] == true,
          refillStock: refill is Map && refill['stock'] is String
              ? refill['stock'] as String
              : null,
          refillWarnDays: refill is Map && refill['warnDays'] is int
              ? refill['warnDays'] as int
              : 7,
        );
      case 'divider':
        return DividerBlock(when);
    }
    return null;
  }
}

/// The view's title row: an icon, a small line above, the title.
class HeaderBlock extends ViewBlock {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String icon;
  const HeaderBlock(
    super.when, {
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

/// A line of text; `tone` is muted, body or warning.
class TextBlock extends ViewBlock {
  final String text;
  final String tone;
  const TextBlock(super.when, {required this.text, required this.tone});
}

/// Small labels, each with its own condition: "Guest network", "Organ donor".
class BadgesBlock extends ViewBlock {
  final List<({String text, String tone, ViewCondition? when})> items;
  const BadgesBlock(super.when, {required this.items});
}

/// Labelled values in a grid. Items whose text is empty once filled in are
/// left out, so an unanswered field leaves no gap.
class FactsBlock extends ViewBlock {
  final List<FactItem> items;
  const FactsBlock(super.when, {required this.items});
}

/// A hidden value with show and copy. Blocks naming it in `revealWith`
/// appear only once it is shown.
class SecretBlock extends ViewBlock {
  final String label;
  final String key;
  const SecretBlock(super.when, {required this.label, required this.key});
}

/// A code to scan, filled in from records.
class QrBlock extends ViewBlock {
  final String data;

  /// The secret the code carries; it stays covered until that is shown.
  final String revealWith;
  final String caption;
  const QrBlock(
    super.when, {
    required this.data,
    required this.revealWith,
    required this.caption,
  });
}

/// Buttons that act on a record's value: open a URL, call, write a mail.
class ActionsBlock extends ViewBlock {
  final List<({String label, String key, String kind})> items;
  const ActionsBlock(super.when, {required this.items});
}

/// Days until a date, turning to a warning [warnDays] ahead and to overdue
/// once it has passed.
class CountdownBlock extends ViewBlock {
  final String label;
  final String key;
  final int warnDays;
  const CountdownBlock(
    super.when, {
    required this.label,
    required this.key,
    required this.warnDays,
  });
}

/// Two columns side by side when there is room, stacked otherwise.
class SplitBlock extends ViewBlock {
  final List<ViewBlock> main;
  final List<ViewBlock> side;
  const SplitBlock(super.when, {required this.main, required this.side});
}

/// A plan over the day for each member of a record group: one row per
/// member, one column per time of day. Works out the next dose and when the
/// stock runs out.
class ScheduleBlock extends ViewBlock {
  final String group;

  /// The first column's heading: "Medicine".
  final String heading;
  final String label;
  final String detail;
  final String note;
  final String until;
  final List<ScheduleColumn> columns;
  final bool showNext;
  final String? refillStock;
  final int refillWarnDays;
  const ScheduleBlock(
    super.when, {
    required this.group,
    required this.heading,
    required this.label,
    required this.detail,
    required this.note,
    required this.until,
    required this.columns,
    required this.showNext,
    required this.refillStock,
    required this.refillWarnDays,
  });
}

class DividerBlock extends ViewBlock {
  const DividerBlock(super.when);
}
