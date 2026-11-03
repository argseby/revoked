import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';

/// Says which tool filled in a form. The name is the tool's own claim, so the
/// address it came from is shown beside it.
class ToolProposalAlert extends StatelessWidget {
  final ToolProposer proposer;

  const ToolProposalAlert({super.key, required this.proposer});

  @override
  Widget build(BuildContext context) {
    return AppAlert(
      leading: const Icon(AppIcons.askFor),
      title: Text('Proposed by ${proposer.label}'),
      content: Text(
        'It came from ${proposer.host}, and any tool can pick its own name. '
        'Check every detail before you save. If you connected this tool, it '
        'can follow what happens next.',
      ),
    );
  }
}
