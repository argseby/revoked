import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_composer.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';

/// Space for a persistent section rail and a readable editor, without widening
/// every other sheet in the app.
const vaultComposerWidth = 652.0;

class VaultComposerHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onClose;
  final String area;
  final IconData areaIcon;

  const VaultComposerHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onClose,
    this.area = 'Vault',
    this.areaIcon = AppIcons.collection,
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
                  Icon(areaIcon, size: 16),
                  AppSpacing.gapXs,
                  Flexible(
                    child: Text(
                      area,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).small.muted,
                  ),
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

/// The record's type, as a grid of choices inside the form. It is a value of
/// the record, so it sits with the other fields rather than in the rail.
class RecordTypePicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String>? onPicked;

  const RecordTypePicker({
    super.key,
    required this.selected,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) => RecordComposerField(
    label: 'Type',
    explanation: 'Decides how the value is entered and shown.',
    child: LayoutBuilder(
      builder: (context, box) {
        final scale =
            MediaQuery.textScalerOf(context).scale(AppTextSize.body) /
            AppTextSize.body;
        final columns = box.maxWidth < 280 * scale
            ? 2
            : box.maxWidth < 420 * scale
            ? 3
            : 4;
        final width = (box.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          key: const ValueKey('record-type-picker'),
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final type in RecordTypeUtils.supportedTypes)
              SizedBox(width: width, child: _choice(context, type)),
          ],
        );
      },
    ),
  );

  Widget _choice(BuildContext context, String type) {
    final scheme = Theme.of(context).colorScheme;
    final active = type == selected;
    final foreground = active ? scheme.onPrimary : scheme.onSurfaceVariant;
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
                child: Column(
                  children: [
                    Icon(
                      RecordTypeUtils.icon(type),
                      size: 18,
                      color: foreground,
                    ),
                    AppSpacing.gapXs,
                    Text(
                      RecordTypeUtils.label(type),
                      textAlign: TextAlign.center,
                    ).small,
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

/// A record field as a composer card; the inline control sits beside the
/// title, leaving the input itself uncluttered.
class RecordComposerField extends StatelessWidget {
  final String label;
  final Widget child;
  final Widget? trailing;
  final String? error;
  final String? explanation;
  final bool missing;

  const RecordComposerField({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
    this.error,
    this.explanation,
    this.missing = false,
  });

  @override
  Widget build(BuildContext context) => AppComposerField(
    label: label,
    explanation: explanation,
    trailing: trailing,
    error: error,
    missing: missing,
    child: child,
  );
}
