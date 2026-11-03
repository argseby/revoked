import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/models/attestation_ask.dart';
import 'package:revoked_app/core/models/check_proposal.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/refresh_on_entry.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';
import 'package:revoked_app/core/widgets/device_key_alert.dart';
import 'package:revoked_app/features/attestations/view/attestation_check_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_create_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestations_section.dart';

/// What other parties attested about this person, and what this workspace
/// attested about others. Attesting and asking start from New; showing one
/// starts from the link a service sends, opened like any other link.
///
/// Opened from someone's ask link, it starts the Attest form filled in.
class AttestationsScreen extends StatefulWidget {
  final AttestationAsk? ask;

  /// A tool's proposal to ask someone to show one; opens the check form.
  final CheckProposal? check;

  /// 0 held, 1 issued, 2 checked.
  final int initialTab;

  const AttestationsScreen({
    super.key,
    this.ask,
    this.check,
    this.initialTab = 0,
  });

  @override
  State<AttestationsScreen> createState() => _AttestationsScreenState();
}

class _AttestationsScreenState extends State<AttestationsScreen>
    with RefreshOnEntry {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ask = widget.ask;
      final check = widget.check;
      if ((ask == null && check == null) || !mounted) return;
      // The ask lives in the address only until it has filled in the form,
      // so returning to the tab does not open it again.
      context.go(AppRoutes.attestations);
      if (ask != null) {
        showAttestationCreateSheet(context, ask: ask);
      } else {
        openAttestationCheckSheet(context, proposal: check);
      }
    });
  }

  @override
  void refresh() {
    Stores.identities.loadIfDue();
    Stores.credentials.loadIfDue();
    Stores.attestations.loadIfDue();
    Stores.attestationChecks.loadIfDue();
  }

  @override
  Widget build(BuildContext context) {
    final h = AppSpacing.screenH(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(h, AppSpacing.md, h, 0),
          child: const DeviceKeyAlert(),
        ),
        Expanded(
          child: Observer(
            builder: (_) => AppTabs(
              labels: [
                _counted('Held', Stores.credentials.credentials.length),
                _counted('Issued', Stores.attestations.attestations.length),
                _counted('Checked', Stores.attestationChecks.checks.length),
              ],
              initialIndex: widget.initialTab,
              views: const [
                HeldAttestations(),
                IssuedAttestations(),
                CheckedAttestations(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _counted(String label, int count) =>
    count == 0 ? label : '$label · $count';
