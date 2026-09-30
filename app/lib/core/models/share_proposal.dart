import 'package:revoked_app/core/models/tool_client.dart';

/// A share a tool asks the owner to create, carried by a
/// `revoked://p?label=…&keys=…` link.
///
/// The tool names only record keys and the share's settings — never values —
/// and never learns the link: the app creates the share on the owner's own
/// server and hands the URL to the owner alone. That is what lets a tool
/// organise sharing without ever holding the data it organises.
///
/// Every field is untrusted input from whoever built the link, so a proposal
/// that is malformed in any part is refused whole rather than repaired.
///
/// A tool that names itself ([client], its origin) can ask to be sent back to
/// [redirect] afterwards, be connected on the way ([challenge]), and tag the
/// link with its own [ref] — so, once connected, it can follow what became of
/// what it proposed without ever holding the data.
class ShareProposal {
  /// Names the share, e.g. the flat an application is for.
  final String label;

  /// Record keys the tool asks to include, in the order it asked.
  final List<String> keys;

  /// Stamped on every file the share serves; empty for no stamp.
  final String stamp;

  /// Days until the share expires; null for no expiry.
  final int? days;

  /// A server-known link purpose (`application`), or empty.
  final String purpose;

  /// The name the tool gives itself. Unverified — shown as a claim only.
  final String from;

  /// A template, by name, that describes the keys — their labels and types —
  /// so a key the vault does not hold yet can be filled in on the spot.
  final String template;

  /// The tool's origin, when it names itself; empty otherwise.
  final String client;

  /// Where to send the owner back to, on [client]'s origin.
  final String redirect;

  /// The tool's own value, handed back unchanged.
  final String state;

  /// PKCE S256 challenge — present when the tool asks to be connected now.
  final String challenge;

  /// The tool's own reference for this link, e.g. which flat it is for.
  final String ref;

  /// Why the tool asks for the optional permissions, when it connects now.
  final ToolReasons reasons;

  /// The server the page that asked is watching for what becomes of this
  /// proposal, as an origin; empty when it waits to be sent back instead.
  final String poll;

  const ShareProposal({
    required this.label,
    required this.keys,
    this.stamp = '',
    this.days,
    this.purpose = '',
    this.from = '',
    this.template = '',
    this.client = '',
    this.redirect = '',
    this.state = '',
    this.challenge = '',
    this.ref = '',
    this.reasons = const ToolReasons(),
    this.poll = '',
  });

  static const maxKeys = 50;
  // links.watermarkText holds at most 120 characters, and the label is often
  // stamped in its place.
  static const maxLabel = 120;
  static const maxStamp = 120;
  static const maxFrom = 40;
  static const maxTemplate = 80;
  static const maxRef = 80;
  static const maxDays = 365;

  /// The purposes the server accepts (util.LinkPurposes).
  static const purposes = {'application'};

  static final _keyPattern = RegExp(r'^[a-z0-9_-]{1,64}$');
  static final _controlChars = RegExp(r'[\x00-\x1F\x7F]');

  /// One line of plain text: control characters become spaces, runs of
  /// whitespace collapse. Null when it is longer than [max] afterwards.
  static String? _line(String? raw, int max) {
    final s = (raw ?? '')
        .replaceAll(_controlChars, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s.length > max ? null : s;
  }

  /// Reads a proposal from a link's query, or null when any part is invalid.
  static ShareProposal? fromQuery(Map<String, String> query) {
    final label = _line(query['label'], maxLabel);
    if (label == null || label.isEmpty) return null;

    final keys = <String>[];
    for (final part in (query['keys'] ?? '').split(',')) {
      final key = part.trim();
      if (key.isEmpty) continue;
      if (!_keyPattern.hasMatch(key)) return null;
      if (!keys.contains(key)) keys.add(key);
    }
    if (keys.isEmpty || keys.length > maxKeys) return null;

    final stamp = _line(query['stamp'], maxStamp);
    if (stamp == null) return null;

    int? days;
    final rawDays = query['days'];
    if (rawDays != null && rawDays.isNotEmpty) {
      days = int.tryParse(rawDays);
      if (days == null || days < 1 || days > maxDays) return null;
    }

    final purpose = query['purpose'] ?? '';
    if (purpose.isNotEmpty && !purposes.contains(purpose)) return null;
    // The server refuses an unstamped application link; say so here, before
    // the owner has confirmed anything.
    if (purpose == 'application' && stamp.isEmpty) return null;

    final from = _line(query['from'], maxFrom);
    if (from == null) return null;

    final template = _line(query['template'], maxTemplate);
    if (template == null) return null;

    final ref = _line(query['ref'], maxRef);
    if (ref == null) return null;

    // Each of these needs the one before it: no return address without a
    // tool to return to, no connection without a way back to deliver it.
    var client = '';
    final rawClient = query['client'] ?? '';
    if (rawClient.isNotEmpty) {
      final origin = ToolClient.origin(rawClient);
      if (origin == null) return null;
      client = origin;
    }
    final redirect = (query['redirect'] ?? '').trim();
    if (redirect.isNotEmpty &&
        (client.isEmpty || !ToolClient.redirectWithin(redirect, client))) {
      return null;
    }
    final state = query['state'] ?? '';
    if (state.isNotEmpty &&
        (redirect.isEmpty || !ToolClient.validState(state))) {
      return null;
    }
    final challenge = query['challenge'] ?? '';
    if (challenge.isNotEmpty &&
        (state.isEmpty || !ToolClient.validChallenge(challenge))) {
      return null;
    }

    final reasons = ToolReasons.fromQuery(query);
    if (reasons == null) return null;

    final poll = ToolClient.pollOrigin(query['poll']);
    if (poll == null || (poll.isNotEmpty && client.isEmpty)) return null;

    return ShareProposal(
      label: label,
      keys: keys,
      stamp: stamp,
      days: days,
      purpose: purpose,
      from: from.isEmpty && client.isNotEmpty ? Uri.parse(client).host : from,
      template: template,
      client: client,
      redirect: redirect,
      state: state,
      challenge: challenge,
      ref: ref,
      reasons: reasons,
      poll: poll,
    );
  }

  /// The query [fromQuery] reads back, with empty fields left out.
  Map<String, String> toQuery() => {
    'label': label,
    'keys': keys.join(','),
    if (stamp.isNotEmpty) 'stamp': stamp,
    if (days != null) 'days': '$days',
    if (purpose.isNotEmpty) 'purpose': purpose,
    if (from.isNotEmpty) 'from': from,
    if (template.isNotEmpty) 'template': template,
    if (client.isNotEmpty) 'client': client,
    if (redirect.isNotEmpty) 'redirect': redirect,
    if (state.isNotEmpty) 'state': state,
    if (challenge.isNotEmpty) 'challenge': challenge,
    if (ref.isNotEmpty) 'ref': ref,
    ...reasons.toQuery(),
    if (poll.isNotEmpty) 'poll': poll,
  };
}
