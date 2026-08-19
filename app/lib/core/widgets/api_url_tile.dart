import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// A labeled, copyable URL row — used to surface a link/request's public API
/// endpoints (deep link, .json, .html) in detail views.
class ApiUrlTile extends StatelessWidget {
  final String label;
  final String url;

  const ApiUrlTile({super.key, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label).muted.small,
                AppSpacing.gapXxs,
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).mono.small,
              ],
            ),
          ),
          AppSpacing.gapSm,
          AppButton(
            icon: AppIcons.copy,
            style: AppButtonStyle.accent,
            tooltip: 'Copy',
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              AppToast.success(context, 'Copied to clipboard');
            },
          ),
        ],
      ),
    );
  }
}
