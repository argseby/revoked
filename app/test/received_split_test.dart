import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/bookmarks/view/bookmarks_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What others gave this account is split by what it is: shares to read under
/// Shares › Received, requests to answer under Requests › To answer. Neither
/// tab shows the other's, and what someone handed over comes before what the
/// person saved.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    runInAction(() {
      Stores.bookmarks.bookmarks.addAll(const [
        Bookmark(id: 'b1', origin: '', slug: 'lease', label: 'Lease details'),
        Bookmark(
          id: 'b2',
          origin: '',
          slug: 'payslip',
          label: 'Pay slip',
          sender: 'u9',
        ),
        Bookmark(
          id: 'b3',
          origin: '',
          slug: 'club',
          label: 'Club membership',
          kind: BookmarkKind.request,
        ),
      ]);
    });
  });

  Future<void> show(WidgetTester tester, BookmarkKind kind) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BookmarksTab(kind: kind)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Received lists the shares, handed over first', (tester) async {
    await show(tester, BookmarkKind.share);
    expect(find.text('Lease details'), findsOneWidget);
    expect(find.text('Pay slip'), findsOneWidget);
    expect(find.text('Club membership'), findsNothing);
    final handed = tester.getTopLeft(find.text('Handed to you')).dy;
    final saved = tester.getTopLeft(find.text('Saved')).dy;
    expect(handed, lessThan(saved));
  });

  testWidgets('To answer lists only the requests', (tester) async {
    await show(tester, BookmarkKind.request);
    expect(find.text('Club membership'), findsOneWidget);
    expect(find.text('Lease details'), findsNothing);
    expect(find.text('Pay slip'), findsNothing);
  });

  testWidgets('with no requests, To answer says so', (tester) async {
    runInAction(
      () => Stores.bookmarks.bookmarks.removeWhere(
        (b) => b.kind == BookmarkKind.request,
      ),
    );
    await show(tester, BookmarkKind.request);
    expect(find.text('Nothing to answer'), findsOneWidget);
  });
}
