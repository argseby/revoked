import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/api_url_tile.dart';
import 'package:revoked_app/core/widgets/app_select.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';

/// What the [showApiAccessSheet] drawer should expose. The endpoints are always
/// the public `/s/{slug}` multi-format surface — the only difference between a
/// share ("data I expose") and a request response ("data I collected") is the
/// slug source and the copy, so one component serves both.
class ApiAccessTarget {
  /// The link slug behind `/s/{slug}` (a share's slug, or a response link's).
  final String slug;
  final String title;
  final String intro;

  /// True when the link is password-gated (shares only) — the password is
  /// woven into every URL.
  final bool gated;

  /// True when the link requires a verified identity, so the public web URLs
  /// won't resolve and the user must use the in-app path.
  final bool requireHandshake;

  /// Field/record keys available for the single-value endpoints. Drives the
  /// key dropdown; empty falls back to a free text input.
  final List<String> keys;

  /// When set, the sheet opens focused on this one field (a tapped value).
  final String? presetKey;

  const ApiAccessTarget({
    required this.slug,
    required this.title,
    required this.intro,
    this.gated = false,
    this.requireHandshake = false,
    this.keys = const [],
    this.presetKey,
  });
}

/// Opens the Web & API access drawer for [target].
Future<void> showApiAccessSheet(
  BuildContext context, {
  required ApiAccessTarget target,
}) {
  return showAppSheet(
    context: context,
    builder: (_) => _ApiAccessSheet(target: target),
  );
}

enum _Format { api, csv, contacts, calendar }

class _ApiAccessSheet extends StatefulWidget {
  final ApiAccessTarget target;

  const _ApiAccessSheet({required this.target});

  @override
  State<_ApiAccessSheet> createState() => _ApiAccessSheetState();
}

class _ApiAccessSheetState extends State<_ApiAccessSheet> {
  final Local<_Format> _formatState = Local(_Format.api);
  late final Local<String?> _selectedKeyState = Local(widget.target.presetKey);
  final _passwordCtrl = ObservableTextController();
  final _keyCtrl = ObservableTextController();

  _Format get _format => _formatState.value;
  String? get _selectedKey => _selectedKeyState.value;

  @override
  void initState() {
    super.initState();
    if (_selectedKey != null) _keyCtrl.text = _selectedKey!;
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  String get _base => Stores.api.baseUrl;
  String get _pull => '$_base/s/${widget.target.slug}';

  /// The effective selected key (dropdown or free text); null/empty = all.
  String? get _key {
    final k = widget.target.keys.isNotEmpty
        ? _selectedKey
        : _keyCtrl.text.trim();
    return (k == null || k.isEmpty) ? null : k;
  }

  /// The password query fragment: the real value once typed, else a visible
  /// placeholder so the shape of the URL is still clear.
  String get _pwParam {
    if (!widget.target.gated) return '';
    final pw = _passwordCtrl.text;
    return pw.isEmpty
        ? 'password=<password>'
        : 'password=${Uri.encodeQueryComponent(pw)}';
  }

  String? get _keyParam {
    final k = _key;
    return k == null ? null : 'key=${Uri.encodeQueryComponent(k)}';
  }

  String _url(String suffix, List<String?> params) {
    final all = params.where((p) => p != null && p.isNotEmpty).cast<String>();
    final q = all.isEmpty ? '' : '?${all.join('&')}';
    return '$_pull$suffix$q';
  }

  /// (label, url) endpoints for the selected format, built from the current
  /// key + password.
  List<(String, String)> _endpoints() {
    final k = _keyParam;
    final pw = _pwParam.isEmpty ? null : _pwParam;
    switch (_format) {
      case _Format.api:
        return [
          if (k == null)
            ('All fields · JSON', _url('', [pw]))
          else ...[
            ('This field · JSON', _url('', [k, pw])),
            ('This field · raw text', _url('', [k, 'raw=1', pw])),
          ],
        ];
      case _Format.csv:
        final csv = _url('.csv', [k, pw]);
        return [('CSV', csv), ('Google Sheets formula', '=IMPORTDATA("$csv")')];
      case _Format.contacts:
        return [
          ('vCard (.vcf)', _url('.vcf', [pw])),
          // CardDAV can't carry a password, so only offer it for open links.
          if (!widget.target.gated)
            ('CardDAV (live sync)', '$_base/dav/s/${widget.target.slug}/'),
        ];
      case _Format.calendar:
        final authority = Uri.tryParse(_base)?.authority ?? _base;
        return [
          ('iCalendar (.ics)', _url('.ics', [pw])),
          (
            'Calendar subscription',
            'webcal://$authority/s/${widget.target.slug}.ics'
                '${_pwParam.isEmpty ? '' : '?$_pwParam'}',
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final t = widget.target;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xxs,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Web & API access').header,
            AppSpacing.gapXxs,
            Text(t.intro).muted.small,

            if (t.requireHandshake) ...[
              AppSpacing.gapMd,
              _Note(
                icon: AppIcons.shieldLock,
                text:
                    'This link requires a verified identity, so these web URLs '
                    "won't resolve — use the in-app share instead.",
              ),
            ],

            AppSpacing.gapXl,
            const Text('Format').small,
            AppSpacing.gapSm,
            _formatBoxes(),

            AppSpacing.gapXl,
            _keySelector(),
            if (t.gated) ...[AppSpacing.gapMd, _passwordField()],

            AppSpacing.gapXl,
            ..._endpoints().map((e) => ApiUrlTile(label: e.$1, url: e.$2)),

            AppSpacing.gapMd,
            Text(_footnote()).muted.small,
          ],
        ),
      ),
    );
  }

  Widget _formatBoxes() {
    const boxes = [
      (_Format.api, AppIcons.server, 'API', 'JSON'),
      (_Format.csv, AppIcons.table, 'CSV', 'Spreadsheets'),
      (
        _Format.contacts,
        AppIcons.personBoundingBox,
        'Contacts',
        'vCard · CardDAV',
      ),
      (_Format.calendar, AppIcons.clock, 'Calendar', 'iCal'),
    ];
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final b in boxes)
          _FormatBox(
            icon: b.$2,
            title: b.$3,
            subtitle: b.$4,
            selected: _format == b.$1,
            onTap: () => _formatState.value = b.$1,
          ),
      ],
    );
  }

  Widget _keySelector() {
    // vCard/CardDAV/Calendar are whole-record formats — a single-field key
    // doesn't apply, so only offer the selector where it changes the result.
    if (_format == _Format.contacts || _format == _Format.calendar) {
      return const SizedBox.shrink();
    }
    final keys = widget.target.keys;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Field').small,
        AppSpacing.gapXs,
        if (keys.isNotEmpty)
          AppSelect<String?>(
            value: _selectedKey,
            placeholder: 'All fields',
            onChanged: (v) => _selectedKeyState.value = v,
            items: [
              const AppSelectItem<String?>(null, Text('All fields')),
              for (final k in keys) AppSelectItem<String?>(k, Text(k)),
            ],
          )
        else
          AppTextField(
            controller: _keyCtrl,
            hint: 'Field key (blank = all fields)',
          ),
      ],
    );
  }

  Widget _passwordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Link password').small,
        AppSpacing.gapXs,
        AppTextField(
          controller: _passwordCtrl,
          hint: 'Type it to get a ready-to-use URL',
          passwordToggle: true,
        ),
      ],
    );
  }

  String _footnote() {
    final parts = <String>[
      'Pull live data from anywhere — no app, no token. Revoking the link cuts '
          'off every URL instantly.',
    ];
    if (widget.target.gated) {
      parts.add(
        'The password becomes part of the URL, so it lands in server logs and '
        'browser history — prefer it for low-sensitivity convenience pulls.',
      );
    }
    if (_format == _Format.contacts && !widget.target.gated) {
      parts.add(
        'For CardDAV, add a contacts account using that URL as the '
        'server (any username/password).',
      );
    }
    return parts.join(' ');
  }
}

class _FormatBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _FormatBox({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.allLg,
      child: Container(
        width: 104,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.4)
              : null,
          borderRadius: AppRadius.allLg,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            AppSpacing.gapSm,
            Text(title).small,
            AppSpacing.gapXxs,
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ).muted.small,
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Note({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: AppRadius.allMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSecondaryContainer),
          AppSpacing.gapSm,
          Expanded(
            child: DefaultTextStyle.merge(
              style: TextStyle(color: scheme.onSecondaryContainer),
              child: Text(text).small,
            ),
          ),
        ],
      ),
    );
  }
}
