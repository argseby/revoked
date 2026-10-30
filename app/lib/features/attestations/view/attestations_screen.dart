import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/models/attestation_ask.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';
import 'package:revoked_app/core/widgets/device_key_alert.dart';
import 'package:revoked_app/features/attestations/view/attestation_create_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestations_section.dart';

/// What other parties attested about this person, and what this workspace
/// attested about others. Attesting and asking start from New; showing one
/// starts from the link a service sends, opened like any other link.
///
/// Opened from someone's ask link, it starts the Attest form filled in.
class AttestationsScreen extends StatefulWidget {
  final AttestationAsk? ask;

  const AttestationsScreen({super.key, this.ask});

  @override
  State<AttestationsScreen> createState() => _AttestationsScreenState();
}

class _AttestationsScreenState extends State<AttestationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Stores.identities.loadIdentities();
      Stores.credentials.load();
      Stores.attestations.load();
      final ask = widget.ask;
      if (ask == null || !mounted) return;
      // The ask lives in the address only until it has filled in the form,
      // so returning to the tab does not open it again.
      context.go(AppRoutes.attestations);
      showAttestationCreateSheet(context, ask: ask);
    });
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
          child: AppTabs(
            labels: const ['Held', 'Issued'],
            views: const [
              AppPageBody(children: [HeldAttestations()]),
              AppPageBody(children: [IssuedAttestations()]),
            ],
          ),
        ),
      ],
    );
  }
}
