import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/state/local.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';

/// Space for a persistent type rail and a readable editor, without widening
/// every other sheet in the app.
const vaultComposerWidth = 652.0;

class VaultComposerHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onClose;

  const VaultComposerHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xxl,
      AppSpacing.xxs,
      AppSpacing.xl,
      AppSpacing.xl,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(AppIcons.collection, size: 16),
                  AppSpacing.gapXs,
                  const Text('Vault').small.muted,
                  const Icon(AppIcons.chevronRight, size: 16),
                  const Text('New').small.muted,
                ],
              ),
              AppSpacing.gapMd,
              Text(title).title,
              AppSpacing.gapXs,
              Text(subtitle).small.muted,
            ],
          ),
        ),
        AppSpacing.gapSm,
        AppButton(
          icon: AppIcons.x,
          tooltip: 'Close',
          style: AppButtonStyle.ghost,
          onTap: onClose,
        ),
      ],
    ),
  );
}

/// The editor scrolls independently beside the desktop rail. On narrow panes
/// (or with larger text), the same choices become a grid above the editor.
class RecordComposerLayout extends StatelessWidget {
  final String selectedType;
  final ValueChanged<String> onTypePicked;
  final List<Widget> children;
  final bool enabled;

  const RecordComposerLayout({
    super.key,
    required this.selectedType,
    required this.onTypePicked,
    required this.children,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale =
          MediaQuery.textScalerOf(context).scale(AppTextSize.body) /
          AppTextSize.body;
      final split = box.maxWidth >= AppSpacing.narrowWidth * scale;
      final picker = _RecordTypePicker(
        selected: selectedType,
        onPicked: enabled ? onTypePicked : null,
        rail: split,
      );
      final editor = ListView(
        key: const PageStorageKey('record-composer-editor'),
        padding: const EdgeInsets.all(AppSpacing.xxl),
        children: [
          if (!split) ...[picker, AppSpacing.gapXxl],
          for (final child in children) ...[child, AppSpacing.gapXl],
        ],
      );
      if (!split) return editor;
      final scheme = Theme.of(context).colorScheme;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('record-type-rail'),
            width: 168,
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              border: BorderDirectional(
                end: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xxl,
              ),
              children: [picker],
            ),
          ),
          Expanded(child: editor),
        ],
      );
    },
  );
}

class _RecordTypePicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String>? onPicked;
  final bool rail;

  const _RecordTypePicker({
    required this.selected,
    required this.onPicked,
    required this.rail,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTarget),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: const AppText('Record type').bold,
        ),
      ),
      AppSpacing.gapSm,
      if (rail)
        for (final type in RecordTypeUtils.supportedTypes) ...[
          _choice(context, type, stacked: false),
          AppSpacing.gapXxs,
        ]
      else
        LayoutBuilder(
          builder: (context, box) {
            final scale =
                MediaQuery.textScalerOf(context).scale(AppTextSize.body) /
                AppTextSize.body;
            final columns = box.maxWidth < 280 * scale ? 2 : 3;
            final width =
                (box.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final type in RecordTypeUtils.supportedTypes)
                  SizedBox(
                    width: width,
                    child: _choice(context, type, stacked: true),
                  ),
              ],
            );
          },
        ),
    ],
  );

  Widget _choice(BuildContext context, String type, {required bool stacked}) {
    final scheme = Theme.of(context).colorScheme;
    final active = type == selected;
    final foreground = active ? scheme.onPrimary : scheme.onSurfaceVariant;
    final icon = Icon(RecordTypeUtils.icon(type), size: 18, color: foreground);
    final label = Text(
      RecordTypeUtils.label(type),
      textAlign: stacked ? TextAlign.center : TextAlign.start,
    ).small;
    return Semantics(
      selected: active,
      button: true,
      child: Material(
        color: active ? scheme.primary : scheme.surfaceContainer,
        borderRadius: AppRadius.allMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: AppRadius.allMd,
          onTap: onPicked == null ? null : () => onPicked!(type),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTarget),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: foreground),
                child: stacked
                    ? Column(children: [icon, AppSpacing.gapXs, label])
                    : Row(
                        children: [
                          icon,
                          AppSpacing.gapSm,
                          Expanded(child: label),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Common heading rhythm for the composer's inputs. An inline control sits
/// beside the heading, leaving the input itself uncluttered.
class RecordComposerField extends StatelessWidget {
  final String label;
  final Widget child;
  final Widget? trailing;
  final String? error;

  const RecordComposerField({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
    this.error,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTarget),
        child: Row(
          children: [
            Expanded(child: AppText(label).bold),
            if (trailing != null) ...[AppSpacing.gapSm, trailing!],
          ],
        ),
      ),
      AppSpacing.gapSm,
      child,
      if (error != null) ...[AppSpacing.gapXs, AppErrorText(error!)],
    ],
  );
}

/// A setting exposes its saved state even while its controls are collapsed.
class RecordComposerDisclosure extends StatefulWidget {
  final String title;
  final String summary;
  final IconData icon;
  final Widget child;
  final bool initiallyOpen;
  final bool enabled;

  const RecordComposerDisclosure({
    super.key,
    required this.title,
    required this.summary,
    required this.icon,
    required this.child,
    this.initiallyOpen = false,
    this.enabled = true,
  });

  @override
  State<RecordComposerDisclosure> createState() =>
      _RecordComposerDisclosureState();
}

class _RecordComposerDisclosureState extends State<RecordComposerDisclosure> {
  late final Local<bool> _open = Local(widget.initiallyOpen);

  @override
  void didUpdateWidget(RecordComposerDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyOpen && !oldWidget.initiallyOpen) _open.value = true;
  }

  @override
  Widget build(BuildContext context) =>
      Observer(builder: (_) => _build(context));

  Widget _build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        expanded: _open.value,
        child: ListTile(
          enabled: widget.enabled,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          leading: Icon(widget.icon, size: 20),
          title: Text(widget.title).small.bold,
          subtitle: Text(widget.summary).small.muted,
          trailing: Icon(
            _open.value ? AppIcons.chevronUp : AppIcons.chevronDown,
            size: 20,
          ),
          onTap: widget.enabled ? () => _open.value = !_open.value : null,
        ),
      ),
      // Keep controls mounted so collapsing a setting retains focus state and
      // selections. Offstage excludes them from keyboard and semantics traversal.
      Offstage(
        offstage: !_open.value,
        child: ExcludeFocus(
          excluding: !_open.value,
          child: TickerMode(
            enabled: _open.value,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    ],
  );
}
