import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/features/connections/tool_return.dart';
import 'package:revoked_app/features/connections/view/tool_permissions.dart';

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
  // Until it is known whether the owner already agreed to this tool.
  final _checking = Local<bool>(true);
  // Already connected: this browser was let in without asking again.
  final _reused = Local<bool>(false);
  // Already connected, and the page that asked collects its answer itself:
  // the owner is asked whether this browser may join.
  final _joining = Local<bool>(false);

  bool get _polls =>
      widget.request != null && toolWatchesThisServer(widget.request!.poll);

  @override
  void initState() {
    super.initState();
    _reuse();
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
    if (existing != null && _polls) {
      if (!mounted) return;
      _joining.value = true;
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
      reuse: _joining.value,
      poll: polls,
    );
    _busy.value = false;
    if (grant == null) {
      _error.value =
          Stores.connections.errorMessage ?? 'Could not connect ${r.name}';
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
    if (context.mounted) context.go(AppRoutes.vault);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final r = widget.request;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: r == null
                  ? _invalid(context)
                  : _checking.value
                  ? const Center(child: CircularProgressIndicator())
                  : _done.value
                  ? _connected(context, r)
                  : _consent(context, r),
            ),
          ),
        ),
      ),
    );
  }

  Widget _invalid(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(AppIcons.exclamationTriangle, size: 40),
        AppSpacing.gapLg,
        const Text('This link doesn’t work').header,
        AppSpacing.gapSm,
        const Text(
          'It does not describe a tool revoked can connect.',
          textAlign: TextAlign.center,
        ).muted,
        AppSpacing.gapXl,
        AppButton(
          label: 'Back to app',
          icon: AppIcons.arrowLeft,
          style: AppButtonStyle.accent,
          onTap: () => context.go(AppRoutes.vault),
        ),
      ],
    );
  }

  Widget _connected(BuildContext context, ConnectRequest r) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(AppIcons.checkCircle, size: 40),
        AppSpacing.gapLg,
        Text(
          _reused.value
              ? '${r.name} was already connected'
              : '${r.name} is connected',
        ).header,
        AppSpacing.gapSm,
        Text(
          '${_reused.value ? 'This browser can now use it too, with what you '
                    'allowed before. ' : ''}'
          '${_polls ? 'Go back to your browser: ${r.name} carries on by '
                    'itself. ' : ''}'
          'You can review or disconnect it under Settings → Workspace → '
          'Connected tools.',
          textAlign: TextAlign.center,
        ).muted,
        AppSpacing.gapXl,
        Wrap(
          spacing: AppSpacing.sm,
          children: [
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
              onTap: () => context.go(AppRoutes.vault),
            ),
          ],
        ),
      ],
    );
  }

  Widget _consent(BuildContext context, ConnectRequest r) {
    final joining = _joining.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          joining
              ? '${r.name} is already connected'
              : '${r.name} wants to connect',
        ).header,
        AppSpacing.gapXs,
        Text(
          joining
              ? 'From ${Uri.parse(r.client).host}. Another browser is asking '
                    'to use it, with what you allowed before.'
              : 'From ${Uri.parse(r.client).host}. The tool chose its own '
                    'name, so check the address.',
        ).muted.small,
        AppSpacing.gapXl,
        if (!joining)
          AppCard(
            child: ToolPermissions(
              name: r.name,
              reasons: r.reasons,
              allowRevoke: _allowRevoke.value,
              allowHandOver: _allowHandOver.value,
              onAllowRevoke: (v) => _allowRevoke.value = v,
              onAllowHandOver: (v) => _allowHandOver.value = v,
            ),
          ),
        if (_polls) ...[
          if (!joining) AppSpacing.gapLg,
          AppCard(
            child: ToolCheckCode(name: r.name, challenge: r.challenge),
          ),
        ],
        if (_error.value != null) ...[
          AppSpacing.gapLg,
          AppAlert(destructive: true, content: Text(_error.value!)),
        ],
        AppSpacing.gapXl,
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppButton(
              label: 'Decline',
              icon: AppIcons.x,
              style: AppButtonStyle.accent,
              onTap: _busy.value ? null : () => _decline(context),
            ),
            AppButton(
              label: joining ? 'Let this browser in' : 'Connect',
              icon: AppIcons.link,
              busy: _busy.value,
              onTap: _busy.value ? null : _connect,
            ),
          ],
        ),
      ],
    );
  }
}
