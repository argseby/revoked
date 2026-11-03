import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';

/// A ready-made beginning for something new: picking it fills the form in.
class AppCreateStart {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback apply;

  const AppCreateStart({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.apply,
  });
}

/// Creating on the page itself, never in a drawer: a button, or a few
/// starting points, that unfold the form right where the new item will be
/// listed.
class AppInlineCreate extends StatefulWidget {
  /// What the button says, such as "New API key".
  final String label;

  /// Starting points shown instead of the button; each one opens the form.
  final List<AppCreateStart> starts;

  /// Runs before the form opens, to clear what was typed last time.
  final VoidCallback? onOpen;

  /// The form, given how to close it once it has created something or the
  /// person cancelled.
  final Widget Function(VoidCallback close) form;

  const AppInlineCreate({
    super.key,
    required this.label,
    required this.form,
    this.starts = const [],
    this.onOpen,
  });

  @override
  State<AppInlineCreate> createState() => _AppInlineCreateState();
}

class _AppInlineCreateState extends State<AppInlineCreate> {
  final _open = Local<bool>(false);
  final _frame = GlobalKey();

  void _show([AppCreateStart? start]) {
    widget.onOpen?.call();
    start?.apply();
    _open.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _frame.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx);
      }
    });
  }

  void _close() => _open.value = false;

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        if (_open.value) {
          final scheme = Theme.of(context).colorScheme;
          return Container(
            key: _frame,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(color: scheme.onSurface),
              borderRadius: AppRadius.allLg,
            ),
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: widget.form(_close),
          );
        }
        if (widget.starts.isEmpty) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              icon: AppIcons.plus,
              label: widget.label,
              style: AppButtonStyle.accent,
              onTap: _show,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.label).small.muted,
            AppSpacing.gapXs,
            LayoutBuilder(
              builder: (context, box) {
                final columns = (box.maxWidth ~/ 180).clamp(
                  1,
                  widget.starts.length,
                );
                final width =
                    (box.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final s in widget.starts)
                      SizedBox(
                        width: width,
                        child: _StartCard(start: s, onTap: () => _show(s)),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _StartCard extends StatelessWidget {
  final AppCreateStart start;
  final VoidCallback onTap;

  const _StartCard({required this.start, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(start.icon, size: 16, color: scheme.onSurface),
                AppSpacing.gapSm,
                Expanded(child: Text(start.label)),
              ],
            ),
            AppSpacing.gapXxs,
            Text(start.subtitle).small.muted,
          ],
        ),
      ),
    );
  }
}
