import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/features/shares/utils/record_access.dart';

/// Who has which of the owner's data: every vault record someone else can
/// read right now, with how many open links, request answers and tools
/// reach it. A record opens its own page, which lists them and revokes them.
///
/// Loads what it is built from when nothing is loaded yet, so it can stand on
/// the Overview as well as under Shared.
class AccessOverview extends StatefulWidget {
  const AccessOverview({super.key});

  @override
  State<AccessOverview> createState() => _AccessOverviewState();
}

class _AccessOverviewState extends State<AccessOverview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Stores.shares.shares.isEmpty) Stores.shares.loadShares();
      if (Stores.vault.records.isEmpty) Stores.vault.loadRecords();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final shares = Stores.shares;
        final vault = Stores.vault;
        if ((shares.isLoading && shares.shares.isEmpty) ||
            (vault.isLoading && vault.records.isEmpty)) {
          return const Center(child: AppSpinner(large: true));
        }

        final rows = openAccessByRecord(
          links: shares.shares,
          sections: vault.sections,
          records: vault.records,
        );
        if (rows.isEmpty) {
          return const AppEmptyState(
            icon: AppIcons.lock,
            title: 'Nobody else can read your data',
            subtitle:
                'No open link, request answer or connected tool carries a '
                'vault record right now.',
          );
        }

        final linkIds = {
          for (final (_, access) in rows)
            for (final a in access) a.link.id,
        };
        return AppListPage(
          groups: [
            AppListGroup(
              title: 'Readable by others',
              footer: Text(
                '${rows.length} ${rows.length == 1 ? 'record is' : 'records are'} '
                'readable through ${linkIds.length} open '
                '${linkIds.length == 1 ? 'link' : 'links'}. A record opens '
                'the list of who reads it, where it can be revoked.',
              ).muted.small,
              children: [
                for (final (record, access) in rows)
                  AppListRow(
                    icon: record.isFile ? AppIcons.fileEarmark : AppIcons.key,
                    title: record.label.isEmpty ? record.key : record.label,
                    subtitle: _breakdown(access),
                    trailing: AppBadge(
                      label: '${access.length}',
                      variant: AppBadgeVariant.outline,
                    ),
                    onTap: () =>
                        context.go(AppRoutes.recordDetailFor(record.id)),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// "2 links · 1 request answer".
  static String _breakdown(List<RecordAccess> access) {
    String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final links = access.where((a) => a.kind == AccessKind.link).length;
    final answers = access
        .where((a) => a.kind == AccessKind.requestAnswer)
        .length;
    final tools = access.where((a) => a.kind == AccessKind.tool).length;
    return [
      if (links > 0) count(links, 'link', 'links'),
      if (answers > 0) count(answers, 'request answer', 'request answers'),
      if (tools > 0) count(tools, 'connected tool', 'connected tools'),
    ].join(' · ');
  }
}
