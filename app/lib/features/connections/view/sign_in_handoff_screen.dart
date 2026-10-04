import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_flow_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen for a `revoked://signin?…` link: a service asks to sign its user in
/// and does not know their server. The app does — the one it is signed into —
/// and opens that server's authorization page in the browser right away.
/// Who is asking and what they get is decided there, on the consent page,
/// after the passkey; this screen only says where it went.
class SignInHandoffScreen extends StatefulWidget {
  /// Null when the link was malformed; the screen then says so.
  final SignInRequest? request;

  const SignInHandoffScreen({super.key, required this.request});

  @override
  State<SignInHandoffScreen> createState() => _SignInHandoffScreenState();
}

class _SignInHandoffScreenState extends State<SignInHandoffScreen> {
  final _failed = Local<bool>(false);

  String get _server => Stores.api.baseUrl;

  @override
  void initState() {
    super.initState();
    if (widget.request != null) _open();
  }

  Future<void> _open() async {
    final uri = widget.request!.authorizeUri(_server);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    _failed.value = !ok;
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final r = widget.request;
    return AppFlowScaffold(
      title: 'Sign in with Revoked',
      subtitle: r == null ? null : 'Requested by ${r.clientHost}',
      closeLabel: 'Back to the app',
      onClose: () => context.go(AppRoutes.vault),
      body: r == null ? _invalid(context) : _handedOff(context, r),
    );
  }

  Widget _invalid(BuildContext context) {
    return AppStatusMessage(
      icon: AppIcons.exclamationTriangle,
      accent: Theme.of(context).colorScheme.error,
      title: 'This link doesn’t work',
      message:
          'It doesn’t describe a sign-in that Revoked can continue. Start '
          'signing in again on the service.',
      actions: [
        AppButton(
          label: 'Back to the app',
          icon: AppIcons.arrowLeft,
          style: AppButtonStyle.accent,
          onTap: () => context.go(AppRoutes.vault),
        ),
      ],
    );
  }

  Widget _handedOff(BuildContext context, SignInRequest r) {
    final server = Uri.tryParse(_server)?.authority ?? _server;
    final failed = _failed.value;
    return AppStatusMessage(
      icon: failed ? AppIcons.exclamationTriangle : AppIcons.boxArrowUpRight,
      accent: failed
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.success,
      title: failed ? 'The browser didn’t open' : 'Continue in your browser',
      message: failed
          ? 'Signing in to ${r.clientHost} continues on your Revoked server, '
                '$server, in the browser. Try opening it again.'
          : '${r.clientHost} asked to sign you in. Your Revoked server, '
                '$server, asks for your passkey in the browser and shows '
                'what ${r.clientHost} would learn before anything is shared.',
      actions: [
        AppButton(
          label: 'Open again',
          icon: AppIcons.boxArrowUpRight,
          onTap: _open,
        ),
        AppButton(
          label: 'Done',
          icon: AppIcons.check,
          style: AppButtonStyle.accent,
          onTap: () => context.go(AppRoutes.vault),
        ),
      ],
    );
  }
}
