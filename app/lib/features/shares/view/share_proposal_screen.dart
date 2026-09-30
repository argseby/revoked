import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_flow_scaffold.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/share_proposal.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';
import 'package:revoked_app/features/connections/view/tool_permissions.dart';
import 'package:revoked_app/features/connections/tool_return.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/vault/view/template_field_fill.dart';

/// Owner-facing screen for a `revoked://p?…` link: a tool proposes a share,
/// the owner sees exactly what it would contain and creates it — or not.
///
/// The tool named keys, not values, and it never receives the link: the share
/// is created on the owner's server and its URL is shown here alone. So a tool
/// can organise what goes where without ever holding the data or the link.
///
/// A key the vault does not hold yet is filled in right here — typed, picked
/// or attached — never by leaving to set it up elsewhere. The answer is saved
/// to the vault once and found by every later proposal. When the proposal
/// names a template, it supplies each key's label and input and its section
/// holds the answers; otherwise the key is offered as text or a file and
/// filed under the tool's name.
class ShareProposalScreen extends StatefulWidget {
  /// Null when the link was malformed; the screen then says so.
  final ShareProposal? proposal;

  const ShareProposalScreen({super.key, required this.proposal});

  @override
  State<ShareProposalScreen> createState() => _ShareProposalScreenState();
}

/// One key the tool asked for, the vault record under it (if any), and the
/// template field that says how to fill it in (if the template has it).
class _Item {
  final String key;
  final models.Record? record;
  final TemplateField? field;

  const _Item(this.key, this.record, this.field);

  String get title {
    final label = record?.label ?? '';
    if (label.isNotEmpty) return label;
    return field?.title ?? humanize(key);
  }

  /// "net_income" -> "Net income", for a key no template describes.
  static String humanize(String key) {
    final words = key.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (words.isEmpty) return key;
    return words[0].toUpperCase() + words.substring(1);
  }
}

/// An item whose label another item on the same link shares — two records
/// both called "Name" — named after its key instead, which is unique.
class _NamedByKey extends _Item {
  const _NamedByKey(super.key, super.record, super.field);

  @override
  String get title => _Item.humanize(key);
}

class _ShareProposalScreenState extends State<ShareProposalScreen> {
  // What the server can stamp; any other file is refused on a stamped share.
  static const _stampableMimes = {'image/png', 'image/jpeg', 'application/pdf'};

  final _items = Local<List<_Item>>(const []);
  final _selected = Local<Set<String>>(const {});
  final _template = Local<Template?>(null);
  final _loading = Local<bool>(true);
  final _loadError = Local<String?>(null);
  final _sign = Local<bool>(true);
  final _submitting = Local<bool>(false);
  final _submitError = Local<String?>(null);
  final _createdSlug = Local<String?>(null);

  // The tool behind the proposal, when it names itself.
  final _connection = Local<Connection?>(null);
  final _connectNow = Local<bool>(true);

  /// Whether the owner has made the connection decisions and moved on to the
  /// link. A proposal that also asks to connect its tool is two decisions,
  /// taken one after the other: what the tool may do, then what the link
  /// holds — so what the tool will receive is shown once it follows from the
  /// choices already made, not above the choice that changes it.
  final _connectionDecided = Local<bool>(false);
  final _allowRevoke = Local<bool>(true);
  final _allowHandOver = Local<bool>(true);

  // What the tool is told on the way back, once the link exists.
  String? _code;
  String? _linkId;
  bool _handedOver = false;

  ShareProposal? get _proposal => widget.proposal;

  String get _toolName => _proposal == null || _proposal!.from.isEmpty
      ? 'the tool'
      : _proposal!.from;

  @override
  void initState() {
    super.initState();
    if (_proposal != null) _load();
  }

  bool _isHidden(models.Record r) => r.format == 'hidden';

  bool _isFile(models.Record r) => r.type == 'file';

  /// A file the stamp cannot mark would be refused when the share is read.
  bool _unstampable(models.Record r) =>
      _proposal!.stamp.isNotEmpty &&
      _isFile(r) &&
      !_stampableMimes.contains((r.mime ?? '').split(';').first);

  /// Hidden values and files the stamp would refuse start unticked: the owner
  /// opts them in, the tool cannot.
  bool _includedByDefault(models.Record r) => !_isHidden(r) && !_unstampable(r);

  Future<void> _load() async {
    final workspace = Stores.auth.activeWorkspace ?? '';
    // The vault's sections, so an answer lands in the template's existing
    // section rather than a second one of the same name; the templates, to
    // describe what is missing; the identities, to sign.
    await Future.wait([
      Stores.vault.loadRecords(),
      Stores.templates.loadTemplates(workspace),
      Stores.identities.loadIdentities().catchError((_) {}),
    ]);
    _template.value = _findTemplate(_proposal!.template);
    if (_proposal!.client.isNotEmpty) {
      _connection.value = await Stores.connections.findByClient(
        _proposal!.client,
      );
    }
    await _refresh(selectAll: true);
    _loading.value = false;
  }

  /// The proposal names its template; a built-in one wins over a workspace
  /// template that happens to share the name.
  Template? _findTemplate(String name) {
    if (name.isEmpty) return null;
    final wanted = name.toLowerCase();
    Template? found;
    for (final t in Stores.templates.templates) {
      if (t.name.toLowerCase() != wanted) continue;
      if (t.isBuiltin) return t;
      found ??= t;
    }
    return found;
  }

  /// Reads what the vault holds under the proposal's keys. With [selectAll]
  /// every includable record is ticked; otherwise only records that were not
  /// there before are added, so filling one in never undoes what the owner
  /// unticked.
  Future<void> _refresh({bool selectAll = false}) async {
    final keys = _proposal!.keys;
    try {
      // The keys matched [a-z0-9_-] when the link was read, so they cannot
      // break out of the filter. A record with requestedBy set is someone's
      // answer to one of your requests — theirs, not yours to pass on.
      final filter =
          '(${keys.map((k) => 'key = "$k"').join(' || ')}) && requestedBy = ""';
      final data = await Stores.api.get(
        '/api/collections/${AppConfig.recordsCollection}/records',
        queryParams: {'filter': filter, 'perPage': '200', 'sort': '-updated'},
      );
      final records = ((data['items'] as List<dynamic>?) ?? [])
          .map((e) => models.Record.fromJson(e as Map<String, dynamic>))
          .toList();
      // Newest first, so a key held twice resolves to its latest record.
      final byKey = <String, models.Record>{};
      for (final r in records) {
        byKey.putIfAbsent(r.key, () => r);
      }
      final template = _template.value;
      final fields = {
        if (template != null)
          for (final f in templateFieldsOf(template)) f.key: f,
      };

      final known = {
        for (final item in _items.value)
          if (item.record != null) item.record!.id,
      };
      final items = [for (final k in keys) _Item(k, byKey[k], fields[k])];
      final titles = <String, int>{};
      for (final item in items) {
        titles.update(item.title, (n) => n + 1, ifAbsent: () => 1);
      }
      _items.value = [
        for (final item in items)
          titles[item.title]! > 1
              ? _NamedByKey(item.key, item.record, item.field)
              : item,
      ];
      _selected.value = {
        if (!selectAll) ..._selected.value,
        for (final r in byKey.values)
          if (_includedByDefault(r) && (selectAll || !known.contains(r.id)))
            r.id,
      };
      _loadError.value = null;
    } catch (e) {
      _loadError.value = e.toString();
    }
  }

  /// Where an answer given here is filed: where the template put the field,
  /// or a section named after the tool that asked.
  ({String key, String name}) _sectionFor(TemplateField field) {
    final template = _template.value;
    if (template != null) return templateFieldSection(template, field);
    final name = _proposal!.from.isEmpty ? 'Shared' : _proposal!.from;
    return (key: sectionKeyFor(name), name: name);
  }

  Future<void> _fill(BuildContext context, TemplateField field) async {
    final section = _sectionFor(field);
    final saved = await fillTemplateFieldInteractively(
      context: context,
      toastContext: context,
      sectionKey: section.key,
      sectionName: section.name,
      field: field,
    );
    if (saved) await _refresh();
  }

  /// Changes a value the vault already holds, the way it would be filled in:
  /// typed, picked from a calendar, or replaced with another file. The record
  /// is edited in place — same record, still ticked, and every other link
  /// that shares it shows the new value too.
  Future<void> _edit(BuildContext context, _Item item) async {
    final r = item.record!;
    Stores.vault.rememberRecord(r);
    final type = _isFile(r)
        ? 'file'
        : RecordTypeUtils.supportedTypes.contains(r.type)
        ? r.type
        : 'text';
    await _fill(
      context,
      TemplateField(
        key: r.key,
        label: item.title,
        type: type,
        format: r.format,
        value: '',
        reason: item.field?.reason ?? '',
        group: '',
      ),
    );
  }

  /// Deletes a record from the vault, not just from this link: every other
  /// link that shares it loses it too, so the owner is asked first. The key
  /// then shows as missing again and can be filled in afresh.
  Future<void> _delete(BuildContext context, _Item item) async {
    final r = item.record!;
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete ${item.title}',
      message:
          'This removes it from your vault and from every link that shares '
          'it. This action cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    final ok = await Stores.vault.deleteRecord(r.id);
    if (!context.mounted) return;
    if (!ok) {
      AppToast.error(
        context,
        'Could not delete ${item.title}',
        subtitle: Stores.vault.errorMessage,
      );
      return;
    }
    _selected.value = {..._selected.value}..remove(r.id);
    await _refresh();
  }

  /// A key no template describes can hold either kind of value, so it is
  /// offered both ways.
  TemplateField _adhoc(String key, {required bool file}) => TemplateField(
    key: key,
    label: _Item.humanize(key),
    type: file ? 'file' : 'text',
    format: 'default',
    value: '',
    reason: '',
    group: '',
  );

  void _toggle(String id, bool on) {
    final next = {..._selected.value};
    if (on) {
      next.add(id);
    } else {
      next.remove(id);
    }
    _selected.value = next;
  }

  /// The slug is the only key to the recipient's page, so it comes from the
  /// CSPRNG and is long enough that guessing one is hopeless.
  static String _randomSlug([int length = 20]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  /// A tool that names itself, is not connected yet, and asked to be.
  bool get _canConnect =>
      _proposal!.client.isNotEmpty &&
      _proposal!.challenge.isNotEmpty &&
      _connection.value == null;

  /// Whether the page that asked watches this server for what becomes of
  /// the proposal, so nothing is opened in a browser to tell it.
  bool get _polls => toolWatchesThisServer(_proposal!.poll);

  /// A tool that is connected, asking from a browser that is not — which can
  /// be let in only where the page collects the answer itself.
  bool get _canJoin =>
      _proposal!.challenge.isNotEmpty && _connection.value != null && _polls;

  /// Whether the tool may be given this link: it is, or is about to be,
  /// connected, and the owner lets it receive links.
  bool get _canHandOver => _connection.value != null
      ? _connection.value!.allowHandOver
      : _canConnect && _connectNow.value && _allowHandOver.value;

  /// Whether the link will belong to a connected tool.
  bool get _toolAttached =>
      _connection.value != null || (_canConnect && _connectNow.value);

  /// Documents and hidden values are never handed to a tool: the owner sends
  /// a link that carries them themselves. (A per-record sensitivity flag is
  /// planned; until then every file and hidden value counts as sensitive.)
  bool _isSensitive(models.Record r) => _isHidden(r) || _isFile(r);

  bool get _sensitiveSelected => _items.value.any(
    (i) =>
        i.record != null &&
        _selected.value.contains(i.record!.id) &&
        _isSensitive(i.record!),
  );

  Future<void> _create() async {
    final p = _proposal!;
    final ids = [
      for (final item in _items.value)
        if (item.record != null && _selected.value.contains(item.record!.id))
          item.record!.id,
    ];
    if (ids.isEmpty) return;
    _submitting.value = true;
    _submitError.value = null;

    var connectionId = _connection.value?.id ?? '';
    if ((_canConnect || _canJoin) && _connectNow.value) {
      final grant = await Stores.connections.authorize(
        clientId: p.client,
        clientName: p.from,
        redirectUri: p.redirect,
        challenge: p.challenge,
        allowRevoke: _allowRevoke.value,
        allowHandOver: _allowHandOver.value,
        reuse: _canJoin,
        poll: _polls,
      );
      if (grant == null) {
        _submitting.value = false;
        _submitError.value =
            Stores.connections.errorMessage ?? 'Could not connect ${p.from}';
        return;
      }
      // A page that collects its answer itself is handed no code.
      _code = _polls ? null : grant.code;
      connectionId = grant.connectionId;
    }
    final handOver =
        connectionId.isNotEmpty && _canHandOver && !_sensitiveSelected;

    final slug = _randomSlug();
    final identity = _sign.value ? Stores.identities.primaryIdentity : null;
    final ok = await Stores.shares.createShare(
      slug: slug,
      label: p.label,
      user: Stores.auth.userId,
      workspace: Stores.auth.activeWorkspace ?? '',
      sections: const [],
      records: ids,
      identityId: identity?.id,
      expiresAt: p.days == null
          ? null
          : DateTime.now().add(Duration(days: p.days!)),
      watermark: p.stamp.isNotEmpty,
      watermarkText: p.stamp,
      purpose: p.purpose,
      connection: connectionId,
      ref: p.ref,
      handedOver: handOver,
    );
    _submitting.value = false;
    if (ok) {
      _linkId = Stores.shares.shares
          .where((l) => l.slug == slug)
          .map((l) => l.id)
          .firstOrNull;
      _handedOver = handOver;
      _createdSlug.value = slug;
      // Handed over, the tool can take it from here: straight back to it,
      // unless its page is watching and finds the link by itself.
      if (handOver && p.redirect.isNotEmpty && !_polls) await _backToTool();
    } else {
      _submitError.value =
          Stores.shares.errorMessage ?? 'Could not create the link';
    }
  }

  Future<void> _backToTool() => returnToTool(
    redirect: _proposal!.redirect,
    state: _proposal!.state,
    status: 'created',
    code: _code,
    linkId: _linkId,
  );

  /// Leaving without creating: a tool waiting for an answer hears "declined".
  Future<void> _leave(BuildContext context) async {
    final p = _proposal;
    if (p != null &&
        p.redirect.isNotEmpty &&
        _createdSlug.value == null &&
        !_polls) {
      await returnToTool(
        redirect: p.redirect,
        state: p.state,
        status: 'declined',
      );
    }
    if (context.mounted) context.go(AppRoutes.vault);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  /// The proposal also asks to connect its tool (or to let this browser in).
  bool get _hasConnectStep =>
      _proposal!.client.isNotEmpty && (_canConnect || _canJoin);

  /// On the first of the two steps: deciding about the connection.
  bool get _onConnectStep => _hasConnectStep && !_connectionDecided.value;

  Widget _build(BuildContext context) {
    final p = _proposal;
    final deciding = p != null && !_loading.value && _createdSlug.value == null;
    final connecting = deciding && _onConnectStep;
    final days = p?.days;
    final String? subtitle;
    if (p == null) {
      subtitle = null;
    } else if (connecting) {
      subtitle = 'Step 1 of 2 · then you review the link';
    } else {
      subtitle = [
        if (deciding && _hasConnectStep) 'Step 2 of 2',
        p.from.isEmpty ? 'Link proposal' : 'Link proposal from ${p.from}',
        if (days != null)
          'expires ${_formatDate(DateTime.now().add(Duration(days: days)))}',
      ].join(' · ');
    }
    return AppFlowScaffold(
      title: p == null
          ? 'Create a link'
          : connecting
          ? (_canJoin
                ? '${p.from} is already connected'
                : '${p.from} wants to connect')
          : p.label.isEmpty
          ? 'Create a link'
          : p.label,
      subtitle: subtitle,
      closeLabel: deciding ? 'Decline and go back' : 'Back to the app',
      onClose: () => _leave(context),
      bottomBar: !deciding
          ? null
          : connecting
          ? _connectDecision(context)
          : _decision(context, p),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final p = _proposal;
    if (p == null) {
      return AppStatusMessage(
        icon: AppIcons.exclamationTriangle,
        accent: Theme.of(context).colorScheme.error,
        title: 'This link doesn’t work',
        message:
            'It doesn’t describe a link that Revoked can create. Ask the tool '
            'that made it for a new one.',
        actions: [
          AppButton(
            label: 'Back to the app',
            icon: AppIcons.arrowLeft,
            style: AppButtonStyle.accent,
            onTap: () => _leave(context),
          ),
        ],
      );
    }
    if (_loading.value) {
      return const Center(child: AppSpinner(large: true));
    }
    final slug = _createdSlug.value;
    if (slug != null) return _buildCreated(context, p, slug);
    if (_onConnectStep) return _buildConnectStep(p);
    return _buildForm(context, p);
  }

  Widget _buildCreated(BuildContext context, ShareProposal p, String slug) {
    // A page that is watching needs nothing opened to carry on.
    final back = p.redirect.isNotEmpty && !_polls;
    return AppStatusMessage(
      icon: AppIcons.checkCircle,
      accent: Theme.of(context).colorScheme.success,
      title: 'Your link is ready',
      message: _handedOver
          ? '$_toolName has the link for ${p.label} and can show or send it '
                'for you. '
                '${_polls ? 'You can return to your browser; it carries on '
                          'by itself. ' : ''}'
                'You can see when it’s opened, or revoke it, under Links.'
          : 'Send it to the recipient of ${p.label}. Only you have the link; '
                '$_toolName doesn’t. You can see when it’s opened, or revoke '
                'it, under Links.',
      actions: [
        AppButton(
          label: 'Send link',
          icon: AppIcons.share,
          style: back ? AppButtonStyle.accent : AppButtonStyle.primary,
          onTap: () => showShareSheet(
            context: context,
            slug: slug,
            title: p.label,
            isRequest: false,
          ),
        ),
        if (back)
          AppButton(
            label: 'Back to $_toolName',
            icon: AppIcons.boxArrowUpRight,
            onTap: _backToTool,
          )
        else
          AppButton(
            label: 'Done',
            icon: AppIcons.check,
            style: AppButtonStyle.accent,
            onTap: () => context.go(AppRoutes.data),
          ),
      ],
    );
  }

  /// Step 1: who is asking, whether to connect it, and what it may do.
  Widget _buildConnectStep(ShareProposal p) {
    Widget choice(AppCheckRow check) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: check,
    );
    final connecting = _connectNow.value;

    return AppPageBody(
      bottomPadding: AppSpacing.xxl,
      children: [
        AppListGroup(
          title: 'Who is asking',
          trailing: const SizedBox.shrink(),
          footer: const Text(
            'A tool chooses its own name, so the address is what identifies '
            'it. Only continue if you recognise it.',
          ),
          children: [
            AppDetailRow(
              icon: AppIcons.globe,
              label: 'Address',
              value: Uri.parse(p.client).host,
            ),
            AppDetailRow(icon: AppIcons.tag, label: 'Name', value: p.from),
          ],
        ),
        AppListGroup(
          title: 'Connection',
          trailing: const SizedBox.shrink(),
          footer: Text(
            connecting
                ? 'Next, you review the link ${p.from} proposes.'
                : 'Next, you review the link. ${p.from} won’t learn anything '
                      'about it.',
          ),
          children: [
            if (_canConnect)
              choice(
                AppCheckRow(
                  label: 'Connect ${p.from}',
                  subtitle:
                      'It can then see the status of links it proposes. It '
                      'can never read your vault.',
                  value: connecting,
                  onChanged: (v) => _connectNow.value = v,
                ),
              ),
            if (_canJoin)
              choice(
                AppCheckRow(
                  label: 'Let this browser in',
                  subtitle:
                      'It isn’t connected in the browser you came from yet. '
                      'It gets the same permissions you granted before.',
                  value: connecting,
                  onChanged: (v) => _connectNow.value = v,
                ),
              ),
          ],
        ),
        if (connecting && _polls)
          ToolCheckCode(name: p.from, challenge: p.challenge),
        if (_canConnect && connecting)
          ToolPermissions(
            name: p.from,
            reasons: p.reasons,
            allowRevoke: _allowRevoke.value,
            allowHandOver: _allowHandOver.value,
            onAllowRevoke: (v) => _allowRevoke.value = v,
            onAllowHandOver: (v) => _allowHandOver.value = v,
          ),
      ],
    );
  }

  Widget _connectDecision(BuildContext context) {
    return AppActionBar(
      children: [
        AppButton(
          label: 'Decline',
          icon: AppIcons.x,
          style: AppButtonStyle.accent,
          onTap: () => _leave(context),
        ),
        AppButton(
          label: 'Continue',
          icon: AppIcons.arrowRight,
          onTap: () => _connectionDecided.value = true,
        ),
      ],
    );
  }

  /// Step 2's account of the tool: whether it is connected, and what it will
  /// learn about this link — which follows from the connection choices and
  /// from what the link holds, both settled above it.
  Widget _toolOutcome(ShareProposal p) {
    final connected = _connection.value != null;
    final String outcome;
    if (!_toolAttached) {
      outcome = '${p.from} won’t learn anything about this link.';
    } else if (!_canHandOver) {
      outcome =
          '${p.from} will see this link’s status, but not the link itself.';
    } else if (_sensitiveSelected) {
      outcome =
          '${p.from} will see this link’s status, but not the link itself: '
          'it contains documents or hidden values, so only you can send it.';
    } else {
      outcome =
          '${p.from} will receive this link and can show, copy or open it.';
    }
    final String status;
    if (connected && !_canJoin) {
      status = 'Connected';
    } else if (_connectNow.value) {
      status = _canJoin ? 'This browser will be let in' : 'Will be connected';
    } else {
      status = 'Not connected';
    }

    return AppListGroup(
      title: p.from,
      trailing: _hasConnectStep
          ? AppButton(
              icon: AppIcons.pen,
              label: 'Change',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () => _connectionDecided.value = false,
            )
          : const SizedBox.shrink(),
      children: [
        AppDetailRow(
          icon: AppIcons.globe,
          label: 'Address',
          value: Uri.parse(p.client).host,
        ),
        AppDetailRow(icon: AppIcons.link, label: 'Connection', value: status),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.info,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              AppSpacing.gapMd,
              Expanded(child: Text(outcome)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context, ShareProposal p) {
    final items = _items.value;
    final missing = items.where((i) => i.record == null).length;
    final selected = items
        .where(
          (i) => i.record != null && _selected.value.contains(i.record!.id),
        )
        .length;
    final identity = Stores.identities.primaryIdentity;
    return AppPageBody(
      bottomPadding: AppSpacing.xxl,
      children: [
        AppListGroup(
          title: 'What the link will contain · $selected of ${items.length}',
          trailing: const SizedBox.shrink(),
          footer: missing > 0
              ? const Text(
                  'Add what’s missing right here. It’s saved to your vault '
                  'once and ready for the next link.',
                )
              : null,
          children: [
            if (_loadError.value != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: AppAlert(
                  destructive: true,
                  content: Text(_loadError.value!),
                ),
              ),
            for (final item in items) _itemRow(context, item),
          ],
        ),
        if (p.stamp.isNotEmpty)
          AppListGroup(
            title: 'Watermark',
            trailing: const SizedBox.shrink(),
            footer: const Text(
              'Every file in the link is stamped with this text, so a copy '
              'can be traced back to it.',
            ),
            children: [
              AppDetailRow(
                icon: AppIcons.watermark,
                label: 'Stamp text',
                value: p.stamp,
              ),
            ],
          ),
        if (p.client.isNotEmpty) _toolOutcome(p),
        if (identity != null)
          AppListGroup(
            title: 'Signature',
            trailing: const SizedBox.shrink(),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                child: AppCheckRow(
                  label: 'Sign as ${identity.name}',
                  subtitle:
                      'The recipient can check that the link comes from you.',
                  value: _sign.value,
                  onChanged: (v) => _sign.value = v,
                ),
              ),
            ],
          ),
        if (_submitError.value != null)
          AppAlert(destructive: true, content: Text(_submitError.value!)),
      ],
    );
  }

  Widget _decision(BuildContext context, ShareProposal p) {
    return AppActionBar(
      children: [
        if (_hasConnectStep)
          AppButton(
            label: 'Back',
            icon: AppIcons.arrowLeft,
            style: AppButtonStyle.accent,
            onTap: _submitting.value
                ? null
                : () => _connectionDecided.value = false,
          )
        else
          AppButton(
            label: 'Decline',
            icon: AppIcons.x,
            style: AppButtonStyle.accent,
            onTap: _submitting.value ? null : () => _leave(context),
          ),
        AppButton(
          label: 'Create link',
          icon: AppIcons.link,
          busy: _submitting.value,
          onTap:
              _selected.value.isEmpty ||
                  _submitting.value ||
                  Stores.vault.isFillingField
              ? null
              : _create,
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Widget _itemRow(BuildContext context, _Item item) {
    final r = item.record;
    if (r == null) return _missingRow(context, item);

    final scheme = Theme.of(context).colorScheme;
    final unstampable = _unstampable(r);
    final on = _selected.value.contains(r.id);
    final String subtitle;
    if (_isFile(r)) {
      subtitle = r.filename ?? r.key;
    } else if (_isHidden(r)) {
      subtitle = 'Hidden value';
    } else if (r.type == 'boolean') {
      subtitle = r.value.toLowerCase() == 'true' ? 'Yes' : 'No';
    } else {
      subtitle = r.value;
    }
    final busy = Stores.vault.isFillingField;

    // Square like every row in a card; the card's clip rounds the ends.
    return InkWell(
      borderRadius: BorderRadius.zero,
      onTap: unstampable ? null : () => _toggle(r.id, !on),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            AppCheckbox(
              value: on,
              onChanged: unstampable ? null : (v) => _toggle(r.id, v ?? false),
            ),
            AppSpacing.gapSm,
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unstampable) ...[
                        AppSpacing.gapSm,
                        const AppBadge(
                          label: 'Can’t be stamped',
                          variant: AppBadgeVariant.destructive,
                        ),
                      ] else if (_isHidden(r)) ...[
                        AppSpacing.gapSm,
                        const AppBadge(
                          label: 'Hidden',
                          icon: AppIcons.eyeSlash,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ).muted.small,
                ],
              ),
            ),
            AppSpacing.gapSm,
            AppButton(
              icon: _isFile(r) ? AppIcons.filePlus : AppIcons.pen,
              tooltip: _isFile(r)
                  ? 'Replace ${item.title}'
                  : 'Edit ${item.title}',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: busy ? null : () => _edit(context, item),
            ),
            AppSpacing.gapXs,
            AppButton(
              icon: AppIcons.trash,
              tooltip: 'Delete ${item.title}',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: busy ? null : () => _delete(context, item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _missingRow(BuildContext context, _Item item) {
    final scheme = Theme.of(context).colorScheme;
    final field = item.field;
    final busy = Stores.vault.isFillingField;
    Widget add(TemplateField f) => AppButton(
      label: f.isFile ? 'Add file' : 'Add',
      icon: f.isFile ? AppIcons.filePlus : AppIcons.plus,
      style: AppButtonStyle.accent,
      size: AppButtonSize.small,
      onTap: busy ? null : () => _fill(context, f),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.warningContainer,
              borderRadius: AppRadius.allMd,
            ),
            child: Icon(
              RecordTypeUtils.icon(field?.type ?? 'text'),
              size: 18,
              color: scheme.warning,
            ),
          ),
          AppSpacing.gapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title),
                DefaultTextStyle.merge(
                  style: TextStyle(color: scheme.warning),
                  child: const Text('Not in your vault yet').small,
                ),
              ],
            ),
          ),
          AppSpacing.gapSm,
          if (field != null)
            add(
              TemplateField(
                key: field.key,
                label: item.title,
                type: field.type,
                format: field.format,
                value: field.value,
                reason: field.reason,
                group: field.group,
                sectionKey: field.sectionKey,
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                add(_adhoc(item.key, file: false)),
                add(_adhoc(item.key, file: true)),
              ],
            ),
        ],
      ),
    );
  }
}
