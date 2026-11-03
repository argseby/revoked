import 'package:revoked_app/core/models/attestation_ask.dart';
import 'package:revoked_app/core/models/tool_client.dart';

/// A check a tool asks the owner to make, carried by a
/// `revoked://check?type=…&issuers=…&claims=…` link: asking someone to show
/// an attestation. The owner makes it and shows the code to the person.
class CheckProposal {
  final String type;
  final List<String> issuers;
  final List<String> claims;
  final ToolProposer proposer;

  const CheckProposal({
    this.type = '',
    this.issuers = const [],
    this.claims = const [],
    this.proposer = ToolProposer.none,
  });

  static const maxIssuers = 20;
  static const maxClaims = 50;
  static final _type = RegExp(r'^[\x21-\x7e]{1,255}$');
  static final _claim = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$');
  static final _domain = RegExp(r'^[a-z0-9.-]+(:[0-9]{1,5})?$');

  /// Reads a proposal from a link's query, or null when any part is invalid.
  static CheckProposal? fromQuery(Map<String, String> query) {
    final type = (query['type'] ?? '').trim();
    if (type.isNotEmpty && !_type.hasMatch(type)) return null;
    final issuers = AttestationAsk.splitClaims(
      (query['issuers'] ?? '').toLowerCase(),
    );
    if (issuers.length > maxIssuers || !issuers.every(_domain.hasMatch)) {
      return null;
    }
    final claims = AttestationAsk.splitClaims(query['claims'] ?? '');
    if (claims.length > maxClaims || !claims.every(_claim.hasMatch)) {
      return null;
    }
    final proposer = ToolProposer.fromQuery(query);
    if (proposer == null) return null;
    return CheckProposal(
      type: type,
      issuers: issuers,
      claims: claims,
      proposer: proposer,
    );
  }

  Map<String, String> toQuery() => {
    if (type.isNotEmpty) 'type': type,
    if (issuers.isNotEmpty) 'issuers': issuers.join(','),
    if (claims.isNotEmpty) 'claims': claims.join(','),
    ...proposer.toQuery(),
  };
}
