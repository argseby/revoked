import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/state/load_state.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_collection_header.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/features/attestations/view/attestations_section.dart';
import 'package:revoked_app/features/bookmarks/view/bookmarks_tab.dart';
import 'package:revoked_app/features/contacts/view/contacts_screen.dart';
import 'package:revoked_app/features/requests/view/inbox_screen.dart';
import 'package:revoked_app/features/shares/view/shares_screen.dart';
import 'package:revoked_app/features/vault/view/vault_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient((_) async => http.Response('{"items":[]}', 200)),
    );
    for (final state in [
      Stores.vault.loadState,
      Stores.shares.loadState,
      Stores.requests.loadState,
      Stores.contacts.loadState,
      Stores.credentials.loadState,
      Stores.attestations.loadState,
      Stores.attestationChecks.loadState,
      Stores.bookmarks.loadState,
    ]) {
      state.succeed(state.begin());
    }
  });

  final screens =
      <
        ({
          String name,
          Widget Function() page,
          String action,
          LoadState Function() state,
        })
      >[
        (
          name: 'vault',
          page: () => const VaultScreen(),
          action: 'Add item',
          state: () => Stores.vault.loadState,
        ),
        (
          name: 'shares',
          page: () => const SharesScreen(),
          action: 'Share items',
          state: () => Stores.shares.loadState,
        ),
        (
          name: 'requests',
          page: () => const InboxScreen(),
          action: 'New request',
          state: () => Stores.requests.loadState,
        ),
        (
          name: 'contacts',
          page: () => const ContactsScreen(),
          action: 'Add contact',
          state: () => Stores.contacts.loadState,
        ),
        (
          name: 'held attestations',
          page: () => const HeldAttestations(),
          action: 'Ask for attestation',
          state: () => Stores.credentials.loadState,
        ),
        (
          name: 'issued attestations',
          page: () => const IssuedAttestations(),
          action: 'Issue attestation',
          state: () => Stores.attestations.loadState,
        ),
        (
          name: 'attestation checks',
          page: () => const CheckedAttestations(),
          action: 'Check attestation',
          state: () => Stores.attestationChecks.loadState,
        ),
        (
          name: 'received shares',
          page: () => const BookmarksTab(kind: BookmarkKind.share),
          action: 'Open a link',
          state: () => Stores.bookmarks.loadState,
        ),
        (
          name: 'received requests',
          page: () => const BookmarksTab(kind: BookmarkKind.request),
          action: 'Open a link',
          state: () => Stores.bookmarks.loadState,
        ),
      ];

  for (final screen in screens) {
    for (final status in ['empty', 'loading', 'error']) {
      for (final small in [true, false]) {
        testWidgets(
          '${screen.name} keeps one header action when $status on ${small ? 'phone' : 'desktop'}',
          (tester) async {
            tester.view.physicalSize = small
                ? const Size(320, 800)
                : const Size(1200, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.build(
                  small ? Brightness.dark : Brightness.light,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(small ? 1.5 : 1)),
                  child: child!,
                ),
                home: Scaffold(body: screen.page()),
              ),
            );
            if (status == 'loading') {
              screen.state().reset();
              screen.state().begin();
            } else if (status == 'error') {
              final state = screen.state();
              state.reset();
              state.fail(state.begin(), 'Offline');
              if (screen.name.startsWith('received')) {
                Stores.bookmarks.error = AppErrorMessage.fromException(
                  StateError('Offline'),
                );
              }
            }
            await tester.pumpAndSettle();
            final action = find.text(screen.action);
            expect(action, findsOneWidget);
            expect(
              find.ancestor(
                of: action,
                matching: find.byType(AppCollectionHeader),
              ),
              findsOneWidget,
            );
            expect(
              tester.getRect(action).bottom,
              lessThan(tester.view.physicalSize.height),
            );
            for (final empty in tester.widgetList<AppEmptyState>(
              find.byType(AppEmptyState),
            )) {
              expect(empty.action, isNull);
              expect(empty.secondaryAction, isNull);
            }
            if (status == 'error') {
              expect(find.byType(AppLoadError), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
