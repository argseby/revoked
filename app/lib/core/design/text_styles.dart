import 'package:flutter/material.dart';

/// The app's entire text vocabulary: three sizes, two modifiers.
///
/// `Text('x')` is body (14). `.header` (18, bold) and `.small` (12) are the
/// only other sizes; `.muted` (secondary color) and `.mono` (fingerprints,
/// keys, code) the only modifiers. Nothing else exists — no inline fontSize or
/// fontWeight anywhere in a view.
class AppText extends StatelessWidget {
  final String data;
  final bool _header;
  final bool _small;
  final bool _bold;
  final bool _muted;
  final bool _mono;
  final bool _selectable;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const AppText(
    this.data, {
    super.key,
    bool header = false,
    bool small = false,
    bool muted = false,
    bool bold = false,
    bool mono = false,
    bool selectable = false,
    this.textAlign,
    this.maxLines,
    this.overflow,
  }) : _header = header,
       _small = small,
       _muted = muted,
       _bold = bold,
       _mono = mono,
       _selectable = selectable;

  AppText _copy({
    bool? header,
    bool? small,
    bool? muted,
    bool? bold,
    bool? mono,
    bool? selectable,
  }) {
    return AppText(
      data,
      key: key,
      header: header ?? _header,
      small: small ?? _small,
      muted: muted ?? _muted,
      mono: mono ?? _mono,
      bold: bold ?? _bold,
      selectable: selectable ?? _selectable,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  AppText get header => _copy(header: true, small: false);
  AppText get small => _copy(small: true, header: false);
  AppText get muted => _copy(muted: true);
  AppText get mono => _copy(mono: true);
  AppText get bold => _copy(bold: true);

  /// Lets the reader copy the text — fingerprints, keys, generated slugs.
  AppText get selectable => _copy(selectable: true);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: _header ? 18 : (_small ? 12 : 14),
      fontWeight: _header
          ? FontWeight.w700
          : _bold
          ? FontWeight.w600
          : FontWeight.w400,
      // Non-muted text inherits, so buttons and alerts keep their own color.
      color: _muted ? scheme.onSurfaceVariant : null,
      fontFamily: _mono ? 'monospace' : null,
    );
    if (_selectable) {
      return SelectableText(
        data,
        textAlign: textAlign,
        maxLines: maxLines,
        style: style,
      );
    }
    return Text(
      data,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: style,
    );
  }
}

/// Lets plain `Text` literals join the system: `Text('x').header.muted`.
extension AppTextSugar on Text {
  AppText _wrap() => AppText(
    data ?? '',
    key: key,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
  );

  AppText get header => _wrap().header;
  AppText get selectable => _wrap().selectable;
  AppText get small => _wrap().small;
  AppText get muted => _wrap().muted;
  AppText get mono => _wrap().mono;
}
