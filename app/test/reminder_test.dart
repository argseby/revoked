import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/reminder.dart';
import 'package:revoked_app/features/reminders/view/reminder_sheet.dart';

void main() {
  group('reminderPresetDate', () {
    final from = DateTime(2026, 1, 31, 15, 42);

    test('lands at nine in the morning', () {
      expect(
        reminderPresetDate(ReminderPreset.week, from),
        DateTime(2026, 2, 7, 9),
      );
    });

    test('a month on takes the last day of a shorter month', () {
      expect(
        reminderPresetDate(ReminderPreset.month, from),
        DateTime(2026, 2, 28, 9),
      );
    });

    test('a year on from a leap day is the last of February', () {
      expect(
        reminderPresetDate(ReminderPreset.year, DateTime(2028, 2, 29)),
        DateTime(2029, 2, 28, 9),
      );
    });

    test('a month on in December rolls into the next year', () {
      expect(
        reminderPresetDate(ReminderPreset.month, DateTime(2026, 12, 10)),
        DateTime(2027, 1, 10, 9),
      );
    });
  });

  group('Reminder', () {
    test('reads PocketBase dates, and an unset one as null', () {
      final r = Reminder.fromJson({
        'id': 'r1',
        'record': 'rec1',
        'kind': 'date',
        'dueAt': '2026-10-09 07:00:00.000Z',
        'watch': '',
        'note': 'Renew',
        'firedAt': '',
      });
      expect(r.isDate, isTrue);
      expect(r.dueAt, DateTime.utc(2026, 10, 9, 7).toLocal());
      expect(r.watch, isNull);
      expect(r.hasFired, isFalse);
    });

    test('says what it waits for', () {
      const own = Reminder(
        id: 'a',
        record: 'rec1',
        kind: Reminder.kindChange,
        watch: 'rec1',
      );
      const other = Reminder(
        id: 'b',
        record: 'rec1',
        kind: Reminder.kindChange,
        watch: 'rec2',
      );
      String nameOf(String id) => id == 'rec2' ? 'Address' : '?';
      expect(describeReminder(own, 'rec1', nameOf), 'When this entry changes');
      expect(describeReminder(other, 'rec1', nameOf), 'When “Address” changes');
    });
  });
}
