import 'package:revoked_app/core/utils/dates.dart';

/// The local day of a server timestamp, or a dash when there is none.
String dayLabel(String? iso) {
  return dayOf(iso) ?? '—';
}
