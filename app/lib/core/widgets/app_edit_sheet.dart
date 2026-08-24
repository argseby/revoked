import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';

/// Opens a focused sub-sheet that edits a single text [controller], with a
/// title, optional description, the field, and a Done button. Used by the
/// create drawers when a summary row is tapped.
///
/// Resolves true when Done was pressed and false when the sheet was
/// dismissed, so a caller that writes the value on the way out can tell a
/// save from a cancel.
Future<bool> showAppEditSheet({
  required BuildContext context,
  required String title,
  required TextEditingController controller,
  String? description,
  String? hint,
  bool passwordToggle = false,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  int maxLines = 1,
  String doneLabel = 'Done',
}) {
  return showAppSheet<bool>(
    context: context,
    builder: (sheetCtx) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title).header,
          if (description != null) ...[
            AppSpacing.gapXxs,
            Text(description).muted.small,
          ],
          AppSpacing.gapLg,
          AppTextField(
            controller: controller,
            hint: hint,
            passwordToggle: passwordToggle,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            maxLines: maxLines,
            autofocus: true,
            onSubmitted: maxLines == 1
                ? (_) => Navigator.of(sheetCtx).pop(true)
                : null,
          ),
          AppSpacing.gapLg,
          AppButton(
            icon: AppIcons.check,
            label: doneLabel,
            onTap: () => Navigator.of(sheetCtx).pop(true),
          ),
        ],
      ),
    ),
  ).then((done) => done ?? false);
}
