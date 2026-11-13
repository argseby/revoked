import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';

/// Material 3 text field. Replaces shadcn's `TextField`, mapping its
/// `placeholder:` -> [hint], `features: [InputFeature.passwordToggle()]` ->
/// [passwordToggle], and `features: [InputFeature.leading(...)]` -> [leading].
class AppTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? hint;
  final String? label;
  final bool obscureText;
  final bool passwordToggle;
  final Widget? leading;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Renders the value in the mono face — keys, slugs, JSON.
  final bool mono;
  final int? maxLines;
  final int? minLines;
  final bool autofocus;
  final bool enabled;
  final String? initialValue;

  /// While the field is empty, it is outlined in the primary color and its
  /// [label] carries [AppRequiredBadge].
  final bool required;

  const AppTextField({
    super.key,
    this.controller,
    this.hint,
    this.label,
    this.obscureText = false,
    this.passwordToggle = false,
    this.leading,
    this.trailing,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.mono = false,
    this.maxLines = 1,
    this.minLines,
    this.autofocus = false,
    this.enabled = true,
    this.initialValue,
    this.required = false,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final Local<bool> _obscured = Local(
    widget.obscureText || widget.passwordToggle,
  );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (widget.required && controller != null) {
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => Observer(
          builder: (_) => _build(context, missing: value.text.trim().isEmpty),
        ),
      );
    }
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context, {bool missing = false}) {
    final obscured = _obscured.value;
    Widget? suffix = widget.trailing;
    if (widget.passwordToggle) {
      suffix = Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: AppButton(
          icon: obscured ? AppIcons.eye : AppIcons.eyeSlash,
          tooltip: obscured ? 'Show' : 'Hide',
          showTooltip: false,
          style: AppButtonStyle.ghost,
          size: AppButtonSize.small,
          onTap: () => _obscured.value = !obscured,
        ),
      );
    }

    return TextFormField(
      controller: widget.controller,
      initialValue: widget.controller == null ? widget.initialValue : null,
      obscureText: obscured,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      style: widget.mono ? const TextStyle(fontFamily: AppFont.mono) : null,
      maxLines: obscured ? 1 : widget.maxLines,
      minLines: widget.minLines,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      decoration: InputDecoration(
        hintText: widget.hint,
        labelText: missing ? null : widget.label,
        label: missing && widget.label != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(widget.label!)),
                  const SizedBox(width: AppSpacing.sm),
                  const AppRequiredBadge(),
                ],
              )
            : null,
        enabledBorder: missing ? _missingBorder(context) : null,
        prefixIcon: widget.leading,
        suffixIcon: suffix,
      ),
    );
  }

  /// The theme's resting outline, in the primary color.
  InputBorder? _missingBorder(BuildContext context) {
    final theme = Theme.of(context);
    final base =
        theme.inputDecorationTheme.enabledBorder ??
        theme.inputDecorationTheme.border;
    final side = BorderSide(color: theme.colorScheme.primary, width: 1.5);
    return base is OutlineInputBorder
        ? base.copyWith(borderSide: side)
        : base is UnderlineInputBorder
        ? base.copyWith(borderSide: side)
        : OutlineInputBorder(borderSide: side);
  }
}
