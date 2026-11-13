import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// **Copy key** and **Copy ID** for an item's options, so an integration can
/// address it. [key] is left out for items that have none.
List<AppSheetAction> copyIdActions(
  BuildContext context, {
  required String id,
  String? key,
}) => [
  if (key != null && key.isNotEmpty)
    AppSheetAction(
      icon: AppIcons.copy,
      label: 'Copy key',
      onTap: () => _copy(context, key, 'Key copied'),
    ),
  if (id.isNotEmpty)
    AppSheetAction(
      icon: AppIcons.copy,
      label: 'Copy ID',
      onTap: () => _copy(context, id, 'ID copied'),
    ),
];

Future<void> _copy(BuildContext context, String text, String done) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) AppToast.success(context, done);
}
