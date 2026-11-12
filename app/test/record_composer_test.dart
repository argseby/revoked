import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/files/pending_upload.dart';
import 'package:revoked_app/core/models/group.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/models/workspace_member.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final writes = <Map<String, dynamic>>[];

  setUp(() async {
    writes.clear();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient((request) async {
        Object response = {'items': []};
        if (request.method == 'POST' &&
            request.url.path == '/api/collections/records/records') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          writes.add(body);
          response = {'id': 'created-record', ...body};
        }
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1100, 1000),
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => openVaultCreateSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(TextEditingController controller) => find.byWidgetPredicate(
    (widget) => widget is AppTextField && widget.controller == controller,
  );

  Future<void> pick(WidgetTester tester, String label) async {
    if (find.text(label).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(label),
        150,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('record-composer-editor')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(find.text(label).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  AppButton saveButton(WidgetTester tester) =>
      tester.widget<AppButton>(find.widgetWithText(AppButton, 'Save record'));

  testWidgets('switching types retains separate drafts and file attachment', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(field(Stores.vault.recordLabel), 'Account');
    await tester.enterText(field(Stores.vault.recordValue), 'my original note');
    await pick(tester, 'Number');
    expect(Stores.vault.recordValue.text, isEmpty);
    expect(saveButton(tester).onTap, isNull);
    await tester.enterText(field(Stores.vault.recordValue), '42');
    await pick(tester, 'Yes or no');
    expect(Stores.vault.recordValue.text, 'false');
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    await pick(tester, 'File');
    expect(find.text('Files are private to your account.'), findsNothing);
    final upload = PendingUpload(
      name: 'document.txt',
      size: 4,
      open: () => Stream.value([116, 101, 115, 116]),
    );
    Stores.vault.setPickedFile(upload);
    await tester.pumpAndSettle();
    await pick(tester, 'Text');
    expect(Stores.vault.recordValue.text, 'my original note');
    await pick(tester, 'Number');
    expect(Stores.vault.recordValue.text, '42');
    await pick(tester, 'Yes or no');
    expect(Stores.vault.recordValue.text, 'true');
    await pick(tester, 'File');
    expect(Stores.vault.pickedFile, same(upload));
    expect(saveButton(tester).onTap, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'masking and the draft survive changing creation modes; save sends current type',
    (tester) async {
      await open(tester);
      await tester.enterText(field(Stores.vault.recordLabel), 'My note');
      await tester.enterText(field(Stores.vault.recordValue), 'hello');
      await tester.tap(find.text('Hide in vault'));
      await tester.pumpAndSettle();
      await pick(tester, 'Section');
      await pick(tester, 'Record');
      expect(Stores.vault.recordValue.text, 'hello');
      expect(Stores.vault.recordFormat, 'hidden');
      await tester.tap(find.text('Save record'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(writes.single, containsPair('key', 'my_note'));
      expect(writes.single, containsPair('value', 'hello'));
      expect(writes.single, containsPair('type', 'text'));
      expect(writes.single, containsPair('format', 'hidden'));
      expect(find.text('Add to vault'), findsNothing);
    },
  );

  testWidgets(
    'access is explicit and groups require a selection; file access stays private',
    (tester) async {
      runInAction(() {
        Stores.auth.currentUser = User(
          id: 'me',
          email: 'me@example.com',
          activeWorkspace: 'workspace',
        );
        Stores.settings.memberships.add(
          WorkspaceMember(
            id: 'member',
            user: 'me',
            workspace: 'workspace',
            role: 'admin',
          ),
        );
        Stores.settings.groups.add(
          const WorkspaceGroup(id: 'finance', key: 'finance', name: 'Finance'),
        );
      });
      await open(tester);
      await tester.enterText(field(Stores.vault.recordLabel), 'IBAN');
      await tester.enterText(field(Stores.vault.recordValue), 'DE89');
      await pick(tester, 'Access');
      await pick(tester, 'Specific groups');
      expect(saveButton(tester).onTap, isNull);
      await pick(tester, 'Finance');
      expect(saveButton(tester).onTap, isNotNull);
      await pick(tester, 'Access');
      await pick(tester, 'File');
      expect(find.text('Private · only you'), findsOneWidget);
      await pick(tester, 'Text');
      await pick(tester, 'Access');
      expect(find.text('Finance'), findsOneWidget);
      expect(saveButton(tester).onTap, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, scale, brightness) in [
    (const Size(320, 900), 1.0, Brightness.light),
    (const Size(1100, 1000), 1.0, Brightness.dark),
    (const Size(375, 1000), 1.8, Brightness.light),
  ]) {
    testWidgets('composer fits $size at text scale $scale in $brightness', (
      tester,
    ) async {
      await open(tester, size: size, textScale: scale, brightness: brightness);
      expect(
        find.byKey(const ValueKey('record-type-rail')),
        size.width > 600 && scale == 1 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await pick(tester, 'Date and time');
      expect(Stores.vault.recordType, 'datetime');
      await tester.scrollUntilVisible(
        find.text('Pick a date'),
        150,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('record-composer-editor')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Pick a date'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await pick(tester, 'Developer options');
      await tester.ensureVisible(find.text('Record key'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
