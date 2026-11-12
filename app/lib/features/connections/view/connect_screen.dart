import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/widgets/app_flow_scaffold.dart';
import 'package:revoked_app/core/widgets/app_consent_layout.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/features/connections/tool_return.dart';
import 'package:revoked_app/features/connections/view/tool_permissions.dart';
import 'package:revoked_app/features/works_with/view/works_with_chip.dart';

/// Owner-facing screen for a `revoked://connect?…` link: a tool asks to be
/// connected, the owner reads exactly what that allows, and agrees or not.
/// Either way they are sent back to the tool.
class ConnectScreen extends StatefulWidget {
  /// Null when the link was malformed; the screen then says so.
  final ConnectRequest? request;

  const ConnectScreen({super.key, required this.request});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _busy = Local<bool>(false);
  final _error = Local<String?>(null);
  final _done = Local<bool>(false);
  final _allowRevoke = Local<bool>(true);
  final _allowHandOver = Local<bool>(true);
  // Reading the vault is never on until the owner turns it on.
  final _allowVaultRead = Local<bool>(false);

  /// The tool's entry in Works with Revoked, matched by its address on this
  /// device; null for a tool that is not listed.
  late final _listing = widget.request == null
      ? null
      : Stores.worksWith.forOrigin(widget.request!.client);

  /// What the tool asks for beyond its reviewed entry. Those switches start
  /// off, and the screen says why.
  late final List<String> _undeclared = widget.request == null
      ? const []
      : _listing?.undeclaredForConnect(widget.request!) ?? const [];

  // What the tool asked for starts given, except what its listing does not
  // declare; the owner takes away what they don't want it to have.
  late final _granted = Local<Set<String>>({
    for (final k in widget.request?.permissions ?? const <String>[])
      if (!_undeclared.contains(k)) k,
  });
  late final _ownSection = Local<bool>(
    (widget.request?.section ?? false) && !_undeclared.contains('section'),
  );
  // Adding records unless the tool asked only to read.
  late final _sectionWrite = Local<bool>(
    !_asks('vault:read') || _asks('vault:write'),
  );
  // The connection the owner already made with this tool, if any.
  final _existing = Local<Connection?>(null);
  // Until it is known whether the owner already agreed to this tool.
  final _checking = Local<bool>(true);
  // Already connected: this browser was let in without asking again.
  final _reused = Local<bool>(false);
  // Already connected, and the page that asked collects its answer itself:
  // the owner is asked whether this browser may join.
  final _joining = Local<bool>(false);
  // The owner paused this tool, so nothing can be agreed until they lift it.
  final _pausedTool = Local<String?>(null);

  bool get _polls =>
      widget.request != null && toolWatchesThisServer(widget.request!.poll);

  /// Whether to offer reading the vault: the tool asked, and its answer goes
  /// back to its own address. The server refuses it for an answer collected
  /// by polling, which anyone could have set up for the owner.
  bool get _offersVault => widget.request?.vault == true && !_polls;

  @override
  void initState() {
    super.initState();
    Stores.invites.loadCatalogue();
    _reuse();
  }

  /// The asked-for permissions as the catalogue names them, in its order.
  /// One the catalogue doesn't name yet shows under its key.
  List<InvitePermission> get _asked {
    final asked = widget.request?.permissions ?? const <String>[];
    final catalogue = Stores.invites.catalogue;
    return [
      for (final key in asked)
        catalogue.firstWhere(
          (p) => p.key == key,
          orElse: () => InvitePermission(key: key, label: key, description: ''),
        ),
    ];
  }

  void _setPermission(String key, bool on) {
    final next = {..._granted.value};
    if (on) {
      next.add(key);
      if (key == 'vault:write' && _asks('vault:read')) next.add('vault:read');
    } else {
      next.remove(key);
      if (key == 'vault:read') next.remove('vault:write');
    }
    _granted.value = next;
  }

  bool _asks(String key) => widget.request?.permissions.contains(key) ?? false;

  /// What the tool may do once connected: the asked-for keys the owner left
  /// ticked, with the vault decided by its section. Left out, the server
  /// keeps what an earlier connect gave and a section means read and add.
  List<String>? _permissionsToSend(ConnectRequest r) {
    final readOnly = r.section && _ownSection.value && !_sectionWrite.value;
    if (r.permissions.isEmpty && !readOnly) return null;
    final held =
        _existing.value?.permissionKeys(Stores.invites.catalogue) ??
        const <String>[];
    final keys = {
      for (final k in held)
        if (!k.startsWith('vault:')) k,
      for (final k in r.permissions)
        if (_granted.value.contains(k) && !k.startsWith('vault:')) k,
    };
    if (r.section && _ownSection.value) {
      keys.add(_sectionWrite.value ? 'vault:write' : 'vault:read');
    } else {
      for (final k in r.permissions) {
        if (k.startsWith('vault:') && _granted.value.contains(k)) keys.add(k);
      }
    }
    return [
      for (final k in Connection.toolPermissions)
        if (keys.contains(k)) k,
    ];
  }

  /// The name of the tool's section: the one it already has, or the one
  /// connecting will create, named after the tool.
  (String, bool) _sectionLabel(ConnectRequest r) {
    final id = _existing.value?.section ?? '';
    if (id.isNotEmpty) {
      for (final s in Stores.vault.sections) {
        if (s.id == id) return (s.name.isEmpty ? s.key : s.name, false);
      }
    }
    return (r.name, true);
  }

  /// Whether the tool asks for more than [existing] already has, which the
  /// owner then has to agree to.
  Future<bool> _asksForMore(ConnectRequest r, Connection existing) async {
    if (r.section && !existing.hasOwnSection) return true;
    if (r.permissions.isEmpty) return false;
    await Stores.invites.loadCatalogue();
    final held = existing.permissionKeys(Stores.invites.catalogue);
    return r.permissions.any((k) => !held.contains(k));
  }

  /// A tool the owner already connected is not asked about again: another of
  /// their browsers gets in under what they agreed to, which stays as it is.
  /// The code still only reaches the tool's own origin, and only the page
  /// that asked can use it. Anything else — never connected, lapsed, refused
  /// — and the owner is asked.
  ///
  /// They are also asked when the page collects its answer itself: no return
  /// address ties that answer to one of their own browsers, so they confirm
  /// the code it shows.
  Future<void> _reuse() async {
    final r = widget.request;
    if (r == null) {
      _checking.value = false;
      return;
    }
    final existing = await Stores.connections.findByClient(r.client);
    if (existing != null) {
      _existing.value = existing;
      if (existing.section.isNotEmpty) Stores.vault.loadIfDue();
    }
    if (existing != null && existing.paused) {
      if (!mounted) return;
      _pausedTool.value = existing.id;
      _checking.value = false;
      return;
    }
    if (existing != null && _polls) {
      if (!mounted) return;
      _joining.value = true;
      _checking.value = false;
      return;
    }
    // Asking for the vault is asking for more than the owner agreed to, so
    // they are asked again rather than let through.
    if (existing != null &&
        ((_offersVault && !existing.allowVaultRead) ||
            await _asksForMore(r, existing))) {
      if (!mounted) return;
      _checking.value = false;
      return;
    }
    final grant = existing == null
        ? null
        : await Stores.connections.authorize(
            clientId: r.client,
            clientName: r.name,
            redirectUri: r.redirect,
            challenge: r.challenge,
            reuse: true,
          );
    if (!mounted) return;
    _checking.value = false;
    if (grant == null) return;
    _reused.value = true;
    _done.value = true;
    await returnToTool(
      redirect: r.redirect,
      state: r.state,
      status: 'connected',
      code: grant.code,
    );
  }

  Future<void> _connect() async {
    final r = widget.request!;
    final polls = _polls;
    _busy.value = true;
    _error.value = null;
    final grant = await Stores.connections.authorize(
      clientId: r.client,
      clientName: r.name,
      redirectUri: r.redirect,
      challenge: r.challenge,
      allowRevoke: _allowRevoke.value,
      allowHandOver: _allowHandOver.value,
      allowVaultRead: _offersVault ? _allowVaultRead.value : null,
      permissions: _permissionsToSend(r),
      section: r.section ? _ownSection.value : null,
      reuse: _joining.value,
      poll: polls,
    );
    _busy.value = false;
    if (grant == null) {
      _error.value =
          Stores.connections.errorMessage ?? '${r.name} could not be connected';
      return;
    }
    _reused.value = _joining.value;
    _done.value = true;
    // The page that asked picks the answer up where it is waiting.
    if (polls) return;
    await returnToTool(
      redirect: r.redirect,
      state: r.state,
      status: 'connected',
      code: grant.code,
    );
  }

  Future<void> _decline(BuildContext context) async {
    final r = widget.request;
    if (r != null && !_polls) {
      await returnToTool(
        redirect: r.redirect,
        state: r.state,
        status: 'declined',
      );
    }
    if (context.mounted) context.go(AppRoutes.overview);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final r = widget.request;
    final paused = _pausedTool.value != null;
    final consenting = r != null && !_checking.value && !_done.value && !paused;
    final joining = _joining.value;
    return AppFlowScaffold(
      title: !consenting
          ? 'Connect a tool'
          : joining
          ? '${r.name} is already connected'
          : 'Connect ${r.name}',
      subtitle: !consenting
          ? null
          : joining
          ? 'Access requested by another browser'
          : Uri.parse(r.client).host,
      closeLabel: consenting ? 'Decline and go back' : 'Back to the app',
      onClose: () => consenting || paused
          ? _decline(context)
          : context.go(AppRoutes.overview),
      bottomBar: consenting ? _decision(context) : null,
      feature: Feature.tools,
      body: r == null
          ? _invalid(context)
          : _checking.value
          ? const Center(child: AppSpinner(large: true))
          : paused
          ? _paused(context, r)
          : _done.value
          ? _connected(context, r)
          : _consent(context, r),
    );
  }

  Widget _invalid(BuildContext context) {
    return AppStatusMessage(
      icon: AppIcons.exclamationTriangle,
      accent: Theme.of(context).colorScheme.error,
      title: 'Invalid link',
      message: 'This tool cannot be connected. A new link is required from the tool.',
      actions: [
        AppButton(
          label: 'Back to the app',
          icon: AppIcons.arrowLeft,
          style: AppButtonStyle.accent,
          onTap: () => context.go(AppRoutes.overview),
        ),
      ],
    );
  }

  Widget _paused(BuildContext context, ConnectRequest r) {
    return AppStatusMessage(
      icon: AppIcons.pause,
      accent: Theme.of(context).colorScheme.onSurfaceVariant,
      title: '${r.name} is paused',
      message: 'The tool can be used again after activation.',
      actions: [
        AppButton(
          label: 'Open tool',
          icon: AppIcons.plug,
          style: AppButtonStyle.accent,
          onTap: () =>
              context.go(AppRoutes.connectedToolFor(_pausedTool.value!)),
        ),
        AppButton(
          label: 'Done',
          icon: AppIcons.check,
          style: AppButtonStyle.accent,
          onTap: () => _decline(context),
        ),
      ],
    );
  }

  Widget _connected(BuildContext context, ConnectRequest r) {
    return AppStatusMessage(
      icon: AppIcons.checkCircle,
      accent: Theme.of(context).colorScheme.success,
      title: _reused.value
          ? '${r.name} was already connected'
          : '${r.name} is connected',
      message:
          '${_reused.value ? 'This browser has access too, with the same '
                    'permissions as before. ' : ''}'
          '${_polls ? '${r.name} continues in the browser. ' : ''}'
          'Connections are managed under Settings → Workspace → '
          'Connected tools.',
      actions: [
        if (!_polls)
          AppButton(
            label: 'Back to ${r.name}',
            icon: AppIcons.boxArrowUpRight,
            onTap: () => returnToTool(
              redirect: r.redirect,
              state: r.state,
              status: 'connected',
            ),
          ),
        AppButton(
          label: 'Done',
          icon: AppIcons.check,
          style: AppButtonStyle.accent,
          onTap: () => context.go(AppRoutes.overview),
        ),
      ],
    );
  }

  /// The address is the one fact here the tool can't choose; its name is a
  /// claim, so the owner is pointed at the address.
  Widget _requester(ConnectRequest r) => AppConsentRequester(
    address: Uri.parse(r.client).authority,
    badge: WorksWithChip(origin: r.client),
  );

  Widget _consent(BuildContext context, ConnectRequest r) {
    final joining = _joining.value;
    return AppPageBody(
      centered: true,
      bottomPadding: AppSpacing.xxl,
      children: [
        if (joining) ...[
          _requester(r),
          if (_polls) ToolCheckCode(name: r.name, challenge: r.challenge),
        ],
        if (!joining)
          ToolPermissions(
            name: r.name,
            leading: [
              if (_polls) ToolCheckCode(name: r.name, challenge: r.challenge),
              if (_listing != null && _undeclared.isNotEmpty)
                WorksWithMismatchAlert(service: _listing, extra: _undeclared),
            ],
            requester: _requester(r),
            reasons: r.reasons,
            allowRevoke: _allowRevoke.value,
            allowHandOver: _allowHandOver.value,
            onAllowRevoke: (v) => _allowRevoke.value = v,
            onAllowHandOver: (v) => _allowHandOver.value = v,
            showVault: _offersVault,
            allowVaultRead: _allowVaultRead.value,
            onAllowVaultRead: (v) => _allowVaultRead.value = v,
            permissions: _asked,
            granted: _granted.value,
            onPermission: _setPermission,
            showSection: r.section,
            ownSection: _ownSection.value,
            onOwnSection: (v) => _ownSection.value = v,
            sectionName: _sectionLabel(r).$1,
            sectionIsNew: _sectionLabel(r).$2,
            reachedSectionNames: [
              if (r.section && _ownSection.value) _sectionLabel(r).$1,
              for (final section in Stores.vault.sections)
                if (_existing.value?.sections.contains(section.id) ?? false)
                  section.name.isEmpty ? section.key : section.name,
            ],
            sectionWrite: _sectionWrite.value,
            onSectionWrite: (v) => _sectionWrite.value = v,
          ),
        if (_error.value != null)
          AppAlert(destructive: true, content: Text(_error.value!)),
      ],
    );
  }

  Widget _decision(BuildContext context) {
    final busy = _busy.value;
    return AppActionBar(
      note: Text(
        _joining.value
            ? 'This browser receives the same permissions as before.'
            : 'Nothing is shared until approved. Connected tools can be '
                  'disconnected later.',
      ).muted.small,
      children: [
        AppButton(
          label: 'Decline',
          icon: AppIcons.x,
          style: AppButtonStyle.accent,
          onTap: busy ? null : () => _decline(context),
        ),
        AppButton(
          label: _joining.value ? 'Allow this browser' : 'Connect',
          icon: AppIcons.link,
          busy: busy,
          onTap: busy ? null : _connect,
        ),
      ],
    );
  }
}
