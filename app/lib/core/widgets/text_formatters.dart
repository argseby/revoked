import 'package:flutter/services.dart';

class SlugInputFormatter extends TextInputFormatter {
  /// Underscore is allowed: the server's slug pattern accepts it, and the
  /// app's own suggestion generator produces `something_1`.
  static final _disallowed = RegExp(r'[^a-z0-9_-]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final filtered = newValue.text.toLowerCase().replaceAll(_disallowed, '');

    // Keep the caret where the typing happened. Collapsing it to the end sent
    // it flying whenever someone corrected a character mid-slug.
    final removedBeforeCaret = _removedBefore(
      newValue.text,
      newValue.selection.baseOffset,
    );
    final offset = (newValue.selection.baseOffset - removedBeforeCaret).clamp(
      0,
      filtered.length,
    );

    return TextEditingValue(
      text: filtered,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }

  int _removedBefore(String raw, int caret) {
    if (caret < 0) return 0;
    final upTo = raw.substring(0, caret.clamp(0, raw.length)).toLowerCase();
    return upTo.length - upTo.replaceAll(_disallowed, '').length;
  }
}

class KeyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text.toLowerCase().replaceAll(' ', '_');
    text = text.replaceAll(RegExp(r'[^a-z0-9_]'), '');

    int newOffset = newValue.selection.baseOffset;
    if (newOffset > text.length) {
      newOffset = text.length;
    }

    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}

/// A record key made from a human label: "Steuer-ID (privat)" becomes
/// `steuer_id_privat`. German umlauts are spelled out rather than dropped, so
/// "Geburtsdatum Mütter" does not turn into `geburtsdatum_mtter`. The result
/// avoids every key in [taken] by appending `_2`, `_3`, …; an empty or
/// all-symbol label yields `record`.
String keyFromLabel(String label, Iterable<String> taken) {
  const spelled = {'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss'};
  var base = label.trim().toLowerCase();
  spelled.forEach((from, to) => base = base.replaceAll(from, to));
  base = base
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (base.isEmpty) base = 'record';
  if (base.length > 90) base = base.substring(0, 90);

  final used = taken.toSet();
  if (!used.contains(base)) return base;
  for (var n = 2; ; n++) {
    final candidate = '${base}_$n';
    if (!used.contains(candidate)) return candidate;
  }
}
