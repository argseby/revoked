import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/refresh_on_entry.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
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

class _AccessOverviewState extends State<AccessOverview> with RefreshOnEntry {
  @override
  void refresh() {
    Stores.shares.loadIfDue();
    Stores.vault.loadIfDue();
  }

  @override
  Widget build(BuildContext context) {
    final shares = Stores.shares;
    final vault = Stores.vault;
    return AppLoadFade(
      loading: () =>
          (shares.loadState.isFirstLoad && shares.shares.isEmpty) ||
          (vault.loadState.isFirstLoad && vault.records.isEmpty),
      skeleton: const AppListSkeleton(
        group: 'Shared with others',
        rows: [
          AppSkeletonRow('IBAN', 'Readable by 2 people', icon: AppIcons.lock),
          AppSkeletonRow(
            'Home address',
            'Readable by 1 person',
            icon: AppIcons.lock,
          ),
        ],
      ),
      builder: (context) {
        final rows = openAccessByRecord(
          links: shares.shares,
          sections: vault.sections,
          records: vault.records,
        );
        if (rows.isEmpty) {
          return AppEmptyState(
            icon: AppIcons.lock,
            title: 'No shared records',
            subtitle:
                'Shared records are listed here with everyone who can read them.',
            example: const AppEmptyExample(
              title: 'IBAN',
              detail: 'Landlord · Employer',
              badge: '2 links',
            ),
            steps: const [
              AppEmptyStep(
                'One row per record',
                'With every link that shares it',
              ),
              AppEmptyStep(
                'Access per record',
                'Links, request answers and tools',
              ),
              AppEmptyStep('Central revocation', 'Without opening each link'),
            ],
          );
        }

        final linkIds = {
          for (final (_, access) in rows)
            for (final a in access) a.link.id,
        };
        return AppListPage(
          groups: [
            AppListGroup(
              title: 'Shared with others',
              footer: Text(
                '${rows.length} ${rows.length == 1 ? 'record' : 'records'} '
                'readable through ${linkIds.length} open '
                '${linkIds.length == 1 ? 'link' : 'links'}. '
                'Access is reviewed and revoked per record.',
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
