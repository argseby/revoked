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
