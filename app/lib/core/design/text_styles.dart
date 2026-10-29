import 'package:flutter/material.dart';

/// The type scale, in logical pixels. Four sizes, so a screen's hierarchy is
/// readable at a glance and nothing is set smaller than 13.
abstract final class AppTextSize {
  static const double small = 13;
  static const double body = 16;
  static const double header = 20;
  static const double title = 28;

  /// Line height of body text, for paragraphs that wrap.
  static const double bodyHeight = 1.45;
  static const double smallHeight = 1.35;
  static const double headingHeight = 1.25;
  static const double titleHeight = 1.15;

  /// Large type set at the default tracking looks loose and formal; pulling
  /// it in is what makes a title read as a headline.
  static const double titleTracking = -0.6;
  static const double headerTracking = -0.2;
}

/// The app's entire text vocabulary: four sizes, a few modifiers.
///
/// `Text('x')` is body (16). `.title` (28, one per screen), `.header` (20,
/// bold) and `.small` (13) are the only other sizes; `.muted` (secondary
/// color), `.mono` (fingerprints, keys, code) and `.italic` (someone else's
/// words, quoted) the only modifiers. Nothing else exists — no inline
/// fontSize or fontWeight anywhere in a view.
class AppText extends StatelessWidget {
  final String data;
  final bool _title;
  final bool _header;
  final bool _small;
  final bool _bold;
  final bool _muted;
  final bool _mono;
  final bool _italic;
  final bool _selectable;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const AppText(
    this.data, {
    super.key,
    bool title = false,
    bool header = false,
    bool small = false,
    bool muted = false,
    bool bold = false,
    bool mono = false,
    bool italic = false,
    bool selectable = false,
    this.textAlign,
    this.maxLines,
    this.overflow,
  }) : _title = title,
       _header = header,
       _small = small,
       _muted = muted,
       _bold = bold,
       _mono = mono,
       _italic = italic,
       _selectable = selectable;

  AppText _copy({
    bool? title,
    bool? header,
    bool? small,
    bool? muted,
    bool? bold,
    bool? mono,
    bool? italic,
    bool? selectable,
  }) {
    return AppText(
      data,
      key: key,
      title: title ?? _title,
      header: header ?? _header,
      small: small ?? _small,
      muted: muted ?? _muted,
      mono: mono ?? _mono,
      italic: italic ?? _italic,
      bold: bold ?? _bold,
      selectable: selectable ?? _selectable,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  /// The screen's own name, once per screen.
  AppText get title => _copy(title: true, header: false, small: false);
  AppText get header => _copy(header: true, title: false, small: false);
  AppText get small => _copy(small: true, title: false, header: false);
  AppText get muted => _copy(muted: true);
  AppText get mono => _copy(mono: true);
  AppText get italic => _copy(italic: true);
  AppText get bold => _copy(bold: true);

  /// Lets the reader copy the text — fingerprints, keys, generated slugs.
  AppText get selectable => _copy(selectable: true);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heading = _title || _header;
    final style = TextStyle(
      fontSize: _title
          ? AppTextSize.title
          : _header
          ? AppTextSize.header
          : _small
          ? AppTextSize.small
          : AppTextSize.body,
      height: _title
          ? AppTextSize.titleHeight
          : _header
          ? AppTextSize.headingHeight
          : _small
          ? AppTextSize.smallHeight
          : AppTextSize.bodyHeight,
      fontWeight: heading
          ? FontWeight.w700
          : _bold
          ? FontWeight.w600
          : FontWeight.w400,
      letterSpacing: _title
          ? AppTextSize.titleTracking
          : _header
          ? AppTextSize.headerTracking
          : null,
      // Non-muted text inherits, so buttons and alerts keep their own color.
      color: _muted ? scheme.onSurfaceVariant : null,
      fontFamily: _mono ? 'monospace' : null,
      fontStyle: _italic ? FontStyle.italic : null,
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

  AppText get title => _wrap().title;
  AppText get header => _wrap().header;
  AppText get selectable => _wrap().selectable;
  AppText get small => _wrap().small;
  AppText get muted => _wrap().muted;
  AppText get mono => _wrap().mono;
}
