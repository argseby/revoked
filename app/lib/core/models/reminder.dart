/// A person's own reminder about a vault entry: at a date, or the first time
/// an entry changes. The server delivers it as a notification and marks it
/// fired; it fires once until armed again.
class Reminder {
  static const kindDate = 'date';
  static const kindChange = 'change';

  final String id;

  /// The entry the reminder is about, and opens when it fires.
  final String record;

  /// [kindDate] or [kindChange].
  final String kind;

  /// When a date reminder fires.
  final DateTime? dueAt;

  /// The entry a change reminder watches: [record] itself, or another entry
  /// in the same workspace.
  final String? watch;
  final String note;

  /// When it fired; null while it is still waiting.
  final DateTime? firedAt;
  final String? created;

  const Reminder({
    required this.id,
    required this.record,
    required this.kind,
    this.dueAt,
    this.watch,
    this.note = '',
    this.firedAt,
    this.created,
  });

  bool get isDate => kind == kindDate;
  bool get hasFired => firedAt != null;

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'] as String,
      record: json['record'] as String? ?? '',
      kind: json['kind'] as String? ?? kindDate,
      dueAt: _date(json['dueAt']),
      watch: (json['watch'] as String?)?.isEmpty ?? true
          ? null
          : json['watch'] as String,
      note: json['note'] as String? ?? '',
      firedAt: _date(json['firedAt']),
      created: json['created'] as String?,
    );
  }

  /// PocketBase sends dates as "2026-10-02 09:00:00.000Z", and an unset one
  /// as "".
  static DateTime? _date(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }
}
