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
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso.replaceFirst(' ', 'T'))?.toLocal();
  if (d == null) return '—';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// A server date as a day and a time of day, or a dash when there is none.
String momentText(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso.replaceFirst(' ', 'T'))?.toLocal();
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dayText(iso)} ${two(d.hour)}:${two(d.minute)}';
}
