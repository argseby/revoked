import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_key_hint.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/features/shell/utils/new_actions.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';

/// The shell's one create action: a grouped list of everything that can be
/// made, each with a sentence on what it is. A dialog on a wide window, a
/// sheet on a phone. Picking a row opens the form that already exists for it.
Future<void> openNewPicker(BuildContext context, {int? destination}) async {
  final first = NewKind.firstFor(destination);
  final NewKind? picked;
  if (AppSpacing.isNarrow(context)) {
    picked = await showAppSheet<NewKind>(
      context: context,
      builder: (sheetCtx) => NewPickerList(
        first: first,
        onPick: (kind) => Navigator.of(sheetCtx).pop(kind),
      ),
    );
  } else {
    picked = await showDialog<NewKind>(
      context: context,
      builder: (dialogCtx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: NewPickerList(
            first: first,
            onPick: (kind) => Navigator.of(dialogCtx).pop(kind),
          ),
        ),
      ),
    );
  }
  if (picked == null || !context.mounted) return;
  await startNew(context, picked);
}

/// The picker's body: a title, then the rows under their group names. Arrow
/// keys move between rows, Enter picks, and each row's letter picks it
/// directly.
class NewPickerList extends StatelessWidget {
  final NewKind first;
  final ValueChanged<NewKind> onPick;

  const NewPickerList({super.key, required this.first, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        for (final kind in NewKind.values)
          CharacterActivator(kind.key): () => onPick(kind),
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Semantics(
                header: true,
                child: const Text('Create something new').header,
              ),
            ),
            for (final group in NewGroup.values) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.xxs,
                ),
                child: Semantics(
                  header: true,
                  child: Text(group.title).small.muted,
                ),
              ),
              for (final kind in NewKind.values)
                if (kind.group == group)
                  _PickerRow(
                    kind: kind,
                    autofocus: kind == first,
                    onTap: () => onPick(kind),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final NewKind kind;
  final bool autofocus;
  final VoidCallback onTap;

  const _PickerRow({
    required this.kind,
    required this.autofocus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: kind.label,
      hint: kind.description,
      excludeSemantics: true,
      child: AppFocusRing(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            autofocus: autofocus,
            onTap: onTap,
            borderRadius: AppRadius.allMd,
            focusColor: scheme.secondaryContainer,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(kind.icon, size: 22),
                    AppSpacing.gapMd,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppText(kind.label).bold,
                          AppText(kind.description).small.muted,
                        ],
                      ),
                    ),
                    AppSpacing.gapSm,
                    AppKeyHint(kind.key.toUpperCase()),
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
