import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whether the page that asked collects the answer itself: it named the
/// server it watches ([poll]), and that is the one this app is signed into.
/// Then nothing is opened in a browser — which might not be the one that
/// asked — and the owner simply goes back to the page they came from.
///
/// An answer left to be collected is not tied to the owner's browser the way
/// a return address is, so it is never given unasked: the owner compares the
/// code the page shows with the one shown here.
bool toolWatchesThisServer(String poll) =>
    poll.isNotEmpty && ToolClient.origin(Stores.api.baseUrl) == poll;

/// Sends the owner back to the tool that sent them here — on a phone, the
/// jump that makes the round trip feel like one step.
///
/// The tool learns only what the app adds: its own [state] back, this
/// server's address (so a connected tool knows where to ask), what happened,
/// and — when the owner just connected it — the one-time code. Never a link
/// the owner did not hand over.
Future<bool> returnToTool({
  required String redirect,
  required String state,
  required String status,
  String? code,
  String? linkId,
}) {
  final uri = ToolClient.returnUri(redirect, {
    if (state.isNotEmpty) 'state': state,
    'status': status,
    'server': Stores.api.baseUrl,
    'code': ?code,
    'link': ?linkId,
  });
  // A tool that cannot be reached is not the owner's problem: the link exists
  // either way, and the screen still offers the way back.
  return launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  ).catchError((Object _) => false);
}
