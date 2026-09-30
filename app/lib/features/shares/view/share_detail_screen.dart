import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/api_access_sheet.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';
import 'package:revoked_app/features/shares/view/link_groups.dart';
import 'package:revoked_app/features/shares/view/share_create_sheet.dart';

/// One link, opened from the Links list: what it shares, who can open it, where
/// it came from, and the actions that end it.
class ShareDetailScreen extends StatefulWidget {
  final String shareId;

  const ShareDetailScreen({super.key, required this.shareId});

  @override
  State<ShareDetailScreen> createState() => _ShareDetailScreenState();
}

class _ShareDetailScreenState extends State<ShareDetailScreen> {
  /// Set while a pause, activate, revoke or delete is in flight, so its button
  /// spins and the others cannot fire on top of it.
  final Local<String?> _busy = Local(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.title.claim(_title);
      // Opened straight from a link, the list has not loaded anything yet.
      if (Stores.shares.shares.isEmpty) Stores.shares.loadShares();
      if (Stores.vault.records.isEmpty) Stores.vault.loadRecords();
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    super.dispose();
  }

  Link? get _share {
    for (final s in Stores.shares.shares) {
      if (s.id == widget.shareId) return s;
    }
    return null;
  }

  void _back() => context.go(AppRoutes.data);

  Widget _title(BuildContext context) {
    return AppBarTitle(title: _share?.label ?? 'Link', onBack: _back);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final share = _share;
        if (share == null) {
          if (Stores.shares.isLoading) {
            return const Center(child: AppSpinner(large: true));
          }
          return AppEmptyState(
            icon: AppIcons.linkSlash,
            title: 'Link not found',
            subtitle: 'It may have been deleted.',
            action: AppButton(
              icon: AppIcons.arrowLeft,
              label: 'Back to links',
              style: AppButtonStyle.accent,
              onTap: _back,
            ),
          );
        }

        return AppDetailPage(
          header: _header(context, share),
          sections: [
            _contents(context, share),
            _access(share),
            _origin(share),
            _manage(context, share),
          ],
        );
      },
    );
  }

  AppDetailHeader _header(BuildContext context, Link share) {
    final theme = Theme.of(context);
    final attention = linkAttention(share, DateTime.now());
    final status = share.status;
    final busy = _busy.value != null;

    final Widget primary = switch (status) {
      'active' => AppButton(
        icon: AppIcons.share,
        label: 'Share link',
        onTap: () => showShareSheet(
          context: context,
          slug: share.slug,
          title: share.label,
          isRequest: false,
          apiTarget: _apiTarget(share),
        ),
      ),
      'paused' => AppButton(
        icon: AppIcons.play,
        label: 'Activate',
        busy: _busy.value == 'active',
        onTap: busy ? null : () => _setStatus(share, 'active'),
      ),
      // A revoked link can never open again; a copy of it can.
      _ => AppButton(
        icon: AppIcons.duplicate,
        label: 'Duplicate',
        onTap: () =>
            openShareCreateSheet(context: context, initialShare: share),
      ),
    };

    return AppDetailHeader(
      badges: [
        AppStatusBadge(status),
        if (attention != null)
          AppBadge(
            icon: AppIcons.clock,
            label: attention.reason,
            accent: theme.colorScheme.warning,
          ),
      ],
      title: share.label,
      subtitle: share.slug,
      subtitleMono: true,
      primaryAction: primary,
      secondaryActions: [
        AppButton(
          icon: AppIcons.pencil,
          tooltip: 'Edit',
          style: AppButtonStyle.accent,
          onTap: () => openShareCreateSheet(context: context, editShare: share),
        ),
        if (status == 'active' || status == 'paused')
          AppButton(
            icon: AppIcons.duplicate,
            tooltip: 'Duplicate',
            style: AppButtonStyle.accent,
            onTap: () =>
                openShareCreateSheet(context: context, initialShare: share),
          ),
      ],
    );
  }

  /// What the link hands out, resolved against the vault: every record with
  /// its key and the value a viewer actually sees, filed under the section it
  /// is shared through.
  Widget _contents(BuildContext context, Link share) {
    final vault = Stores.vault;
    final byId = {for (final r in vault.records) r.id: r};
    final rows = <Widget>[];
    final placed = <String>{};

    Widget recordRow(models.Record r, {bool nested = false}) =>
        _SharedRecordRow(
          record: r,
          value: _shownValue(r, byId),
          nested: nested,
          onTap: () => context.go(AppRoutes.recordDetailFor(r.id)),
        );

    for (final id in share.sections) {
      for (final sec in vault.sections) {
        if (sec.id != id) continue;
        final records = [
          for (final rId in sec.records)
            if (byId[rId] != null) byId[rId]!,
        ];
        rows.add(_SharedSectionRow(section: sec, count: records.length));
        for (final r in records) {
          placed.add(r.id);
          rows.add(recordRow(r, nested: true));
        }
      }
    }
    // A shared section's records are also listed on the link itself; show
    // each once, under its section.
    for (final id in share.records) {
      final r = byId[id];
      if (r == null || placed.contains(id)) continue;
      placed.add(id);
      rows.add(recordRow(r));
    }

    final total = share.sections.length + share.records.length;
    if (rows.isEmpty) {
      rows.add(
        AppDetailRow(
          icon: AppIcons.info,
          label: total == 0
              ? 'Nothing selected yet'
              : vault.isLoading
              ? 'Loading…'
              : vault.errorMessage != null
              ? "Couldn't load your vault"
              : '$total items no longer in your vault',
        ),
      );
    }
    rows.add(
      AppDetailRow(
        icon: AppIcons.funnel,
        label: 'Show in vault',
        onTap: () => context.go('${AppRoutes.vault}?shareFilterId=${share.id}'),
      ),
    );

    final count = placed.length;
    return AppListGroup(
      title: "What's shared · $count ${count == 1 ? 'record' : 'records'}",
      previewCount: 12,
      noun: 'records',
      trailing: share.status == 'revoked'
          ? null
          : AppButton(
              icon: AppIcons.plusSlashMinus,
              label: 'Change',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () =>
                  context.go('${AppRoutes.vault}?editShareId=${share.id}'),
            ),
      children: rows,
    );
  }

  /// The value a viewer of the link sees: an alias forwards its parent's, a
  /// file shows its name and size.
  String _shownValue(models.Record r, Map<String, models.Record> byId) {
    if (r.isFile) return '${r.displayName} · ${formatBytes(r.size)}';
    final value = r.isAlias ? (byId[r.aliasOf]?.value ?? '') : r.value;
    return value.isEmpty ? '—' : value;
  }

  Widget _access(Link share) {
    final expires = AppEntityCard.formatDate(share.expiresAt);
    return AppListGroup(
      title: 'Access',
      trailing: const SizedBox.shrink(),
      children: [
        AppDetailRow(
          icon: AppIcons.lock,
          label: 'Password',
          value: share.hasPassword ? 'On' : 'Off',
        ),
        AppDetailRow(
          icon: AppIcons.clock,
          label: 'Expires',
          value: expires ?? 'Never',
        ),
        AppDetailRow(
          icon: AppIcons.eye,
          label: 'Views',
          value: share.maxViews > 0
              ? '${share.viewCount} of ${share.maxViews}'
              : '${share.viewCount}',
        ),
        AppDetailRow(
          icon: AppIcons.shieldCheck,
          label: 'Handshake',
          value: share.requireHandshake ? 'Required' : 'Off',
        ),
        // The text the owner typed is what every stamped copy carries; left
        // empty, the server stamps the link's label instead.
        AppDetailRow(
          icon: AppIcons.watermark,
          label: 'Watermark',
          value: !share.watermark
              ? 'Off'
              : share.watermarkText.trim().isNotEmpty
              ? share.watermarkText.trim()
              : share.label,
        ),
        if (share.watermark)
          AppDetailRow(
            icon: AppIcons.hash,
            label: 'Stamp reference',
            value: '#${share.watermarkTag}',
            valueMono: true,
          ),
      ],
    );
  }

  Widget _origin(Link share) {
    final String origin;
    if (share.isFromTool) {
      origin = 'Proposed by ${share.proposedByHost}';
    } else if (share.isFromRequest) {
      origin = 'Answer to a request';
    } else {
      origin = 'Made in the app';
    }

    return AppListGroup(
      title: 'Details',
      trailing: const SizedBox.shrink(),
      children: [
        AppDetailRow(icon: AppIcons.nodePlus, label: 'Origin', value: origin),
        if (share.ref.isNotEmpty)
          AppDetailRow(
            icon: AppIcons.tag,
            label: 'Reference',
            value: share.ref,
          ),
        if (share.isFromTool)
          AppDetailRow(
            icon: AppIcons.send,
            label: 'Link handed to the tool',
            value: share.handedOver ? 'Yes' : 'No',
          ),
        AppDetailRow(
          icon: AppIcons.plus,
          label: 'Created',
          value: AppEntityCard.formatDate(share.created) ?? '—',
        ),
        AppDetailRow(
          icon: AppIcons.pen,
          label: 'Last changed',
          value: AppEntityCard.formatDate(share.updated) ?? '—',
        ),
      ],
    );
  }

  /// The actions that stop the link, last on the page and apart from the rest.
  Widget _manage(BuildContext context, Link share) {
    final status = share.status;
    final busy = _busy.value;
    final locked = busy != null;

    return AppDetailManage(
      actions: [
        if (status == 'active')
          AppButton(
            icon: AppIcons.pause,
            label: 'Pause',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            busy: busy == 'paused',
            onTap: locked ? null : () => _setStatus(share, 'paused'),
          ),
        if (status != 'revoked')
          AppButton(
            icon: AppIcons.xCircle,
            label: 'Revoke',
            style: AppButtonStyle.destructive,
            size: AppButtonSize.small,
            busy: busy == 'revoked',
            onTap: locked ? null : () => _confirmRevoke(context, share),
          ),
        AppButton(
          icon: AppIcons.trash,
          label: 'Delete',
          style: AppButtonStyle.destructive,
          size: AppButtonSize.small,
          busy: busy == 'delete',
          onTap: locked ? null : () => _confirmDelete(context, share),
        ),
      ],
    );
  }

  Future<void> _setStatus(Link share, String status) async {
    _busy.value = status;
    try {
      await Stores.shares.updateShare(share.id, {'status': status});
    } finally {
      _busy.value = null;
    }
  }

  Future<void> _confirmRevoke(BuildContext context, Link share) async {
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
      confirmIcon: AppIcons.xCircle,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    _busy.value = 'revoked';
    final ok = await Stores.shares.updateShare(share.id, {'status': 'revoked'});
    _busy.value = null;
    if (ok && context.mounted) {
      AppToast.success(context, 'Share link permanently revoked');
    }
  }

  Future<void> _confirmDelete(BuildContext context, Link share) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete share link',
      message:
          'This public link will stop working immediately. '
          'This action cannot be undone.',
      content: ApiPreview(
        spec: Stores.shares.deleteShareSpec(share.id),
        title: 'API request · delete',
      ),
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    _busy.value = 'delete';
    final ok = await Stores.shares.deleteShare(share.id);
    _busy.value = null;
    if (ok && context.mounted) {
      AppToast.success(context, 'Share link deleted successfully');
      _back();
    }
  }

  /// Opens the Web & API access drawer for this share — pick a format and copy
  /// a ready-to-use `/s/{slug}` endpoint. The data stays behind the same
  /// revocation as everywhere else; this just exposes where to fetch it.
  ApiAccessTarget _apiTarget(Link share) => ApiAccessTarget(
    slug: share.slug,
    title: share.label,
    intro:
        'Use this share\'s live data anywhere — pick a format and copy a '
        'ready-to-use endpoint.',
    gated: share.hasPassword,
    requireHandshake: share.requireHandshake,
    keys: _sharedKeys(share),
  );

  /// The record keys this share exposes (direct records + records inside its
  /// shared sections), resolved against the loaded vault for the key dropdown.
  List<String> _sharedKeys(Link share) {
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
}

/// A section a link shares, heading the records it hands out through it.
class _SharedSectionRow extends StatelessWidget {
  final Section section;
  final int count;

  const _SharedSectionRow({required this.section, required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(AppIcons.folder, size: 18, color: scheme.onSurfaceVariant),
          AppSpacing.gapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  section.name.isEmpty ? section.key : section.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).bold,
                AppText(section.key, maxLines: 1).small.muted.mono,
              ],
            ),
          ),
          AppSpacing.gapMd,
          AppText(
            'Section · $count ${count == 1 ? 'record' : 'records'}',
          ).small.muted,
        ],
      ),
    );
  }
}

/// One shared record: its label and key on the left, the value a viewer of
/// the link sees on the right. A hidden value stays masked until the eye is
/// tapped; the row itself opens the record.
class _SharedRecordRow extends StatelessWidget {
  final models.Record record;
  final String value;

  /// Filed under a [_SharedSectionRow] above it, so indented beneath it.
  final bool nested;
  final VoidCallback onTap;

  const _SharedRecordRow({
    required this.record,
    required this.value,
    required this.nested,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = record;
    final masked = r.isHidden && !Stores.vault.isRevealed(r.id);

    // Square like every row in a card; the card's clip rounds the ends.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          nested ? AppSpacing.md + AppSpacing.xl : AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              RecordTypeUtils.icon(r.type),
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            AppSpacing.gapMd,
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    r.label.isEmpty ? r.key : r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AppText(
                    r.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).small.muted.mono,
                ],
              ),
            ),
            AppSpacing.gapMd,
            Expanded(
              flex: 5,
              child: AppText(
                masked ? '••••••••••••' : value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ).small,
            ),
            if (r.isHidden)
              AppButton(
                icon: masked ? AppIcons.eye : AppIcons.eyeSlash,
                tooltip: masked ? 'Show value' : 'Hide value',
                style: AppButtonStyle.accent,
                size: AppButtonSize.small,
                onTap: () => Stores.vault.toggleRevealed(r.id),
              )
            else
              const SizedBox(width: AppSpacing.xs),
            Icon(
              AppIcons.chevronRight,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
