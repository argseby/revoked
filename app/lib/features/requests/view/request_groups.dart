import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/utils/deadline.dart';

/// Where a request sits in the Requests list: answers waiting to be read
/// first, finished requests last.
enum RequestGroup { fresh, open, closed }

/// A request that no longer collects answers.
bool isRequestClosed(DataRequest r) =>
    r.status == 'revoked' || r.status == 'expired' || r.status == 'completed';

/// [unread] is how many of its responses the owner has not opened yet. A
/// closed request with unread answers still leads — its last answer is news.
RequestGroup requestGroup(DataRequest r, int unread) {
  if (unread > 0) return RequestGroup.fresh;
  return isRequestClosed(r) ? RequestGroup.closed : RequestGroup.open;
}

/// "11 of 20 responses", "1 response", "No responses yet".
String responsesSummary(DataRequest r) {
  final n = r.responseCount;
  if (r.maxResponses > 0) return '$n of ${r.maxResponses} responses';
  if (n == 0) return 'No responses yet';
  return '$n ${n == 1 ? 'response' : 'responses'}';
}

/// The row's one line: news first, then a deadline, then the count.
String requestSummary(DataRequest r, int unread, DateTime now) {
  final parts = <String>[
    if (unread > 0) '$unread new',
    if (!isRequestClosed(r)) ?expiryNotice(r.expiresAt, now),
    responsesSummary(r),
  ];
  return parts.join(' · ');
}
