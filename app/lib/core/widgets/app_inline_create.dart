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

/// What opens a create form, for the page to place: [header] on the right of
/// the list's group header, [button] in its empty state.
class AppCreateTrigger {
  final String label;
  final VoidCallback open;

  const AppCreateTrigger._(this.label, this.open);

  /// Says only "New": the group title beside it names what is created, and
  /// the full label would break the title on a small phone.
  Widget get header => AppButton(
    icon: AppIcons.plus,
    label: 'New',
    tooltip: label,
    style: AppButtonStyle.accent,
    size: AppButtonSize.small,
    onTap: open,
  );

  Widget get button => AppButton(
    icon: AppIcons.plus,
    label: label,
    style: AppButtonStyle.accent,
    onTap: open,
  );
}

enum _Stage { closed, choosing, form }

/// Creating on the page itself, never in a drawer: the trigger sits in the
/// header of the list the new item joins, and the form unfolds above that
/// list.
class AppInlineCreate extends StatefulWidget {
  /// What the trigger says, such as "New API key".
  final String label;

  /// Starting points offered first; each one opens the form.
  final List<AppCreateStart> starts;

  /// Runs before the form opens, to clear what was typed last time.
  final VoidCallback? onOpen;

  /// The form, given how to close it once it has created something or the
  /// person cancelled.
  final Widget Function(VoidCallback close) form;

  /// The list the new item joins. The trigger is null while the form is open,
  /// so the header goes back to its count.
  final Widget Function(AppCreateTrigger? trigger) builder;

  const AppInlineCreate({
    super.key,
    required this.label,
    required this.form,
    required this.builder,
    this.starts = const [],
    this.onOpen,
  });

  @override
  State<AppInlineCreate> createState() => _AppInlineCreateState();
}

class _AppInlineCreateState extends State<AppInlineCreate> {
  final _stage = Local<_Stage>(_Stage.closed);
  final _frame = GlobalKey();

  void _open() {
    if (widget.starts.isEmpty) {
      _showForm();
    } else {
      _stage.value = _Stage.choosing;
      _reveal();
    }
  }

  void _showForm([AppCreateStart? start]) {
    widget.onOpen?.call();
    start?.apply();
    _stage.value = _Stage.form;
    _reveal();
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _frame.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx);
      }
    });
  }

  void _close() => _stage.value = _Stage.closed;

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final stage = _stage.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stage == _Stage.form) ...[
              _formFrame(context),
              AppSpacing.gapLg,
            ] else if (stage == _Stage.choosing) ...[
              KeyedSubtree(key: _frame, child: _starts()),
              AppSpacing.gapLg,
            ],
            widget.builder(
              stage == _Stage.closed
                  ? AppCreateTrigger._(widget.label, _open)
                  : null,
            ),
          ],
        );
      },
    );
  }

  Widget _formFrame(BuildContext context) {
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

  Widget _starts() {
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
                    child: _StartCard(start: s, onTap: () => _showForm(s)),
                  ),
              ],
            );
          },
        ),
        AppSpacing.gapSm,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            label: 'Cancel',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: _close,
          ),
        ),
      ],
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
