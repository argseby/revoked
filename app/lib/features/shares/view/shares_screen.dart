import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/status_colors.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/api_access_sheet.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_screen_header.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/data_table/filter_bar.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';
import 'package:revoked_app/features/shares/store/shares_store.dart';
import 'package:revoked_app/features/shares/view/share_create_sheet.dart';

class SharesScreen extends StatefulWidget {
  final String? filterSlug;

  const SharesScreen({super.key, this.filterSlug});

  @override
  State<SharesScreen> createState() => _SharesScreenState();
}

class _SharesScreenState extends State<SharesScreen> {
  late final TableStore<Link> _table;

  @override
  void initState() {
    super.initState();
    _table = TableStore<Link>(
      getSourceItems: () => Stores.shares.shares.toList(),
      fieldGetters: {
        'label': (l) => l.label,
        'slug': (l) => l.slug,
        'status': (l) => l.status,
        'created': (l) => l.created ?? '',
      },
      defaultSort: 'created_desc',
    );
    if (widget.filterSlug != null) {
      _table.searchQuery = widget.filterSlug!;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.setFilter(_filterButton);
      Stores.shares.loadShares();
      Stores.vault.loadRecords();
      Stores.identities.loadIdentities();
    });
  }

  @override
  void dispose() {
    ShellSlots.clearFilter(_filterButton);
    _table.dispose();
    super.dispose();
  }

  Widget _filterButton(BuildContext context) {
    return FilterButton<Link>(
      controller: _table,
      columns: const [
        DataTableColumn(value: 'label', label: 'Label'),
        DataTableColumn(value: 'slug', label: 'Slug'),
        DataTableColumn(value: 'status', label: 'Status'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.shares;

    final outerPad = AppSpacing.screenH(context);
    final scrollbarMargin = AppSpacing.scrollbarMargin(context);
    final innerPad = outerPad - scrollbarMargin;
    final horizontalPad = EdgeInsets.symmetric(horizontal: outerPad);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: horizontalPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSpacing.gapMd,
              Observer(
                builder: (_) {
                  final count = store.shares.length;
                  return AppScreenHeader(
                    title: 'Share',
                    badgeLabel: '$count ${count == 1 ? 'link' : 'links'}',
                  );
                },
              ),
            ],
          ),
        ),

        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: scrollbarMargin),
            child: Observer(
              builder: (_) {
                if (store.isLoading && store.shares.isEmpty) {
                  return const Center(child: AppSpinner(large: true));
                }

                if (store.errorMessage != null) {
                  return AppLoadError(
                    title: 'Failed to load shares',
                    message: store.errorMessage!,
                    onRetry: store.loadShares,
                  );
                }

                if (store.shares.isEmpty) {
                  return AppEmptyState(
                    icon: AppIcons.share,
                    title: 'No shared links',
                    subtitle: 'Tap + to securely share data from your vault.',
                  );
                }

                if (_table.filteredItems.isEmpty && store.shares.isNotEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxl),
                      child: const Text('No shares match your filters.').muted,
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.only(
                    left: innerPad,
                    right: innerPad,
                    bottom: AppSpacing.huge,
                  ),
                  itemCount: _table.filteredItems.length,
                  itemBuilder: (context, index) {
                    final share = _table.filteredItems[index];
                    return _ShareCard(
                      share: share,
                      onDelete: () => _confirmDelete(context, store, share.id),
                      onPause: () async {
                        await store.updateShare(share.id, {'status': 'paused'});
                      },
                      onActivate: () async {
                        await store.updateShare(share.id, {'status': 'active'});
                      },
                      onRevoke: () => _confirmRevoke(context, store, share),
                      onDuplicate: () => openShareCreateSheet(
                        context: context,
                        initialShare: share,
                      ),
                      onEdit: () => openShareCreateSheet(
                        context: context,
                        editShare: share,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SharesStore store,
    String id,
  ) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete share link',
      message:
          'This public link will stop working immediately. '
          'This action cannot be undone.',
      content: ApiPreview(
        spec: Stores.shares.deleteShareSpec(id),
        title: 'API request · delete',
      ),
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await store.deleteShare(id);
    if (ok && context.mounted) {
      AppToast.success(context, 'Share link deleted successfully');
    }
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    SharesStore store,
    Link share,
  ) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Revoke share link',
      message:
          'Once a public share link is revoked, it can NEVER be '
          'activated or shared again. Are you sure?',
      content: ApiPreview(
        spec: Stores.shares.updateShareSpec(share.id, const {
          'status': 'revoked',
        }),
        title: 'API request · revoke',
      ),
      confirmLabel: 'Revoke permanently',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await store.updateShare(share.id, {'status': 'revoked'});
    if (ok && context.mounted) {
      AppToast.success(context, 'Share link permanently revoked');
    }
  }
}

class _ShareCard extends StatelessWidget {
  final Link share;
  final VoidCallback onDelete;
  final VoidCallback onPause;
  final VoidCallback onActivate;
  final VoidCallback onRevoke;
  final VoidCallback onDuplicate;
  final VoidCallback onEdit;

  const _ShareCard({
    required this.share,
    required this.onDelete,
    required this.onPause,
    required this.onActivate,
    required this.onRevoke,
    required this.onDuplicate,
    required this.onEdit,
  });

  List<AppSheetAction> _shareActions(BuildContext context) {
    final isActive = share.status == 'active';
    final isPaused = share.status == 'paused';
    final isRevoked = share.status == 'revoked';

    return [
      if (!isRevoked)
        AppSheetAction(
          icon: AppIcons.plusSlashMinus,
          label: 'Add or remove records',
          primary: true,
          onTap: () => context.go('${AppRoutes.vault}?editShareId=${share.id}'),
        ),
      AppSheetAction(
        icon: AppIcons.share,
        label: 'Share',
        enabled: isActive,
        onTap: () => showShareSheet(
          context: context,
          slug: share.slug,
          title: share.label,
          isRequest: false,
          apiTarget: _apiTarget(),
        ),
      ),
      AppSheetAction(
        icon: AppIcons.funnel,
        label: 'Filter by shared records',
        onTap: () => context.go('${AppRoutes.vault}?shareFilterId=${share.id}'),
      ),

      AppSheetAction(icon: AppIcons.pencil, label: 'Edit', onTap: onEdit),
      AppSheetAction(
        icon: AppIcons.nodePlus,
        label: 'Duplicate',
        onTap: onDuplicate,
      ),
      if (isActive)
        AppSheetAction(icon: AppIcons.pause, label: 'Pause', onTap: onPause)
      else if (isPaused)
        AppSheetAction(
          icon: AppIcons.play,
          label: 'Activate',
          onTap: onActivate,
        ),
      if (!isRevoked)
        AppSheetAction(
          icon: AppIcons.xCircle,
          label: 'Revoke',
          destructive: true,
          onTap: onRevoke,
        ),
      AppSheetAction(
        icon: AppIcons.trash,
        label: 'Delete',
        destructive: true,
        onTap: onDelete,
      ),
    ];
  }

  /// Opens the Web & API access drawer for this share — pick a format and copy
  /// a ready-to-use `/s/{slug}` endpoint. The data stays behind the same
  /// revocation as everywhere else; this just exposes where to fetch it.
  ApiAccessTarget _apiTarget() => ApiAccessTarget(
    slug: share.slug,
    title: share.label,
    intro:
        'Use this share\'s live data anywhere — pick a format and copy a '
        'ready-to-use endpoint.',
    gated: share.hasPassword,
    requireHandshake: share.requireHandshake,
    keys: _sharedKeys(),
  );

  /// The record keys this share exposes (direct records + records inside its
  /// shared sections), resolved against the loaded vault for the key dropdown.
  List<String> _sharedKeys() {
    final vault = Stores.vault;
    final ids = <String>{...share.records};
    for (final secId in share.sections) {
      for (final sec in vault.sections) {
        if (sec.id == secId) ids.addAll(sec.records);
      }
    }
    final keys = <String>[];
    for (final r in vault.records) {
      if (ids.contains(r.id) && !keys.contains(r.key)) keys.add(r.key);
    }
    return keys;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppEntityCard(
      icon: AppIcons.link,
      title: share.label,
      subtitle: share.slug,
      subtitleMono: true,
      date: AppEntityCard.formatDate(share.created),
      tags: _tags(theme),
      actions: _shareActions(context),
    );
  }

  List<Widget> _tags(ThemeData theme) {
    final out = <Widget>[
      AppBadge(
        label: StatusColors.displayLabel(share.status),
        accent: StatusColors.foreground(theme, share.status),
      ),
      AppBadge(
        icon: AppIcons.eye,
        label: share.maxViews > 0
            ? '${share.viewCount}/${share.maxViews} views'
            : '${share.viewCount} views',
      ),
    ];
    if (share.isFromRequest) {
      out.add(const AppBadge(icon: AppIcons.inboxFill, label: 'From request'));
    }
    if (share.hasPassword) {
      out.add(const AppBadge(icon: AppIcons.lock, label: 'Password'));
    }
    if (share.expiresAt != null) {
      final d = AppEntityCard.formatDate(share.expiresAt);
      out.add(
        AppBadge(
          icon: AppIcons.clock,
          label: d == null ? 'Expires' : 'Expires $d',
        ),
      );
    }
    if (share.requireHandshake) {
      out.add(const AppBadge(icon: AppIcons.shieldCheck, label: 'Handshake'));
    }
    out.add(
      AppBadge(
        icon: AppIcons.folder,
        label: '${share.sections.length} sections',
      ),
    );
    out.add(
      AppBadge(
        icon: AppIcons.cardList,
        label: '${share.records.length} records',
      ),
    );
    return out;
  }
}
