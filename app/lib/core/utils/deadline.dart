/// How close to its expiry a live link or request has to be before a list
/// flags it.
const Duration expiryWarning = Duration(days: 3);

/// "Expires in 2 days" when [expiresAt] falls within [expiryWarning] of
/// [now], "Past its expiry date" once it has passed, and null otherwise — the
/// one wording every list uses for a deadline.
String? expiryNotice(String? expiresAt, DateTime now) {
  final expires = DateTime.tryParse(expiresAt ?? '');
  if (expires == null) return null;

  final left = expires.difference(now);
  if (left.isNegative) return 'Past its expiry date';
  if (left >= expiryWarning) return null;
  if (left.inHours < 1) return 'Expires within the hour';
  if (left.inHours < 24) {
    final h = left.inHours;
    return 'Expires in $h ${h == 1 ? 'hour' : 'hours'}';
  }
  final d = left.inDays;
  return 'Expires in $d ${d == 1 ? 'day' : 'days'}';
}

/// Whether [expiresAt] has already passed.
bool isPastExpiry(String? expiresAt, DateTime now) {
  final expires = DateTime.tryParse(expiresAt ?? '');
  return expires != null && expires.isBefore(now);
}
