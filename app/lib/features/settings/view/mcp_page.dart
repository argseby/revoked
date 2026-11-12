import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// The release asset for the computer the app runs on. A phone has no AI
/// application to run it beside, so it is shown the Apple-silicon Mac.
({String asset, bool windows}) _target() {
  return switch (Abi.current()) {
    Abi.macosX64 => (asset: 'revoked-mcp-darwin-amd64', windows: false),
    Abi.linuxX64 => (asset: 'revoked-mcp-linux-amd64', windows: false),
    Abi.linuxArm64 => (asset: 'revoked-mcp-linux-arm64', windows: false),
    Abi.windowsX64 => (asset: 'revoked-mcp-windows-amd64.exe', windows: true),
    Abi.windowsArm64 => (asset: 'revoked-mcp-windows-arm64.exe', windows: true),
    _ => (asset: 'revoked-mcp-darwin-arm64', windows: false),
  };
}

/// Where the program is installed. Claude Desktop does not expand `~`, so its
/// config needs the home directory written out.
String _home(bool windows) {
  final home = Platform.environment[windows ? 'USERPROFILE' : 'HOME'];
  if (home != null && home.isNotEmpty && !Platform.isAndroid) {
    return _unsandboxed(home);
  }
  return windows ? r'C:\Users\name' : '/Users/name';
}

/// The sandboxed macOS app sees its container as `HOME`
/// (`/Users/name/Library/Containers/<bundle id>/Data`); the AI application
/// runs outside it, so the real home directory is the part before the
/// container.
String _unsandboxed(String home) {
  const marker = '/Library/Containers/';
  final i = home.indexOf(marker);
  return i > 0 ? home.substring(0, i) : home;
}

/// Settings → AI assistant (MCP): how to run `revoked-mcp` beside an AI
/// application, with the commands written for this computer and server.
class McpPage extends StatelessWidget {
  const McpPage({super.key});

  static const _download = '${AppConfig.repoUrl}/releases/latest/download';

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final server = Stores.api.baseUrl;
        final target = _target();
        final home = _home(target.windows);
        final binary = target.windows
            ? '$home\\revoked-mcp.exe'
            : '$home/.local/bin/revoked-mcp';
        final install = target.windows
            ? 'Invoke-WebRequest -OutFile "$binary" '
                  '$_download/${target.asset}'
            : 'mkdir -p ~/.local/bin && curl -fL -o ~/.local/bin/revoked-mcp '
                  '$_download/${target.asset} && chmod +x ~/.local/bin/revoked-mcp';
        final desktopPath = binary.replaceAll(r'\', r'\\');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppListGroup(
              title: 'Program',
              trailing: const SizedBox.shrink(),
              footer: Text(
                '${target.asset} from the latest release. Releases include '
                'macOS, Linux and Windows builds.',
              ),
              children: [_Command(text: install)],
            ),
            AppListGroup(
              title: 'Claude Code',
              trailing: const SizedBox.shrink(),
              footer: const Text(
                'REVOKED_SERVER is the server this app is signed in to. A '
                'different server means a different account.',
              ),
              children: [
                _Command(
                  text:
                      'claude mcp add revoked -e REVOKED_SERVER=$server '
                      '-- $binary',
                ),
              ],
            ),
            AppListGroup(
              title: 'Claude Desktop',
              trailing: const SizedBox.shrink(),
              footer: const Text(
                'Added under Settings → Developer → Edit Config. The change '
                'takes effect after a restart.',
              ),
              children: [
                _Command(
                  text:
                      '{\n'
                      '  "mcpServers": {\n'
                      '    "revoked": {\n'
                      '      "command": "$desktopPath",\n'
                      '      "env": { "REVOKED_SERVER": "$server" }\n'
                      '    }\n'
                      '  }\n'
                      '}',
                ),
              ],
            ),
            const AppListGroup(
              title: 'Connection',
              trailing: SizedBox.shrink(),
              footer: Text(
                'Connected assistants are listed under Connected tools. A '
                'connection lasts 90 days.',
              ),
              children: [
                _Step(
                  number: 1,
                  text: 'The assistant is asked to "Connect to Revoked."',
                ),
                _Step(
                  number: 2,
                  text:
                      'This app opens Connect AI assistant and shows a short '
                      'code. The assistant reports the same code.',
                ),
                _Step(
                  number: 3,
                  text:
                      'With matching codes, the permissions are selected and '
                      'confirmed with Connect. Otherwise, Decline.',
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A command or config block, shown as typed and copied in one tap.
class _Command extends StatelessWidget {
  final String text;

  const _Command({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(text).mono.small.selectable),
          AppSpacing.gapSm,
          AppButton(
            icon: AppIcons.copy,
            tooltip: 'Copy',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: () {
              Clipboard.setData(ClipboardData(text: text));
              AppToast.success(context, 'Copied to clipboard');
            },
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String text;

  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: AppRadius.allMd,
            ),
            child: Text(
              '$number',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ).small.bold,
          ),
          AppSpacing.gapMd,
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
