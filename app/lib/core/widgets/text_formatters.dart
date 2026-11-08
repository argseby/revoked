import 'package:flutter/services.dart';

/// German letters a key or slug spells out instead of dropping, so "Größe"
/// becomes `groesse` rather than `gre`.
const _spelledOut = {'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss'};

String _spellOut(String text) {
  var out = text;
  _spelledOut.forEach((from, to) => out = out.replaceAll(from, to));
  return out;
}

class SlugInputFormatter extends TextInputFormatter {
  /// Underscore is allowed: the server's slug pattern accepts it, and the
  /// app's own suggestion generator produces `something_1`.
  static final _disallowed = RegExp(r'[^a-z0-9_-]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.toLowerCase();
    final filtered = _spellOut(raw).replaceAll(_disallowed, '');

    // Keep the caret where the typing happened. Collapsing it to the end sent
    // it flying whenever someone corrected a character mid-slug.
    final caret = newValue.selection.baseOffset;
    final offset = caret < 0
        ? filtered.length
        : _spellOut(
            raw.substring(0, caret.clamp(0, raw.length)),
          ).replaceAll(_disallowed, '').length.clamp(0, filtered.length);

    return TextEditingValue(
      text: filtered,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }
}

class KeyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String clean(String s) => _spellOut(
      s.toLowerCase().replaceAll(' ', '_'),
    ).replaceAll(RegExp(r'[^a-z0-9_]'), '');
    final text = clean(newValue.text);

    final caret = newValue.selection.baseOffset;
    final newOffset = caret < 0
        ? text.length
        : clean(
            newValue.text.substring(0, caret.clamp(0, newValue.text.length)),
          ).length.clamp(0, text.length);

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
  var base = _spellOut(label.trim().toLowerCase());
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
