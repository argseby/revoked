import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_button.dart';

/// A hidden value drawn as a solid ink bar — the redaction mark of the logo —
/// until it is revealed.
///
/// The bar's length follows the value's, within limits, so an IBAN and a PIN
/// do not look alike, and nothing of the value itself is on screen or in the
/// accessibility tree: a screen reader says "Hidden value". [onCopy] adds a
/// copy button; how a copy is confirmed is the caller's.
class RedactedValue extends StatefulWidget {
  final String value;

  /// Offers a show/hide button. Off where the value must stay hidden.
  final bool revealable;
  final VoidCallback? onCopy;

  const RedactedValue(
    this.value, {
    super.key,
    this.revealable = true,
    this.onCopy,
  });

  @override
  State<RedactedValue> createState() => _RedactedValueState();
}

class _RedactedValueState extends State<RedactedValue> {
  final Local<bool> _show = Local(false);

  @override
  Widget build(BuildContext context) => Observer(builder: _build);

  Widget _build(BuildContext context) {
    final length = widget.value.characters.length;
    final barWidth = (length * 9.0).clamp(48.0, 240.0);
    final shown = _show.value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: shown
              ? AppText(widget.value).mono.selectable
              : RedactionBar(width: barWidth),
        ),
        if (widget.revealable) ...[
          AppSpacing.gapSm,
          AppButton(
            icon: shown ? AppIcons.eyeSlash : AppIcons.eye,
            tooltip: shown ? 'Hide value' : 'Show value',
            style: AppButtonStyle.ghost,
            size: AppButtonSize.small,
            onTap: () => _show.value = !shown,
          ),
        ],
        if (widget.onCopy != null)
          AppButton(
            icon: AppIcons.copy,
            tooltip: 'Copy value',
            style: AppButtonStyle.ghost,
            size: AppButtonSize.small,
            onTap: widget.onCopy,
          ),
      ],
    );
  }
}

/// The bar itself: solid ink where a value is hidden. On its own in lists,
/// where a row shows a record's value without the controls to reveal it.
class RedactionBar extends StatelessWidget {
  final double width;

  /// Sized to the line it stands in for: body or small text.
  final bool small;

  const RedactionBar({super.key, this.width = 96, this.small = false});

  @override
  Widget build(BuildContext context) {
    final size = small ? AppTextSize.small : AppTextSize.body;
    return Semantics(
      label: 'Hidden value',
      excludeSemantics: true,
      child: Container(
        width: width,
        height: size * 0.8,
        margin: EdgeInsets.symmetric(vertical: size * 0.25),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface,
          borderRadius: AppRadius.allXs,
        ),
      ),
    );
  }
}
