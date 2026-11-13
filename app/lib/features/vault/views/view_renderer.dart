import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_qr_code.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/redacted_value.dart';
import 'package:revoked_app/features/vault/views/view_data.dart';
import 'package:revoked_app/features/vault/views/view_spec.dart';

/// Draws a [ViewSpec] over [data]: one card, its blocks top to bottom.
class ViewRenderer extends StatefulWidget {
  final ViewSpec spec;
  final ViewData data;

  /// "Now" for countdowns and schedules; the clock unless a test sets it.
  final DateTime? now;

  const ViewRenderer({
    super.key,
    required this.spec,
    required this.data,
    this.now,
  });

  @override
  State<ViewRenderer> createState() => _ViewRendererState();
}

/// The accent names a view may use, so a view never brings its own colours.
Color viewAccent(String name, ColorScheme scheme) => switch (name) {
  'teal' => const Color(0xFF0D9488),
  'red' => scheme.danger,
  'amber' => scheme.warning,
  'green' => scheme.success,
  'violet' => const Color(0xFF7C3AED),
  _ => scheme.primary,
};

IconData viewIcon(String name) => switch (name) {
  'wifi' => AppIcons.wifi,
  'health' => AppIcons.health,
  'car' => AppIcons.car,
  'medication' => AppIcons.medication,
  'person' => AppIcons.person,
  'phone' => AppIcons.phone,
  'calendar' => AppIcons.calendar,
  'key' => AppIcons.key,
  'server' => AppIcons.server,
  'finance' => AppIcons.finance,
  _ => AppIcons.folder,
};

class _ViewRendererState extends State<ViewRenderer> {
  /// Secrets shown on this card; blocks that carry one follow it.
  final _revealed = Local<Set<String>>(const {});

  ViewData get _data => widget.data;
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  Widget build(BuildContext context) => Observer(builder: _build);

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('section-view-${widget.spec.id}'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.allLg,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: _blocks(context, widget.spec.blocks),
    );
  }

  Widget _blocks(BuildContext context, List<ViewBlock> blocks) {
    final shown = [
      for (final b in blocks)
        if (_data.test(b.when)) ?_block(context, b),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, w) in shown.indexed) ...[if (i > 0) AppSpacing.gapLg, w],
      ],
    );
  }

  Widget? _block(BuildContext context, ViewBlock b) => switch (b) {
    HeaderBlock() => _header(context, b),
    TextBlock() => _text(context, b),
    BadgesBlock() => _badges(context, b),
    FactsBlock() => _facts(context, b),
    SecretBlock() => _secret(context, b),
    QrBlock() => _qr(context, b),
    ActionsBlock() => _actions(context, b),
    CountdownBlock() => _countdown(context, b),
    SplitBlock() => _split(context, b),
    ScheduleBlock() => _schedule(context, b),
    DividerBlock() => Divider(
      height: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    ),
  };

  Color? _tone(String tone, ColorScheme scheme) => switch (tone) {
    'success' => scheme.success,
    'warning' => scheme.warning,
    'danger' => scheme.danger,
    'accent' => viewAccent(widget.spec.accent, scheme),
    _ => null,
  };

  Widget _header(BuildContext context, HeaderBlock b) {
    final scheme = Theme.of(context).colorScheme;
    final accent = viewAccent(widget.spec.accent, scheme);
    final title = _data.fill(b.title);
    // A line whose fields are not all filled in is left out, not shown half.
    final eyebrow = _data.complete(b.eyebrow) ? _data.fill(b.eyebrow) : '';
    final subtitle = _data.complete(b.subtitle) ? _data.fill(b.subtitle) : '';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: AppRadius.allMd,
          ),
          child: Icon(viewIcon(b.icon), color: accent),
        ),
        AppSpacing.gapMd,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow.trim().isNotEmpty) Text(eyebrow).small.muted,
              AppText(
                title.trim().isEmpty ? widget.spec.name : title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ).header,
              if (subtitle.trim().isNotEmpty) Text(subtitle).small.muted,
            ],
          ),
        ),
      ],
    );
  }

  Widget? _text(BuildContext context, TextBlock b) {
    if (!_data.complete(b.text)) return null;
    final text = _data.fill(b.text);
    final scheme = Theme.of(context).colorScheme;
    if (b.tone == 'warning') {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.exclamationTriangle, size: 16, color: scheme.warning),
          AppSpacing.gapSm,
          Expanded(child: Text(text).small),
        ],
      );
    }
    return b.tone == 'body' ? Text(text) : Text(text).small.muted;
  }

  Widget? _badges(BuildContext context, BadgesBlock b) {
    final scheme = Theme.of(context).colorScheme;
    final shown = [
      for (final item in b.items)
        if (_data.test(item.when) && _data.complete(item.text)) item,
    ];
    if (shown.isEmpty) return null;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final item in shown)
          AppBadge(
            label: _data.fill(item.text),
            accent: _tone(item.tone, scheme),
          ),
      ],
    );
  }

  Widget? _facts(BuildContext context, FactsBlock b) {
    final items = [
      for (final f in b.items)
        if (_data.complete(f.value)) (f, _data.fill(f.value)),
    ];
    if (items.isEmpty) return null;
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final columns = (box.maxWidth / (170 * scale)).floor().clamp(1, 3);
        final width = (box.maxWidth - AppSpacing.lg * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.md,
          children: [
            for (final (f, v) in items)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.label).small.muted,
                    f.mono
                        ? AppText(v, selectable: true).mono
                        : AppText(v, selectable: true),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    AppToast.success(context, '$what copied');
  }

  Widget _secret(BuildContext context, SecretBlock b) {
    final value = _data.value(b.key);
    final revealed = _revealed.value.contains(b.key);
    final label = b.label.isEmpty ? b.key : b.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label).small.muted,
        AppSpacing.gapXs,
        if (_data.isLocked(b.key))
          const Text('Not readable on this device.').small.muted
        else if (value == null || value.isEmpty)
          const Text('Not filled in yet.').small.muted
        else
          Row(
            children: [
              Expanded(
                child: revealed
                    ? AppText(value, selectable: true).mono
                    : const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: RedactionBar(width: 120),
                      ),
              ),
              AppButton(
                icon: revealed ? AppIcons.eyeSlash : AppIcons.eye,
                tooltip: revealed ? 'Hide $label' : 'Show $label',
                style: AppButtonStyle.ghost,
                onTap: () => _revealed.value = revealed
                    ? ({..._revealed.value}..remove(b.key))
                    : {..._revealed.value, b.key},
              ),
              AppButton(
                icon: AppIcons.copy,
                tooltip: 'Copy $label',
                style: AppButtonStyle.ghost,
                onTap: () => _copy(value, label),
              ),
            ],
          ),
      ],
    );
  }

  Widget? _qr(BuildContext context, QrBlock b) {
    if (!_data.complete(b.data)) return null;
    final scheme = Theme.of(context).colorScheme;
    // A code never carries a hidden value as dots: it stays covered until
    // every hidden value it holds has been shown.
    final covered = {
      if (b.revealWith.isNotEmpty) b.revealWith,
      ..._data.keysIn(b.data).where(_data.isHidden),
    }.any((key) => !_revealed.value.contains(key));
    const size = 160.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (covered)
          Container(
            width: size + AppSpacing.md * 2,
            height: size + AppSpacing.md * 2,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: AppRadius.allMd,
            ),
            child: Center(
              child: Icon(
                AppIcons.qrCode,
                size: 48,
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          AppQrCode(
            data: _data.fill(b.data, revealed: _revealed.value),
            size: size,
          ),
        AppSpacing.gapSm,
        Text(
          covered ? 'Shows once the secret is revealed.' : b.caption,
          textAlign: TextAlign.center,
        ).small.muted,
      ],
    );
  }

  Widget? _actions(BuildContext context, ActionsBlock b) {
    final buttons = <Widget>[];
    for (final a in b.items) {
      final v = (_data.value(a.key) ?? '').trim();
      if (v.isEmpty || _data.isHidden(a.key)) continue;
      final (icon, uri) = switch (a.kind) {
        'tel' => (
          AppIcons.phone,
          Uri(scheme: 'tel', path: v.replaceAll(RegExp(r'[^\d+]'), '')),
        ),
        'mail' => (AppIcons.mail, Uri(scheme: 'mailto', path: v)),
        _ => (AppIcons.boxArrowUpRight, Uri.tryParse(v)),
      };
      // Only links a person would expect to open: no scripts or files.
      if (uri == null ||
          !const ['http', 'https', 'tel', 'mailto'].contains(uri.scheme)) {
        continue;
      }
      buttons.add(
        AppButton(
          icon: icon,
          // "Call {insurer}" reads "Call" while the insurer is not filled in.
          label: _data.complete(a.label)
              ? _data.fill(a.label)
              : a.label.replaceAll(RegExp(r'\s*\{[^}]*\}'), '').trim(),
          style: AppButtonStyle.outline,
          size: AppButtonSize.small,
          onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
        ),
      );
    }
    if (buttons.isEmpty) return null;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: buttons,
    );
  }

  Widget? _countdown(BuildContext context, CountdownBlock b) {
    final date = DateTime.tryParse(_data.value(b.key) ?? '');
    if (date == null) return null;
    final scheme = Theme.of(context).colorScheme;
    final days = daysUntil(date, _now);
    final (text, tone) = days < 0
        ? ('${-days} ${-days == 1 ? 'day' : 'days'} overdue', scheme.danger)
        : days == 0
        ? ('Today', scheme.warning)
        : days <= b.warnDays
        ? ('In $days ${days == 1 ? 'day' : 'days'}', scheme.warning)
        : ('In $days days', scheme.onSurfaceVariant);
    return Row(
      children: [
        Icon(AppIcons.calendar, size: 18, color: tone),
        AppSpacing.gapSm,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.label).small.muted,
              Text(formatCalendarDay(date)),
            ],
          ),
        ),
        AppBadge(label: text, accent: tone),
      ],
    );
  }

  Widget _split(BuildContext context, SplitBlock b) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final main = _blocks(context, b.main);
      final side = _blocks(context, b.side);
      if (box.maxWidth >= 520 * scale) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: main),
            AppSpacing.gapXl,
            SizedBox(width: 160 + AppSpacing.md * 2, child: side),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          main,
          AppSpacing.gapXl,
          Center(child: side),
        ],
      );
    },
  );

  Widget? _schedule(BuildContext context, ScheduleBlock b) {
    final members = _data.group(b.group);
    if (members.isEmpty) return null;
    final scheme = Theme.of(context).colorScheme;
    final now = _now;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;

    String cell(String raw) => scheduleAmount(raw) > 0 ? raw.trim() : '–';

    final header = TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      children: [
        _cell(Text(b.heading).small.muted, start: true),
        for (final c in b.columns)
          _cell(
            Tooltip(
              message: c.time,
              child: Text(c.label, textAlign: TextAlign.center).small.muted,
            ),
          ),
      ],
    );
    final rows = <TableRow>[
      for (final m in members)
        () {
          final active = scheduleActive(m, b, now);
          final end = b.until.isEmpty ? null : DateTime.tryParse(m[b.until]);
          final lines = [
            if (b.detail.isNotEmpty && m[b.detail].isNotEmpty) m[b.detail],
            if (end != null)
              active ? 'until ${formatCalendarDay(end)}' : 'ended',
          ];
          return TableRow(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            children: [
              _cell(
                Opacity(
                  opacity: active ? 1 : 0.5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(m[b.label].isEmpty ? 'Unnamed' : m[b.label]).bold,
                      if (lines.isNotEmpty) Text(lines.join(' · ')).small.muted,
                      if (b.note.isNotEmpty && m[b.note].isNotEmpty)
                        Text(m[b.note]).small.muted,
                    ],
                  ),
                ),
                start: true,
              ),
              for (final c in b.columns)
                _cell(
                  Opacity(
                    opacity: active ? 1 : 0.5,
                    child: Text(cell(m[c.field]), textAlign: TextAlign.center),
                  ),
                ),
            ],
          );
        }(),
    ];

    final next = b.showNext ? nextDose(members, b, now) : null;
    final refills = [
      for (final m in members)
        if (scheduleActive(m, b, now))
          if (daysOfStock(m, b) case final d? when d <= b.refillWarnDays)
            (m, d),
    ];

    String when(DateTime at) {
      final minutes = at.difference(now).inMinutes;
      final time =
          '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
      final day = at.day == now.day ? '' : ' tomorrow';
      final rel = minutes < 60
          ? 'in $minutes min'
          : 'in ${(minutes / 60).round()} h';
      return 'at $time$day ($rel)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {
            0: const FlexColumnWidth(),
            for (var i = 1; i <= b.columns.length; i++)
              i: FixedColumnWidth(52 * scale),
          },
          children: [header, ...rows],
        ),
        if (next != null) ...[
          AppSpacing.gapMd,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.clock, size: 18, color: scheme.primary),
              AppSpacing.gapSm,
              Expanded(
                child: Text(
                  'Next: ${next.members.map((m) => [m[b.label], if (b.detail.isNotEmpty) m[b.detail]].where((s) => s.isNotEmpty).join(' ')).join(', ')} ${when(next.at)}',
                ),
              ),
            ],
          ),
        ],
        for (final (m, d) in refills) ...[
          AppSpacing.gapSm,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.exclamationTriangle,
                size: 18,
                color: scheme.warning,
              ),
              AppSpacing.gapSm,
              Expanded(
                child: Text(
                  d == 0
                      ? 'Refill ${m[b.label]} now: none left'
                      : 'Refill ${m[b.label]} soon: about $d '
                            '${d == 1 ? 'day' : 'days'} left',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _cell(Widget child, {bool start = false}) => Padding(
    padding: const EdgeInsets.symmetric(
      vertical: AppSpacing.sm,
      horizontal: AppSpacing.xs,
    ),
    child: start ? child : Center(child: child),
  );
}
