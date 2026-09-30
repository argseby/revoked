/// What a shared value is, for the icon it gets and what can be done with it
/// — call a phone number, write to an email address, open a web address.
///
/// The same rules as the public web page, so a value reads the same in the
/// browser and in the app.
enum ValueKind {
  phone,
  email,
  url,
  date,
  number,
  boolean,
  person,
  place,
  work,
  text,
  pdf,
  image,
  file,
}

final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
final _web = RegExp(r'^https?://\S+$', caseSensitive: false);
final _www = RegExp(r'^www\.\S+\.\S+$', caseSensitive: false);
final _phoneChars = RegExp(r'^\+?[\d\s()/.\-]+$');
final _phoneHint = RegExp(r'phone|tel|mobil|handy|fax');
final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})([T ]|$)');
final _placeHint = RegExp(r'address|adresse|street|stra(ss|ß)e');
final _workHint = RegExp(r'employer|company|arbeitgeber|firma');

/// Told from the record's [type] first, then from what the [value] looks
/// like, and last from its [key] or [label] — a text record holding
/// "+49 170 …" is a phone number.
ValueKind valueKindOf({
  required String type,
  required String value,
  String key = '',
  String label = '',
  String mime = '',
  String filename = '',
}) {
  final v = value.trim();
  final hint = '$key $label'.toLowerCase();
  if (type == 'file') {
    final m = mime.toLowerCase();
    final f = filename.toLowerCase();
    if (m.contains('pdf') || f.endsWith('.pdf')) return ValueKind.pdf;
    if (m.startsWith('image/') ||
        RegExp(r'\.(png|jpe?g|gif|webp|heic)$').hasMatch(f)) {
      return ValueKind.image;
    }
    return ValueKind.file;
  }
  if (type == 'boolean') return ValueKind.boolean;
  if (_email.hasMatch(v)) return ValueKind.email;
  if (type == 'url' || _web.hasMatch(v) || _www.hasMatch(v)) {
    return ValueKind.url;
  }
  final digits = RegExp(r'\d').allMatches(v).length;
  if (_phoneChars.hasMatch(v) &&
      digits >= 6 &&
      digits <= 15 &&
      (v.startsWith('+') || v.startsWith('0') || _phoneHint.hasMatch(hint))) {
    return ValueKind.phone;
  }
  if (type == 'datetime' || _isoDate.hasMatch(v)) return ValueKind.date;
  if (type == 'number') return ValueKind.number;
  if (_placeHint.hasMatch(hint)) return ValueKind.place;
  if (_workHint.hasMatch(hint)) return ValueKind.work;
  if (hint.contains('name')) return ValueKind.person;
  return ValueKind.text;
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The value as a person reads it: "Yes" for `true`, "12 April 1991" for
/// `1991-04-12`. Copying still copies the value as stored.
String displayValue(ValueKind kind, String value) {
  final v = value.trim();
  if (kind == ValueKind.boolean) {
    if (v.toLowerCase() == 'true') return 'Yes';
    if (v.toLowerCase() == 'false') return 'No';
  }
  if (kind == ValueKind.date) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
    if (m != null) {
      final month = int.parse(m.group(2)!);
      if (month >= 1 && month <= 12) {
        return '${int.parse(m.group(3)!)} ${_months[month - 1]} ${m.group(1)}';
      }
    }
  }
  return v;
}

/// Where the value's action leads: a call, an email, a web page. Only ever
/// `tel:`, `mailto:` or http(s) — a shared value must never become some
/// other kind of link.
Uri? actionUri(ValueKind kind, String value) {
  final v = value.trim();
  switch (kind) {
    case ValueKind.phone:
      final number = v.replaceAll(RegExp(r'[^\d+]'), '');
      return number.isEmpty ? null : Uri(scheme: 'tel', path: number);
    case ValueKind.email:
      return _email.hasMatch(v) ? Uri(scheme: 'mailto', path: v) : null;
    case ValueKind.url:
      final uri = Uri.tryParse(
        RegExp(r'^https?://', caseSensitive: false).hasMatch(v)
            ? v
            : 'https://$v',
      );
      if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
        return null;
      }
      return uri.host.isEmpty ? null : uri;
    default:
      return null;
  }
}
