import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/widgets/app_animated_size.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';

/// A value chosen rather than typed — from a list, a calendar, a switch —
/// drawn in the same frame as a text field, so a form's inputs line up. Goes
/// inside an [AppFormField], which carries its label.
class AppPickerField extends StatelessWidget {
  /// The current choice, or what to choose when [isPlaceholder].
  final String text;
  final bool isPlaceholder;
  final VoidCallback onTap;
  final IconData? leading;

  /// What tapping opens: [AppIcons.chevronDown] for a list, a calendar for a
  /// date. Null when the field changes in place, as a switch does.
  final IconData? opens;

  /// Shown once a value is set, for a field that may be left empty.
  final VoidCallback? onClear;

  /// Controls acting on the value in place, such as a switch.
  final List<Widget> trailing;

  const AppPickerField({
    super.key,
    required this.text,
    required this.onTap,
    this.isPlaceholder = false,
    this.leading,
    this.opens = AppIcons.chevronDown,
    this.onClear,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.allMd,
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: leading == null ? null : Icon(leading),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onClear != null && !isPlaceholder)
                AppButton(
                  icon: AppIcons.x,
                  style: AppButtonStyle.ghost,
                  size: AppButtonSize.small,
                  tooltip: 'Clear',
                  showTooltip: false,
                  onTap: onClear,
                ),
              ...trailing,
              if (opens != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Icon(opens, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: isPlaceholder
              ? TextStyle(color: scheme.onSurfaceVariant)
              : null,
        ),
      ),
    );
  }
}

/// A field filled in where it stands: its label, the input, and under it
/// whatever is wrong with the value, else a note. Anything typed belongs here
/// rather than behind a row that opens a sheet to type in, which costs a tap
/// to open and one to close. A choice from a list is an [AppPickerField].
class AppFormField extends StatelessWidget {
  final String label;

  /// The input: an `AppTextField`, a switch row, a file picker.
  final Widget child;

  /// What the field is for, under the label.
  final String? explanation;

  /// Replaces [note] while the value is wrong.
  final String? error;

  /// Under the input, such as what an empty field falls back to.
  final String? note;

  /// Under the input, after the error or note: "Use suggested: …".
  final Widget? action;

  /// Lines the field up with a create drawer's rows. Off inside a form that
  /// already pads its fields.
  final bool inset;

  const AppFormField({
    super.key,
    required this.label,
    required this.child,
    this.explanation,
    this.error,
    this.note,
    this.action,
    this.inset = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: inset
          ? const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.sm,
            )
          : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label),
          if (explanation != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(explanation!).muted.small,
          ],
          const SizedBox(height: AppSpacing.xs),
          child,
          if (error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppErrorText(error!),
          ] else if (note != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(note!).muted.small,
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(alignment: Alignment.centerLeft, child: action),
          ],
        ],
      ),
    );
  }
}

/// A boolean setting rendered as a row with a trailing switch — no sub-sheet.
/// The app's only labelled toggle.
class AppFormToggleRow extends StatelessWidget {
  /// Omitted for a toggle inside already-labelled content, where a second
  /// glyph would just be noise.
  final IconData? icon;

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// A short tag after the label, such as "Alpha" on a feature still settling.
  final String? badge;

  /// Aligns the row with a create drawer's other rows. Off when the toggle
  /// sits inside a container that already provides the padding.
  final bool inset;

  /// The row's own inner padding, in place of [inset], for a row inside a
  /// group: the hover then reaches the group's edges, as its other rows do.
  final EdgeInsetsGeometry? padding;

  const AppFormToggleRow({
    super.key,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
    this.badge,
    this.inset = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding:
          padding ??
          (inset
              ? const EdgeInsets.symmetric(horizontal: AppSpacing.xl)
              : EdgeInsets.zero),
      leading: icon == null ? null : Icon(icon, color: scheme.onSurfaceVariant),
      title: badge == null
          ? Text(label)
          : Row(
              children: [
                Flexible(child: Text(label)),
                AppSpacing.gapSm,
                AppBadge(label: badge!, variant: AppBadgeVariant.experimental),
              ],
            ),
      subtitle: Text(subtitle).muted.small,
      trailing: AppSwitch(value: value, onChanged: onChanged),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}

/// A small uppercase section label grouping rows within a create drawer.
class AppFormSectionHeader extends StatelessWidget {
  final String text;
  const AppFormSectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxs,
      ),
      child: Text(text).small.bold.muted,
    );
  }
}

/// The fields a create drawer does not need for the common case — keys,
/// slugs, limits, the API preview — folded behind one row, so the form opens
/// with only what most people fill in.
///
/// [summary] says what is inside ("Key, API preview"), so nobody has to open
/// it to find out. Starts closed unless [initiallyOpen], which a form passes
/// when something inside needs attention.
class AppFormAdvanced extends StatefulWidget {
  final String summary;
  final List<Widget> children;
  final bool initiallyOpen;

  const AppFormAdvanced({
    super.key,
    required this.summary,
    required this.children,
    this.initiallyOpen = false,
  });

  @override
  State<AppFormAdvanced> createState() => _AppFormAdvancedState();
}

class _AppFormAdvancedState extends State<AppFormAdvanced> {
  late final Local<bool> _open = Local(widget.initiallyOpen);

  @override
  Widget build(BuildContext context) {
    return Observer(builder: _build);
  }

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = _open.value;
    return AppAnimatedSize(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
            ),
            leading: Icon(AppIcons.sliders, color: scheme.onSurfaceVariant),
            title: const Text('Advanced'),
            subtitle: Text(widget.summary).muted.small,
            trailing: Icon(
              open ? AppIcons.chevronUp : AppIcons.chevronDown,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            onTap: () => _open.value = !open,
          ),
          if (open) ...widget.children,
        ],
      ),
    );
  }
}
