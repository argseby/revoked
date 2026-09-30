import 'package:flutter_test/flutter_test.dart';

import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/utils/deadline.dart';
import 'package:revoked_app/features/requests/view/request_groups.dart';

/// The Requests list leads with answers nobody has read yet and folds away
/// requests that no longer collect anything.
void main() {
  final now = DateTime.utc(2026, 9, 30, 12);

  DataRequest request({
    String status = 'active',
    int responses = 0,
    int max = 0,
    String? expiresAt,
  }) => DataRequest(
    id: 'r1',
    slug: 'slug',
    label: 'Tenant applications',
    status: status,
    identity: '',
    user: 'u',
    workspace: 'w',
    responseCount: responses,
    maxResponses: max,
    expiresAt: expiresAt,
  );

  test('unread answers lead, whatever the status', () {
    expect(requestGroup(request(), 2), RequestGroup.fresh);
    expect(requestGroup(request(status: 'completed'), 1), RequestGroup.fresh);
  });

  test('without news, open and closed requests part ways', () {
    expect(requestGroup(request(), 0), RequestGroup.open);
    expect(requestGroup(request(status: 'paused'), 0), RequestGroup.open);
    for (final s in ['revoked', 'expired', 'completed']) {
      expect(requestGroup(request(status: s), 0), RequestGroup.closed);
    }
  });

  test('the summary puts news, then the deadline, then the count', () {
    final r = request(
      responses: 11,
      max: 20,
      expiresAt: '2026-10-01T12:00:00Z',
    );
    expect(
      requestSummary(r, 3, now),
      '3 new · Expires in 1 day · 11 of 20 responses',
    );
  });

  test('a closed request does not warn about its deadline', () {
    final r = request(status: 'revoked', expiresAt: '2026-10-01T12:00:00Z');
    expect(requestSummary(r, 0, now), 'No responses yet');
  });

  test('response counts read as a sentence', () {
    expect(responsesSummary(request(responses: 1)), '1 response');
    expect(responsesSummary(request(responses: 5)), '5 responses');
  });

  group('expiryNotice', () {
    test('stays quiet far from the date', () {
      expect(expiryNotice('2026-12-01T00:00:00Z', now), isNull);
      expect(expiryNotice(null, now), isNull);
      expect(expiryNotice('not a date', now), isNull);
    });

    test('counts down hours on the last day', () {
      expect(expiryNotice('2026-09-30T13:00:00Z', now), 'Expires in 1 hour');
      expect(
        expiryNotice('2026-09-30T12:30:00Z', now),
        'Expires within the hour',
      );
    });
  });
}
