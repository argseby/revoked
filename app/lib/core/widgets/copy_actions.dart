import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// Copies the id the API addresses an item by. An item's key is a field of
/// its data, never an address, so only the id is offered.
AppSheetAction copyIdAction(BuildContext context, String id) => AppSheetAction(
  icon: AppIcons.copy,
  label: 'Copy ID (API)',
  onTap: () async {
    await Clipboard.setData(ClipboardData(text: id));
    if (context.mounted) AppToast.success(context, 'ID copied');
  },
);
