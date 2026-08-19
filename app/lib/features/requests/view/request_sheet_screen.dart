import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/api_access_sheet.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_screen_header.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/sheet_view.dart';

/// Spreadsheet view of a request's responses, opened from the Inbox.
///
/// Each responder is one row (keyed by signing identity, else the
/// pseudonymous identifier, else the response link), and each requested field
/// is a column — the same living, server-resolved values the grouped view
/// shows, but in a navigable grid you can sort, copy, and export to CSV. The
/// data is read-only here by design: each response is the responder's own
/// living grant, which the request owner cannot write back to.
class RequestSheetScreen extends StatefulWidget {
  final String requestId;

  const RequestSheetScreen({super.key, required this.requestId});

  @override
  State<RequestSheetScreen> createState() => _RequestSheetScreenState();
}

class _RequestSheetScreenState extends State<RequestSheetScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant RequestSheetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId) _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final store = Stores.requests;
    if (store.requests.isEmpty) await store.loadRequests();
    await store.loadResponses(widget.requestId);
    if (mounted) setState(() => _loading = false);
  }

  String _requestLabel() {
    for (final req in Stores.requests.requests) {
      if (req.id == widget.requestId) {
        return req.label.isEmpty ? req.slug : req.label;
      }
    }
    return 'Request';
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

  bool _requestClosed() {
    for (final req in Stores.requests.requests) {
      if (req.id == widget.requestId) {
        return req.status == 'revoked' || req.status == 'expired';
      }
    }
    return false;
  }

  /// Collapses the request's responses into one row per responder and the
  /// union of their answered fields into columns.
  _SheetData _pivot(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final responses =
        Stores.requests.responsesByRequest[widget.requestId] ?? const [];
    final closed = _requestClosed();

    // One row per responder: identity wins, then identifier, then the link.
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final r in responses) {
      final id = (r['identity'] as String?) ?? '';
      final ident = (r['identifier'] as String?) ?? '';
      final slug = (r['slug'] as String?) ?? '';
      final key = id.isNotEmpty
          ? 'id:$id'
          : ident.isNotEmpty
          ? 'idf:$ident'
          : slug.isNotEmpty
          ? 'slug:$slug'
          : 'r:${r['created']}';
      if (seen.add(key)) unique.add(r);
    }

    // Columns: union of answered field keys, in first-seen order.
    final keys = <String>[];
    final keySet = <String>{};
    for (final r in unique) {
      final data = r['data'];
      if (data is Map) {
        for (final k in data.keys) {
          if (keySet.add(k.toString())) keys.add(k.toString());
        }
      }
    }
    final hasIdentifier = unique.any(
      (r) => ((r['identifier'] as String?) ?? '').isNotEmpty,
    );

    final columns = <SheetColumn>[
      const SheetColumn('Responder', width: 190),
      if (hasIdentifier) const SheetColumn('Identifier', width: 150),
      for (final k in keys) SheetColumn(k, width: 170),
      const SheetColumn('Status', width: 110),
      const SheetColumn('Submitted', width: 160),
    ];

    final rows = <List<SheetCell>>[];
    for (final r in unique) {
      final senderRaw = (r['senderName'] as String?)?.trim();
      final sender = (senderRaw == null || senderRaw.isEmpty)
          ? 'Anonymous'
          : senderRaw;
      final verified = ((r['identity'] as String?) ?? '').isNotEmpty;
      final revoked = ((r['status'] as String?) ?? '') == 'revoked' || closed;
      final data = r['data'];
      final dataMap = data is Map ? data : const {};
      final slug = (r['slug'] as String?) ?? '';

      rows.add([
        SheetCell(
          sender,
          leading: verified
              ? Icon(AppIcons.shieldCheck, size: 14, color: scheme.primary)
              : null,
        ),
        if (hasIdentifier) SheetCell((r['identifier'] as String?) ?? ''),
        for (final k in keys)
          SheetCell(
            '${dataMap[k] ?? ''}',
            onTap: () => _onValueTap(slug, k, '${dataMap[k] ?? ''}'),
          ),
        SheetCell(
          revoked ? 'Revoked' : 'Live',
          color: revoked ? scheme.error : null,
        ),
        SheetCell(_formatDate((r['created'] as String?) ?? '')),
      ]);
    }

    return _SheetData(columns: columns, rows: rows);
  }

  void _copyCsv(_SheetData data) {
    String esc(String s) =>
        (s.contains(',') || s.contains('"') || s.contains('\n'))
        ? '"${s.replaceAll('"', '""')}"'
        : s;
    final b = StringBuffer();
    b.writeln(data.columns.map((c) => esc(c.label)).join(','));
    for (final row in data.rows) {
      b.writeln(
        [
          for (var i = 0; i < data.columns.length; i++)
            esc(i < row.length ? row[i].text : ''),
        ].join(','),
      );
    }
    Clipboard.setData(ClipboardData(text: b.toString()));
    AppToast.success(context, 'Copied ${data.rows.length} rows as CSV');
  }

  /// Drawer shown when a value cell is tapped: copy it, or open the same
  /// Web & API access used everywhere else, preset to this field.
  void _onValueTap(String slug, String key, String value) {
    showAppOptionsSheet(
      context: context,
      title: key,
      subtitle: value.isEmpty ? null : value,
      actions: [
        AppSheetAction(
          icon: AppIcons.copy,
          label: 'Copy value',
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            AppToast.success(context, 'Copied to clipboard');
          },
        ),
        if (slug.isNotEmpty)
          AppSheetAction(
            icon: AppIcons.server,
            label: 'Web & API access',
            onTap: () => showApiAccessSheet(
              context,
              target: ApiAccessTarget(
                slug: slug,
                title: key,
                intro:
                    'Reuse this value (or the whole response) — pick a format '
                    'and copy a ready-to-use endpoint.',
                keys: [key],
                presetKey: key,
              ),
            ),
          ),
      ],
    );
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
              final data = _loading ? null : _pivot(context);
              final count = data?.rows.length ?? 0;
              return AppScreenHeader(
                title: _requestLabel(),
                onBack: () => context.go(AppRoutes.inbox),
                badgeLabel: '$count ${count == 1 ? 'responder' : 'responders'}',
                actions: [
                  _responsesToggle(context, widget.requestId, current: 1),
                  AppButton(
                    icon: AppIcons.copy,
                    tooltip: 'Copy as CSV',
                    style: AppButtonStyle.accent,
                    onTap: (data == null || data.rows.isEmpty)
                        ? null
                        : () => _copyCsv(data),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: _loading
              ? const Center(child: AppSpinner(large: true))
              : Observer(
                  builder: (_) {
                    final data = _pivot(context);
                    if (data.rows.isEmpty) {
                      return const AppEmptyState(
                        icon: AppIcons.cardList,
                        title: 'No responses yet',
                        subtitle:
                            'When people respond to this request, each one shows up here as a row.',
                      );
                    }
                    return Padding(
                      padding: EdgeInsets.fromLTRB(pad, 0, pad, AppSpacing.lg),
                      child: SheetView(columns: data.columns, rows: data.rows),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _SheetData {
  final List<SheetColumn> columns;
  final List<List<SheetCell>> rows;
  const _SheetData({required this.columns, required this.rows});
}
