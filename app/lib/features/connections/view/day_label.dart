/// The local day of a server timestamp, or a dash when there is none.
String dayLabel(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.replaceFirst(' ', 'T'))?.toLocal();
  if (d == null) return '—';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
