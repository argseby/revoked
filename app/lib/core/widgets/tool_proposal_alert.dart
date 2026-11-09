import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/features/works_with/view/works_with_chip.dart';

/// Says which tool filled in a form. The name is the tool's own claim, so the
/// address it came from is shown beside it.
class ToolProposalAlert extends StatelessWidget {
  final ToolProposer proposer;

  const ToolProposalAlert({super.key, required this.proposer});

  @override
  Widget build(BuildContext context) {
    return AppAlert(
      leading: const Icon(AppIcons.askFor),
      title: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Proposed by ${proposer.label}'),
          if (!proposer.isEmpty) WorksWithChip(origin: proposer.client),
        ],
      ),
      content: Text(
        'Sent from ${proposer.host}. Tools choose their own names, so every detail should be checked before saving. A connected tool can follow what happens next.',
      ),
    );
  }
}
