import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/features/requests/store/requests_store.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_screen_header.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/api_access_sheet.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/core/widgets/data_table/filter_bar.dart';

/// Grant status for a connection.
enum GrantStatus { live, revoked, vault }

/// One row in the Connections view: a single piece of information you hold,
/// plus where it came from, who shared it, and whether the source is still
/// active (a "living grant" rather than a dead copy).
class DataItem {
  final GrantStatus status;
  final String origin; // 'Request' | 'Vault'
  final String source; // request label / 'Vault'
  final String name; // field name / record label
  final String value; // the information itself
  final String templateId;
  final String requestId;
  final String linkSlug; // the grant link's slug (empty for vault items)
  final String sender;
  final bool verified; // shared under a cryptographic identity
  final String identityName; // signing identity's name (if verified)
  final String identityDomain; // signing identity's issuing domain
  final String identifier; // pseudonymous identifier the responder echoed back
  final String created;

  const DataItem({
    required this.status,
    required this.origin,
    required this.source,
    required this.name,
    required this.value,
    required this.templateId,
    required this.requestId,
    required this.linkSlug,
    required this.sender,
    required this.verified,
    required this.identityName,
    required this.identityDomain,
    required this.identifier,
    required this.created,
  });

  bool get isVault => origin == 'Vault';
  String get statusKey => status.name;
}

/// The Connections view — everything you hold as living, revocable, verified
/// grants: request responses (data others shared with you) and your own vault
/// records, filterable by name / value / template / source / status.
class DataScreen extends StatefulWidget {
  /// When set, only data from this request is shown.
  final String? requestId;

  const DataScreen({super.key, this.requestId});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  late final TableStore<DataItem> _table;

  @override
  void initState() {
    super.initState();
    _table = TableStore<DataItem>(
      getSourceItems: _buildItems,
      fieldGetters: {
        'name': (d) => d.name,
        'value': (d) => d.value,
        'source': (d) => d.source,
        'template': (d) => d.templateId,
        'origin': (d) => d.origin,
        'sender': (d) => d.sender,
        'status': (d) => d.statusKey,
        'created': (d) => d.created,
      },
      defaultSort: 'created_desc',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.setFilter(_filterButton);
      _load();
    });
  }

  Future<void> _load() =>
      Stores.requests.loadDataScreen(Stores.vault.loadRecords);

  @override
  void dispose() {
    ShellSlots.clearFilter(_filterButton);
    _table.dispose();
    super.dispose();
  }

  Widget _filterButton(BuildContext context) {
    return FilterButton<DataItem>(
      controller: _table,
      columns: const [
        DataTableColumn(value: 'name', label: 'Name'),
        DataTableColumn(value: 'value', label: 'Value'),
        DataTableColumn(value: 'source', label: 'Source'),
        DataTableColumn(value: 'template', label: 'Template ID'),
        DataTableColumn(value: 'sender', label: 'Sender'),
        DataTableColumn(value: 'status', label: 'Status (live/revoked/vault)'),
      ],
    );
  }

  GrantStatus _grantStatus(String requestStatus) {
    if (requestStatus == 'revoked' || requestStatus == 'expired') {
      return GrantStatus.revoked;
    }
    return GrantStatus.live;
  }

  List<DataItem> _buildItems() {
    final requests = Stores.requests;
    final vault = Stores.vault;
    final items = <DataItem>[];

    for (final req in requests.requests) {
      if (widget.requestId != null && req.id != widget.requestId) continue;
      final responses = requests.responsesByRequest[req.id] ?? const [];
      for (final r in responses) {
        // A response can be individually revoked by its responder even while
        // the request itself is still live; that wins over the request status.
        final respStatus = (r['status'] as String?) ?? '';
        final status = respStatus == 'revoked'
            ? GrantStatus.revoked
            : _grantStatus(req.status);
        final senderRaw = (r['senderName'] as String?)?.trim();
        final sender = (senderRaw == null || senderRaw.isEmpty)
            ? 'Anonymous'
            : senderRaw;
        final verified = ((r['identity'] as String?) ?? '').isNotEmpty;
        final created = (r['created'] as String?) ?? '';
        final data = r['data'];
        if (data is Map) {
          data.forEach((key, val) {
            items.add(
              DataItem(
                status: status,
                origin: 'Request',
                source: req.label.isEmpty ? req.slug : req.label,
                name: key.toString(),
                value: '${val ?? ''}',
                templateId: req.templateId,
                requestId: req.id,
                linkSlug: (r['slug'] as String?) ?? '',
                sender: sender,
                verified: verified,
                identityName: (r['identityName'] as String?) ?? '',
                identityDomain: (r['identityDomain'] as String?) ?? '',
                identifier: (r['identifier'] as String?) ?? '',
                created: created,
              ),
            );
          });
        }
      }
    }

    if (widget.requestId == null) {
      for (final rec in vault.records) {
        items.add(
          DataItem(
            status: GrantStatus.vault,
            origin: 'Vault',
            source: 'Vault',
            name: rec.label.isEmpty ? rec.key : rec.label,
            value: rec.isHidden ? '••••••••' : rec.value,
            templateId: '',
            requestId: '',
            linkSlug: '',
            sender: '',
            verified: false,
            identityName: '',
            identityDomain: '',
            identifier: '',
            created: rec.created ?? '',
          ),
        );
      }
    }
    return items;
  }

  String _activeRequestLabel() {
    for (final req in Stores.requests.requests) {
      if (req.id == widget.requestId) {
        return req.label.isEmpty ? req.slug : req.label;
      }
    }
    return widget.requestId ?? '';
  }

  /// The List/Sheet switch shown in both response views so it's always clear
  /// which layout you're in (and easy to flip).
  Widget _responsesToggle(
    BuildContext context,
    String requestId, {
    required int current,
  }) {
    return AppSegmented<int>(
      value: current,
      items: const [
        AppSegmentedItem(value: 0, label: 'List'),
        AppSegmentedItem(value: 1, label: 'Sheet'),
      ],
      onChanged: (v) {
        if (v == current) return;
        context.go(
          v == 0
              ? '${AppRoutes.requestData}?requestId=$requestId'
              : '${AppRoutes.requestSheet}?requestId=$requestId',
        );
      },
    );
  }

  /// Groups a request's response items by who sent them: by signing identity
  /// when present, otherwise one bucket per submission (rendered as anonymous).
  /// Items from the same response share a link slug, so that's the group key;
  /// truly anonymous guests fall back to a per-submission synthetic key.
  List<List<DataItem>> _groupByResponder(List<DataItem> items) {
    final order = <String>[];
    final map = <String, List<DataItem>>{};
    for (final it in items) {
      final key = it.linkSlug.isNotEmpty
          ? it.linkSlug
          : 'resp:${it.created}|${it.sender}';
      final bucket = map[key];
      if (bucket == null) {
        map[key] = [it];
        order.add(key);
      } else {
        bucket.add(it);
      }
    }
    return [for (final k in order) map[k]!];
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screenH(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, AppSpacing.md, pad, 0),
          child: Observer(
            builder: (_) {
              final count = _table.filteredItems.length;
              return AppScreenHeader(
                title: widget.requestId != null
                    ? _activeRequestLabel()
                    : 'Connections',
                onBack: widget.requestId != null
                    ? () => context.go(AppRoutes.inbox)
                    : null,
                badgeLabel: '$count ${count == 1 ? 'item' : 'items'}',
                actions: [
                  if (widget.requestId != null) ...[
                    _responsesToggle(context, widget.requestId!, current: 0),
                  ],
                ],
              );
            },
          ),
        ),

        // Overview of how many connections are live vs revoked vs from vault.
        Observer(
          builder: (_) {
            if (Stores.requests.isLoadingData) return const SizedBox.shrink();
            final all = _buildItems();
            final live = all.where((d) => d.status == GrantStatus.live).length;
            final revoked = all
                .where((d) => d.status == GrantStatus.revoked)
                .length;
            final vault = all
                .where((d) => d.status == GrantStatus.vault)
                .length;
            if (all.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, 0),
              child: Wrap(
                spacing: AppSpacing.xs,
                children: [
                  _StatChip(status: GrantStatus.live, count: live),
                  _StatChip(status: GrantStatus.revoked, count: revoked),
                  _StatChip(status: GrantStatus.vault, count: vault),
                ],
              ),
            );
          },
        ),

        Expanded(
          child: Observer(
            builder: (_) {
              if (Stores.requests.isLoadingData) {
                return const Center(child: AppSpinner(large: true));
              }
              final items = _table.filteredItems;
              if (items.isEmpty) {
                return AppEmptyState(
                  icon: AppIcons.cardList,
                  title: widget.requestId != null
                      ? 'No responses yet'
                      : 'No connections yet',
                  subtitle: widget.requestId != null
                      ? 'Data people send in response to this request will appear here, grouped by who sent it.'
                      : 'Data shared with you and your own vault records will show up here.',
                );
              }
              // Per-request view: group every response by who sent it —
              // by signing identity, or an anonymous bucket per submission.
              if (widget.requestId != null) {
                final groups = _groupByResponder(items);
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    pad,
                    AppSpacing.md,
                    pad,
                    AppSpacing.huge,
                  ),
                  itemCount: groups.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) => _ResponderGroup(
                    items: groups[i],
                    onTapItem: (it) => _showDetail(context, it),
                  ),
                );
              }
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  pad,
                  AppSpacing.md,
                  pad,
                  AppSpacing.huge,
                ),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _DataRow(
                  item: items[i],
                  onTap: () => _showDetail(context, items[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showDetail(BuildContext context, DataItem item) async {
    await showAppSheet(
      context: context,
      builder: (sheetCtx) {
        final scheme = Theme.of(sheetCtx).colorScheme;
        final pullSlug = item.isVault || item.linkSlug.isEmpty
            ? null
            : item.linkSlug;
        return Padding(
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
              Row(
                children: [
                  Expanded(child: Text(item.name).header),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusPill(status: item.status),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: AppRadius.allMd,
                ),
                child: Text(
                  item.value.isEmpty ? '—' : item.value,
                ).mono.selectable,
              ),
              const SizedBox(height: AppSpacing.lg),
              _kv(context, 'Source', item.isVault ? 'Your vault' : item.source),
              if (!item.isVault) _kv(context, 'Shared by', item.sender),
              if (!item.isVault)
                _kv(
                  context,
                  'Identity',
                  !item.verified
                      ? 'Unsigned'
                      : item.identityName.isEmpty
                      ? 'Signed — cryptographic identity'
                      : item.identityDomain.isEmpty
                      ? 'Signed by ${item.identityName}'
                      : 'Signed by ${item.identityName} (${item.identityDomain})',
                ),
              if (item.created.isNotEmpty)
                _kv(context, 'Received', _formatDate(item.created)),
              if (pullSlug != null) ...[
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  icon: AppIcons.server,
                  label: 'Web & API access',
                  style: AppButtonStyle.accent,
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    showApiAccessSheet(
                      context,
                      target: ApiAccessTarget(
                        slug: pullSlug,
                        title: item.name,
                        intro:
                            'Reuse this value (or the whole response) — pick a '
                            'format and copy a ready-to-use endpoint.',
                        keys: [item.name],
                        presetKey: item.name,
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (item.isVault)
                AppButton(
                  icon: AppIcons.safe,
                  label: 'Open in Vault',
                  style: AppButtonStyle.accent,
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    context.go(AppRoutes.vault);
                  },
                )
              else ...[
                AppButton(
                  icon: AppIcons.inboxFill,
                  label: 'Open source request',
                  style: AppButtonStyle.accent,
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    context.go(AppRoutes.inbox);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                if (item.status == GrantStatus.live)
                  AppButton(
                    icon: AppIcons.xCircle,
                    label: 'Revoke source request',
                    style: AppButtonStyle.destructive,
                    onTap: () => _revokeSource(sheetCtx, item),
                  ),
                if (item.status == GrantStatus.live)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: const Text(
                      'Stops this request collecting any new data.',
                    ).muted.small,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _revokeSource(BuildContext sheetCtx, DataItem item) async {
    final confirmed = await showAppDialog(
      context: sheetCtx,
      title: 'Revoke request?',
      message:
          'The link stops working immediately and collects no further '
          'responses. Data already collected is kept.',
      content: ApiPreview(
        spec: RequestsStore.updateRequestSpec(item.requestId, const {
          'status': 'revoked',
        }),
        title: 'API request · revoke',
      ),
      confirmLabel: 'Revoke',
      destructive: true,
    );
    if (!confirmed || !sheetCtx.mounted) return;
    final ok = await Stores.requests.updateRequest(item.requestId, {
      'status': 'revoked',
    });
    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
    if (!mounted) return;
    if (ok) {
      AppToast.success(context, 'Source request revoked');
    } else {
      AppToast.error(
        context,
        'Could not revoke',
        subtitle: Stores.requests.errorMessage,
      );
    }
  }

  Widget _kv(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label).muted.small),
          Expanded(child: Text(value).small),
        ],
      ),
    );
  }
}

/// Formats an ISO datetime as a local YYYY-MM-DD, echoing it back on failure.
String _formatDate(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}

/// Visual styling for a [GrantStatus].
class _StatusStyle {
  final String label;
  final Color bg;
  final Color fg;
  const _StatusStyle(this.label, this.bg, this.fg);

  factory _StatusStyle.of(GrantStatus status, ColorScheme scheme) {
    switch (status) {
      case GrantStatus.live:
        return _StatusStyle(
          'Live',
          scheme.primary.withValues(alpha: 0.12),
          scheme.primary,
        );
      case GrantStatus.revoked:
        return _StatusStyle(
          'Revoked',
          scheme.errorContainer,
          scheme.onErrorContainer,
        );
      case GrantStatus.vault:
        return _StatusStyle(
          'Vault',
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        );
    }
  }
}

class _StatusPill extends StatelessWidget {
  final GrantStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final style = _StatusStyle.of(status, Theme.of(context).colorScheme);
    return AppBadge(label: style.label, accent: style.fg);
  }
}

class _StatChip extends StatelessWidget {
  final GrantStatus status;
  final int count;
  const _StatChip({required this.status, required this.count});

  @override
  Widget build(BuildContext context) {
    final style = _StatusStyle.of(status, Theme.of(context).colorScheme);
    return AppBadge(
      label: '$count ${style.label.toLowerCase()}',
      accent: style.fg,
    );
  }
}

/// One responder's submission to a request: a header identifying who sent it
/// (signing identity, or anonymous) with their identifier, then the fields they
/// shared listed below.
class _ResponderGroup extends StatelessWidget {
  final List<DataItem> items;
  final void Function(DataItem) onTapItem;

  const _ResponderGroup({required this.items, required this.onTapItem});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final head = items.first;

    final String title;
    if (head.verified && head.identityName.isNotEmpty) {
      title = head.identityDomain.isEmpty
          ? head.identityName
          : '${head.identityName} (${head.identityDomain})';
    } else if (head.sender.isNotEmpty && head.sender != 'Anonymous') {
      title = head.sender;
    } else {
      title = 'Anonymous';
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: head.verified
                        ? scheme.primary.withValues(alpha: 0.12)
                        : scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    head.verified
                        ? AppIcons.shieldCheck
                        : AppIcons.personBoundingBox,
                    size: 18,
                    color: head.verified
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ).small,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          AppBadge(
                            label: head.verified ? 'Signed' : 'Unsigned',
                            variant: head.verified
                                ? AppBadgeVariant.primary
                                : AppBadgeVariant.outline,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (head.identifier.isNotEmpty)
                            AppBadge(
                              icon: AppIcons.tag,
                              label: 'ID: ${head.identifier}',
                            ),
                          Text(
                            '${items.length} ${items.length == 1 ? 'field' : 'fields'}',
                          ).muted.small,
                          if (head.created.isNotEmpty)
                            Text('· ${_formatDate(head.created)}').muted.small,
                        ],
                      ),
                    ],
                  ),
                ),
                if (head.linkSlug.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  AppButton(
                    icon: AppIcons.server,
                    tooltip: 'Web & API access',
                    style: AppButtonStyle.accent,
                    size: AppButtonSize.small,
                    onTap: () => _openApiAccess(context),
                  ),
                ] else
                  const SizedBox(width: AppSpacing.sm),
                _StatusPill(status: head.status),
              ],
            ),
          ),
          const AppDivider(),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const AppDivider(inset: true),
            _FieldRow(item: items[i], onTap: () => onTapItem(items[i])),
          ],
        ],
      ),
    );
  }

  void _openApiAccess(BuildContext context) {
    final head = items.first;
    if (head.linkSlug.isEmpty) return;
    showApiAccessSheet(
      context,
      target: ApiAccessTarget(
        slug: head.linkSlug,
        title: head.sender.isEmpty ? 'Responder' : head.sender,
        intro:
            'Reuse the data this responder shared — pick a format and copy a '
            'ready-to-use endpoint. It stays live until the grant is revoked.',
        keys: [for (final it in items) it.name],
      ),
    );
  }
}

/// A compact field row inside a [_ResponderGroup] — the shared key and its
/// current value, tappable for full provenance.
class _FieldRow extends StatelessWidget {
  final DataItem item;
  final VoidCallback onTap;

  const _FieldRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.allMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name).small,
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    item.value.isEmpty ? '—' : item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).mono.muted.small,
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              AppIcons.chevronRight,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final DataItem item;
  final VoidCallback onTap;

  const _DataRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(item.name).small),
                    if (item.verified) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Icon(
                        AppIcons.shieldCheck,
                        size: 13,
                        color: scheme.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  item.value.isEmpty ? '—' : item.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ).mono.small,
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Icon(
                      item.isVault ? AppIcons.safe : AppIcons.inboxFill,
                      size: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Flexible(
                      child: Text(
                        item.isVault
                            ? 'Vault'
                            : '${item.source}${item.sender.isNotEmpty ? ' · ${item.sender}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).muted.small,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatusPill(status: item.status),
        ],
      ),
    );
  }
}
