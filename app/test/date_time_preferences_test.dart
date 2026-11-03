import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/state/date_time_preferences.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dates read the way the reader's region writes them, in their own time,
/// unless they chose otherwise.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DateTimePreferences.setDateStyle(DateStyle.automatic);
    await DateTimePreferences.setClockStyle(ClockStyle.automatic);
    await DateTimePreferences.setTimeZone(null);
  });

  test('a German device gets German dates and a 24-hour clock', () {
    const germany = Locale('de', 'DE');
    expect(
      DateTimePreferences.dateStyleFor(germany),
      DateStyle.dayMonthYearDots,
    );
    expect(DateTimePreferences.clockStyleFor(germany), ClockStyle.hours24);
    expect(
      DateTimePreferences.dateStyleFor(const Locale('de')),
      DateStyle.dayMonthYearDots,
    );
  });

  test('other regions get their own', () {
    expect(
      DateTimePreferences.dateStyleFor(const Locale('en', 'US')),
      DateStyle.monthDayYear,
    );
    expect(
      DateTimePreferences.clockStyleFor(const Locale('en', 'US')),
      ClockStyle.hours12,
    );
    expect(
      DateTimePreferences.dateStyleFor(const Locale('en', 'GB')),
      DateStyle.dayMonthYearSlashes,
    );
    expect(
      DateTimePreferences.clockStyleFor(const Locale('en', 'GB')),
      ClockStyle.hours24,
    );
    expect(
      DateTimePreferences.dateStyleFor(const Locale('ja', 'JP')),
      DateStyle.yearMonthDay,
    );
  });

  test('a chosen zone and style decide what is shown', () async {
    await DateTimePreferences.setDateStyle(DateStyle.dayMonthYearDots);
    await DateTimePreferences.setClockStyle(ClockStyle.hours24);
    await DateTimePreferences.setTimeZone('Europe/Berlin');
    expect(dayTimeOf('2026-11-03 23:30:00.000Z'), '04.11.2026 00:30');

    await DateTimePreferences.setTimeZone('America/New_York');
    await DateTimePreferences.setClockStyle(ClockStyle.hours12);
    await DateTimePreferences.setDateStyle(DateStyle.monthDayYear);
    expect(dayTimeOf('2026-11-03 23:30:00.000Z'), '11/03/2026 6:30 PM');
  });

  test('a day picked on the calendar keeps its date in any zone', () async {
    await DateTimePreferences.setDateStyle(DateStyle.yearMonthDay);
    await DateTimePreferences.setTimeZone('Pacific/Honolulu');
    expect(formatCalendarDay(DateTime(2026, 12, 31)), '2026-12-31');
  });

  test('the choice survives a restart', () async {
    await DateTimePreferences.setDateStyle(DateStyle.yearMonthDay);
    await DateTimePreferences.setTimeZone('Asia/Tokyo');
    await DateTimePreferences.load();
    expect(DateTimePreferences.dateStyle, DateStyle.yearMonthDay);
    expect(DateTimePreferences.timeZone?.name, 'Asia/Tokyo');
  });

  test('an unknown zone falls back to the device', () async {
    await DateTimePreferences.setTimeZone('Mars/Olympus_Mons');
    expect(DateTimePreferences.timeZone, isNull);
  });
}
