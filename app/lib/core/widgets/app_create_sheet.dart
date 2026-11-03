import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';

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

/// Opens a create form in the side panel (a bottom sheet on a phone): the one
/// way a page creates something. With [starts], the panel offers those first
/// and opens the form on the one picked.
///
/// [onOpen] clears what was typed last time; it runs before a start applies,
/// so the start's choices survive. [form] is given how to close the panel.
Future<void> showAppCreateSheet(
  BuildContext context, {
  required String label,
  required Widget Function(VoidCallback close) form,
  List<AppCreateStart> starts = const [],
  VoidCallback? onOpen,
}) {
  if (starts.isEmpty) onOpen?.call();
  return showAppSheet<void>(
    context: context,
    builder: (sheet) => _CreateFlow(
      label: label,
      starts: starts,
      onOpen: onOpen,
      form: form,
      close: () => Navigator.of(sheet).pop(),
    ),
  );
}

class _CreateFlow extends StatefulWidget {
  final String label;
  final List<AppCreateStart> starts;
  final VoidCallback? onOpen;
  final Widget Function(VoidCallback close) form;
  final VoidCallback close;

  const _CreateFlow({
    required this.label,
    required this.starts,
    required this.onOpen,
    required this.form,
    required this.close,
  });

  @override
  State<_CreateFlow> createState() => _CreateFlowState();
}

class _CreateFlowState extends State<_CreateFlow> {
  late final _choosing = Local<bool>(widget.starts.isNotEmpty);

  void _pick(AppCreateStart start) {
    widget.onOpen?.call();
    start.apply();
    _choosing.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) => SingleChildScrollView(
        child: _choosing.value ? _starts() : widget.form(widget.close),
      ),
    );
  }

  Widget _starts() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xxs,
            AppSpacing.xl,
            AppSpacing.md,
          ),
          child: Text(widget.label).header,
        ),
        const AppDivider(),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in widget.starts) ...[
                _StartCard(start: s, onTap: () => _pick(s)),
                AppSpacing.gapSm,
              ],
              AppSpacing.gapSm,
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppButton(
                  label: 'Cancel',
                  style: AppButtonStyle.accent,
                  onTap: widget.close,
                ),
              ),
            ],
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
