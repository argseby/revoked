import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/features/shares/view/share_actions.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/router/held_link_keys.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/api_access_sheet.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/audience_tag.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';
import 'package:revoked_app/features/shares/view/link_groups.dart';
import 'package:revoked_app/features/shares/view/share_create_sheet.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';
import 'package:revoked_app/core/models/feature.dart';

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

  Link? get _share => Stores.shares.findById(widget.shareId);

  /// Whether this person may change a colleague's share: asked of the server
  /// once the share is known, null until then.
  final Local<bool?> _canEdit = Local(null);
  bool _askedCanEdit = false;

  void _askCanEdit(Link share) {
    if (_askedCanEdit || _mine(share)) return;
    _askedCanEdit = true;
    Stores.shares.canEditShare(share.id).then((v) {
      if (mounted) _canEdit.value = v;
    });
  }

  /// The owner, or a member the share is open to for editing.
  bool _editable(Link share) => _mine(share) || _canEdit.value == true;

  /// Whether this person owns the share. A colleague's share, opened to them
  /// (VISIBILITY.md), can be changed here only when it is also open to them
  /// for editing ([_editable]); who sees it stays its owner's.
  bool _mine(Link share) =>
      Stores.auth.userId.isEmpty || share.user == Stores.auth.userId;

  void _openAccess(BuildContext context, Link share) => openAccessSheet(
    context,
    area: AccessArea.shares,
    id: share.id,
    name: share.label,
    audienceKind: share.audienceKind,
    editing: share.editing,
    save: (kind, editing, groups) => Stores.shares.setShareAudience(
      share.id,
      kind: kind,
      editing: editing,
      groups: groups,
    ),
    saveError: () => Stores.shares.errorMessage,
  );

  void _back() => context.go(AppRoutes.shared);

  /// Beside the list in a split there is nothing to go back to: the list
  /// is on screen, and picking another link there is the way on.
  Widget _title(BuildContext context) {
    final split = mounted && ShellSplitPane.contains(this.context);
    return AppBarTitle(title: 'Shares', onBack: split ? null : _back);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final share = _share;
        if (share == null) {
          if (Stores.shares.isLoading) {
            return const AppDetailSkeleton(
              badges: ['active'],
              primary: 'Share link',
              sections: [
                AppSkeletonGroup('What it shares', rows: 2),
                AppSkeletonGroup('Protection', rows: 3),
              ],
              aside: [
                AppSkeletonGroup('Access', rows: 2),
                AppSkeletonGroup('Details', rows: 3),
              ],
            );
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

        final mine = _mine(share);
        _askCanEdit(share);
        return AppDetailPage(
          header: _header(context, share),
          sections: [
            _summary(share),
            if (mine) ...[
              _contents(context, share),
              _manage(context, share),
            ] else ...[
              _othersContents(share),
              // Open to this member for editing: pause, revoke and delete,
              // though not what it holds, which is its owner's.
              if (_editable(share)) _manage(context, share),
            ],
          ],
          aside: [_access(share), _origin(share)],
        );
      },
    );
  }

  AppDetailHeader _header(BuildContext context, Link share) {
    final theme = Theme.of(context);
    final attention = linkAttention(share, DateTime.now());
    final status = share.status;
    final busy = _busy.value != null;

    final mine = _mine(share);
    final editable = _editable(share);
    // A colleague's share can be passed on while active and, by an editor,
    // reactivated; a copy of it would hold their records, which is refused.
    final Widget? primary =
        !mine && !(status == 'active' || (editable && status == 'paused'))
        ? null
        : switch (status) {
            'active' => AppButton(
              icon: AppIcons.share,
              label: 'Share link',
              onTap: () => showShareSheet(
                context: context,
                slug: share.slug,
                title: share.label,
                isRequest: false,
                apiTarget: _apiTarget(share),
                linkKey: Stores.shares.linkKeyText(share),
                keyUnreadable:
                    share.hasKey && Stores.shares.linkKeyText(share) == null,
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

    final full = Stores.features.visible(Feature.developer);
    return AppDetailHeader(
      badges: [
        StatusLabel(status),
        if (!mine)
          const AppBadge(
            icon: AppIcons.personWorkspace,
            label: 'Shared by a member',
          ),
        AudienceTag(Audience(share.audienceKind, share.audienceGroups)),
        if (attention != null)
          AppBadge(
            icon: AppIcons.clock,
            label: attention.reason,
            accent: theme.colorScheme.warning,
          ),
      ],
      title: share.label.trim().isEmpty ? 'Unnamed link' : share.label,
      // The slug is for whoever scripts against it; the label names it.
      subtitle: full ? share.slug : null,
      subtitleMono: true,
      primaryAction: primary,
      secondaryActions: [
        if (status == 'active')
          AppButton(
            icon: AppIcons.eye,
            tooltip: 'View as recipient',
            style: AppButtonStyle.accent,
            onTap: () {
              final key = Stores.shares.linkKeyText(share);
              HeldLinkKeys.hold(
                slug: share.slug,
                key: key == null ? null : SealedFormats.parseLinkKey(key),
              );
              context.push('/s/${share.slug}');
            },
          ),
        if (mine) ...[
          AppButton(
            icon: AppIcons.personWorkspace,
            tooltip: 'Visibility',
            style: AppButtonStyle.accent,
            onTap: () => _openAccess(context, share),
          ),
          AppButton(
            icon: AppIcons.pencil,
            tooltip: 'Edit',
            style: AppButtonStyle.accent,
            onTap: () =>
                openShareCreateSheet(context: context, editShare: share),
          ),
          if (status == 'active' || status == 'paused')
            AppButton(
              icon: AppIcons.duplicate,
              tooltip: 'Duplicate',
              style: AppButtonStyle.accent,
              onTap: () =>
                  openShareCreateSheet(context: context, initialShare: share),
            ),
        ] else if (editable)
          AppButton(
            icon: AppIcons.pencil,
            tooltip: 'Edit',
            style: AppButtonStyle.accent,
            onTap: () =>
                openShareCreateSheet(context: context, editShare: share),
          ),
      ],
    );
  }

  /// A colleague's share holds records of their vault, not this person's, so
  /// they are not listed against this vault. Opening the link shows them.
  Widget _othersContents(Link share) {
    final n = share.records.length + share.sections.length;
    return AppListGroup(
      title: 'Contents',
      children: [
        AppDetailRow(
          icon: AppIcons.info,
          label: n == 0
              ? 'Nothing selected'
              : '$n ${n == 1 ? 'item' : 'items'} of its owner\'s vault, shown '
                    'to whoever opens the link',
        ),
      ],
    );
  }

  /// What the link hands out, resolved against the vault: every record with
  /// its key, filed under the section it is shared through. Values stay on
  /// the record's own page, so a secret is not on show here and a long name
  /// keeps its room.
  Widget _contents(BuildContext context, Link share) {
    final vault = Stores.vault;
    // A share may hold entries the workspace published, beside its own.
    final byId = {
      for (final r in vault.sharedRecords) r.id: r,
      for (final r in vault.records) r.id: r,
    };
    final rows = <Widget>[];
    final placed = <String>{};

    Widget recordRow(models.Record r, {bool nested = false}) =>
        _SharedRecordRow(
          record: r,
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
              ? 'Nothing selected'
              : vault.isLoading
              ? 'Loading…'
              : vault.errorMessage != null
              ? 'The vault could not be loaded'
              : '$total items no longer in the vault',
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
      title: 'Contents · $count ${count == 1 ? 'record' : 'records'}',
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

  /// The link in one plain sentence: what it gives, and that it can be
  /// stopped. Said first, for anyone who reads no further.
  Widget _summary(Link share) {
    final n = share.records.length + share.sections.length;
    final what = n == 0
        ? 'nothing yet'
        : share.sections.isEmpty
        ? '${share.records.length} '
              '${share.records.length == 1 ? 'record' : 'records'}'
        : 'the records listed below';
    final requirements = [
      if (share.hasPassword) 'the password',
      if (share.identity?.isNotEmpty == true)
        'the required identity'
      else if (share.requireHandshake)
        'viewer verification',
    ];
    final audience = requirements.isEmpty
        ? 'Anyone with this link'
        : 'Viewers with this link and ${requirements.join(' and ')}';
    final sentence = switch (share.status) {
      'active' =>
        '$audience can see $what, always the latest '
            'version. Access can be paused or revoked.',
      'paused' =>
        'This link is paused and cannot be opened until it is activated '
            'again.',
      'expired' => 'This link has expired and can no longer be opened.',
      _ =>
        'This link is permanently revoked. A new link can be created from it.',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Text(sentence),
    );
  }

  Widget _access(Link share) {
    final expires = dayTimeOf(share.expiresAt);
    return AppListGroup(
      title: 'Protection',
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
          label: 'Verified viewer',
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
        if (share.watermark && Stores.features.visible(Feature.developer))
          AppDetailRow(
            icon: AppIcons.hash,
            label: 'Watermark tag',
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
      origin = 'Created in the app';
    }

    return AppListGroup(
      title: 'Details',
      collapsed: true,
      noun: 'details',
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
            label: 'Sent to the tool',
            value: share.handedOver ? 'Yes' : 'No',
          ),
        AppDetailRow(
          icon: AppIcons.plus,
          label: 'Created',
          value: dayTimeOf(share.created) ?? '—',
        ),
        AppDetailRow(
          icon: AppIcons.pen,
          label: 'Last changed',
          value: dayTimeOf(share.updated) ?? '—',
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
        if (_mine(share) &&
            share.hasKey &&
            (status == 'active' || status == 'paused'))
          AppButton(
            icon: AppIcons.key,
            label: 'Replace link key',
            style: AppButtonStyle.accent,
            busy: busy == 'key',
            onTap: locked ? null : () => _replaceKey(share),
          ),
        if (status == 'active')
          AppButton(
            icon: AppIcons.pause,
            label: 'Pause',
            style: AppButtonStyle.accent,
            busy: busy == 'paused',
            onTap: locked ? null : () => _setStatus(share, 'paused'),
          ),
        if (status != 'revoked')
          AppButton(
            icon: AppIcons.shieldSlash,
            label: 'Revoke',
            style: AppButtonStyle.danger,
            busy: busy == 'revoked',
            onTap: locked ? null : () => _confirmRevoke(context, share),
          ),
        AppButton(
          icon: AppIcons.trash,
          label: 'Delete',
          style: AppButtonStyle.danger,
          busy: busy == 'delete',
          onTap: locked ? null : () => _confirmDelete(context, share),
        ),
      ],
    );
  }

  ShareActions get _actions => ShareActions(
    context,
    onBusy: (busy) => _busy.value = busy,
    onDeleted: _back,
  );

  Future<void> _replaceKey(Link share) => _actions.replaceKey(share);
  Future<void> _setStatus(Link share, String status) =>
      _actions.setStatus(share, status);
  Future<void> _confirmRevoke(BuildContext context, Link share) =>
      _actions.revoke(share);
  Future<void> _confirmDelete(BuildContext context, Link share) =>
      _actions.delete(share);

  /// Opens the Web & API access drawer for this share — pick a format and copy
  /// a ready-to-use `/s/{slug}` endpoint. The data stays behind the same
  /// revocation as everywhere else; this just exposes where to fetch it.
  ApiAccessTarget _apiTarget(Link share) => ApiAccessTarget(
    slug: share.slug,
    title: share.label,
    intro:
        'This link\'s data is available in several formats, always up to '
        'date.',
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

/// One shared record: its label and key. The row opens the record, where
/// its value is.
class _SharedRecordRow extends StatelessWidget {
  final models.Record record;

  /// Filed under a [_SharedSectionRow] above it, so indented beneath it.
  final bool nested;
  final VoidCallback onTap;

  const _SharedRecordRow({
    required this.record,
    required this.nested,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = record;

    // Square like every row in a card; the card's clip rounds the ends.
    return AppFocusRing(
      borderRadius: BorderRadius.zero,
      child: InkWell(
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
              AppSpacing.gapSm,
              Icon(
                AppIcons.chevronRight,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
