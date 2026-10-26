import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/features/shares/utils/recipients.dart';

/// One recipient and what they hold. Opens their link, or the Links list
/// narrowed to their name when they hold several.
class RecipientRow extends StatelessWidget {
  final List<Link> links;

  const RecipientRow(this.links, {super.key});

  @override
  Widget build(BuildContext context) {
    final name = links.first.label.trim();
    return AppListRow(
      icon: AppIcons.person,
      title: name.isEmpty ? 'Unnamed link' : name,
      subtitle: recipientSummary(links),
      trailing: StatusLabel(recipientStatus(links)),
      onTap: () => context.go(
        links.length == 1
            ? AppRoutes.shareDetailFor(links.first.id)
            : '${AppRoutes.shared}?filterSlug='
                  '${Uri.encodeQueryComponent(name)}',
      ),
    );
  }
}
