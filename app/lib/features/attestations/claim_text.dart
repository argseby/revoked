import 'package:revoked_app/core/utils/dates.dart';

/// A claim's value as it is shown: the words a person reads, not the JSON.
String claimText(Object? value) => switch (value) {
  true => 'Yes',
  false => 'No',
  null => '—',
  final num n => n == n.roundToDouble() ? n.toInt().toString() : n.toString(),
  _ => value.toString(),
};

/// A server date as a day, or a dash when there is none.
String dayText(String? iso) {
  return dayOf(iso) ?? '—';
}

/// A server date as a day and a time of day, or a dash when there is none.
String momentText(String? iso) => dayTimeOf(iso) ?? '—';
