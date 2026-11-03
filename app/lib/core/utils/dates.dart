/// The one way the app writes a date or a time, in the style and zone chosen
/// under Appearance. Read inside an `Observer`, a change shows at once.
library;

import 'package:timezone/timezone.dart' as tz;

import 'package:revoked_app/core/state/date_time_preferences.dart';

/// A server timestamp, which may separate date and time with a space.
DateTime? parseInstant(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso.replaceFirst(' ', 'T'));
}

/// [instant] as it reads on the wall clock of the chosen time zone.
DateTime inDisplayZone(DateTime instant) {
  final zone = DateTimePreferences.timeZone;
  return zone == null ? instant.toLocal() : tz.TZDateTime.from(instant, zone);
}

/// Now, in the chosen time zone — for "today" and "yesterday".
DateTime displayNow() => inDisplayZone(DateTime.now());

/// The day [instant] falls on in the chosen time zone.
String formatDay(DateTime instant) => _day(inDisplayZone(instant));

/// The time of day of [instant] in the chosen time zone.
String formatTime(DateTime instant) => _time(inDisplayZone(instant));

/// The day and time of [instant] in the chosen time zone.
String formatDayTime(DateTime instant) {
  final t = inDisplayZone(instant);
  return '${_day(t)} ${_time(t)}';
}

/// A day picked on this device's calendar keeps its date; only a server
/// instant moves into the chosen zone. Converting a picked midnight would
/// show the day before in any zone west of the device.
String formatCalendarDay(DateTime day) =>
    day.isUtc ? formatDay(day) : _day(day);

/// [iso]'s day, or null when it is missing or unreadable.
String? dayOf(String? iso) {
  final t = parseInstant(iso);
  return t == null ? null : formatDay(t);
}

/// [iso]'s time of day, or null when it is missing or unreadable.
String? timeOf(String? iso) {
  final t = parseInstant(iso);
  return t == null ? null : formatTime(t);
}

/// [iso]'s day and time, or null when it is missing or unreadable.
String? dayTimeOf(String? iso) {
  final t = parseInstant(iso);
  return t == null ? null : formatDayTime(t);
}

String _day(DateTime t) => writeDay(t, DateTimePreferences.effectiveDateStyle);

String _two(int n) => n.toString().padLeft(2, '0');

/// [t]'s own date fields written in [style], whatever is chosen now.
String writeDay(DateTime t, DateStyle style) {
  final d = _two(t.day), m = _two(t.month), y = t.year.toString();
  return switch (style) {
    DateStyle.dayMonthYearDots => '$d.$m.$y',
    DateStyle.dayMonthYearSlashes => '$d/$m/$y',
    DateStyle.monthDayYear => '$m/$d/$y',
    DateStyle.yearMonthDay || DateStyle.automatic => '$y-$m-$d',
  };
}

String _time(DateTime t) {
  if (DateTimePreferences.effectiveClockStyle != ClockStyle.hours12) {
    return '${_two(t.hour)}:${_two(t.minute)}';
  }
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$hour:${_two(t.minute)} ${t.hour < 12 ? 'AM' : 'PM'}';
}
