import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';

/// Opens a focused sub-sheet that edits a single text [controller], with a
/// title, optional description, the field, and a Done button. Used by the
/// create drawers when a summary row is tapped. The caller should `setState`
/// after this future completes to refresh the row's summary.
Future<void> showAppEditSheet({
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
  return showAppSheet<void>(
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
                ? (_) => Navigator.of(sheetCtx).pop()
                : null,
          ),
          AppSpacing.gapLg,
          AppButton(
            label: doneLabel,
            onTap: () => Navigator.of(sheetCtx).pop(),
          ),
        ],
      ),
    ),
  );
}
