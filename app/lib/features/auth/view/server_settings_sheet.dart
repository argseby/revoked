import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:http/http.dart' as http;

import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// Opens the server-settings drawer used from the login / register screens so
/// the user can point the app at a different backend (IP + port or a domain).
Future<void> openServerSettingsSheet(BuildContext context) {
  return showAppSheet(
    context: context,
    builder: (_) => const ServerSettingsSheet(),
  );
}

class ServerSettingsSheet extends StatefulWidget {
  const ServerSettingsSheet({super.key});

  @override
  State<ServerSettingsSheet> createState() => _ServerSettingsSheetState();
}

class _ServerSettingsSheetState extends State<ServerSettingsSheet> {
  late final TextEditingController _controller;
  bool _testing = false;
  bool? _reachable; // null = not tested yet
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: Stores.api.baseUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final url = ApiClient.normalizeServerUrl(_controller.text);
    setState(() {
      _testing = true;
      _reachable = null;
      _testMessage = null;
    });
    try {
      final resp = await http
          .get(Uri.parse('$url/api/health'))
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      final ok = resp.statusCode == 200;
      setState(() {
        _testing = false;
        _reachable = ok;
        _testMessage = ok
            ? 'Connected to $url'
            : 'Reached $url but got HTTP ${resp.statusCode}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _reachable = false;
        _testMessage = 'Could not reach $url';
      });
    }
  }

  Future<void> _save() async {
    final saved = await Stores.api.setBaseUrl(_controller.text);
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(context, 'Server set to $saved');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              Icon(AppIcons.server, size: 18, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              const Text('Server').header,
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            'Choose which backend this app talks to. Enter an address like '
            '192.168.1.5:3000 or https://your-domain.com.',
          ).muted.small,
          const SizedBox(height: AppSpacing.lg),
          const Text('Server address').small,
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: _controller,
            hint: 'http://192.168.1.5:3000',
            keyboardType: TextInputType.url,
            autofocus: true,
            onChanged: (_) {
              if (_reachable != null || _testMessage != null) {
                setState(() {
                  _reachable = null;
                  _testMessage = null;
                });
              }
            },
          ),
          if (_testMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  _reachable == true ? AppIcons.checkCircle : AppIcons.xCircle,
                  size: 16,
                  color: _reachable == true ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_testMessage!).small),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  icon: AppIcons.shieldCheck,
                  label: 'Test',
                  style: AppButtonStyle.accent,
                  busy: _testing,
                  onTap: _test,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  icon: AppIcons.checkCircle,
                  label: 'Save',
                  onTap: _save,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Reset to default',
              onTap: () {
                _controller.text = Stores.api.defaultBaseUrl;
                setState(() {
                  _reachable = null;
                  _testMessage = null;
                });
              },
              style: AppButtonStyle.accent,
            ),
          ),
        ],
      ),
    );
  }
}
