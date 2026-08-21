import 'dart:typed_data';

import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/network/api_client.dart';

part 'vault_store.g.dart';

/// A MobX store backing the vault feature: holds the observable list of
/// vault [models.Record]s and [Section]s for the active workspace and
/// mediates all create/update/delete operations against the API.
///
/// Mutating actions catch errors into [errorMessage] and return `false`
/// rather than throwing, so callers can drive UI state off the boolean
/// result.
// ignore: library_private_types_in_public_api
class VaultStore extends _VaultStore with _$VaultStore {
  VaultStore(super.api);

  /// The exact API request [createRecord] issues — the single source of truth
  /// shared with the in-app API preview, so what the UI shows is what the app
  /// sends.
  static ApiRequestSpec createRecordSpec({
    required String key,
    required String value,
    required String label,
    required String type,
    required String format,
    required String user,
    required String workspace,
  }) {
    return ApiRequestSpec(
      method: 'POST',
      path: '/api/collections/${AppConfig.recordsCollection}/records',
      body: {
        'key': key,
        'value': value,
        'label': label,
        'type': type,
        'format': format,
        'user': user,
        'workspace': workspace,
      },
    );
  }

  /// The exact API request [updateRecord] issues — shared with the preview.
  static ApiRequestSpec updateRecordSpec(
    String id,
    Map<String, dynamic> updates,
  ) {
    return ApiRequestSpec(
      method: 'PATCH',
      path: '/api/collections/${AppConfig.recordsCollection}/records/$id',
      body: updates,
    );
  }

  /// The exact API request [deleteRecord] issues — shared with the preview.
  static ApiRequestSpec deleteRecordSpec(String id) {
    return ApiRequestSpec(
      method: 'DELETE',
      path: '/api/collections/${AppConfig.recordsCollection}/records/$id',
    );
  }

  /// The exact API request [createSection] issues — shared with the preview.
  static ApiRequestSpec createSectionSpec({
    required String key,
    required String name,
    required List<String> records,
    required String user,
    required String workspace,
  }) {
    return ApiRequestSpec(
      method: 'POST',
      path: '/api/collections/${AppConfig.sectionsCollection}/records',
      body: {
        'key': key,
        'name': name,
        'records': records,
        'user': user,
        'workspace': workspace,
      },
    );
  }

  /// The exact API request [updateSection] issues — shared with the preview.
  static ApiRequestSpec updateSectionSpec(
    String id,
    Map<String, dynamic> updates,
  ) {
    return ApiRequestSpec(
      method: 'PATCH',
      path: '/api/collections/${AppConfig.sectionsCollection}/records/$id',
      body: updates,
    );
  }

  /// The exact API request [deleteSection] issues — shared with the preview.
  static ApiRequestSpec deleteSectionSpec(String id) {
    return ApiRequestSpec(
      method: 'DELETE',
      path: '/api/collections/${AppConfig.sectionsCollection}/records/$id',
    );
  }
}

abstract class _VaultStore with Store {
  final ApiClient _api;

  _VaultStore(this._api);

  @observable
  ObservableList<models.Record> records = ObservableList<models.Record>();

  @observable
  ObservableList<Section> sections = ObservableList<Section>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  /// The section whose membership is being edited, if any. Drives the whole
  /// screen's mode, so it belongs with the data it filters.
  @observable
  String? editingSectionId;

  @action
  void editSection(String? id) => editingSectionId = id;

  final ObservableTextController recordKey = ObservableTextController();
  final ObservableTextController recordValue = ObservableTextController();
  final ObservableTextController editRecordFilename =
      ObservableTextController();
  final ObservableTextController recordLabel = ObservableTextController();

  @observable
  String recordType = 'text';

  @observable
  String recordFormat = 'default';

  @observable
  String? recordKeyWarning;

  @observable
  String? recordSuggestedKey;

  @observable
  String? recordTypeWarning;

  @observable
  String? recordDetectedType;

  /// The picked file for a file-type draft. Bytes live on the store like every
  /// other draft field, so the drawer survives rebuilds and reroutes.
  @observable
  String? pickedFileName;

  @observable
  Uint8List? pickedFileBytes;

  /// When duplicating a record that lives in a section, the new one joins it.
  @observable
  String? recordOriginSectionId;

  @observable
  bool isSubmittingRecord = false;

  @action
  void setRecordType(String value) => recordType = value;

  @action
  void setRecordFormat(String value) => recordFormat = value;

  @action
  void setRecordKeyCheck({String? warning, String? suggestion}) {
    recordKeyWarning = warning;
    recordSuggestedKey = suggestion;
  }

  @action
  void setRecordTypeCheck({String? warning, String? detected}) {
    recordTypeWarning = warning;
    recordDetectedType = detected;
  }

  @action
  void setSubmittingRecord(bool value) => isSubmittingRecord = value;

  @action
  void setPickedFile(String name, Uint8List bytes) {
    pickedFileName = name;
    pickedFileBytes = bytes;
  }

  @action
  void clearPickedFile() {
    pickedFileName = null;
    pickedFileBytes = null;
  }

  /// Prepares the drawer for a new record, or for duplicating [from].
  @action
  void startRecordDraft({models.Record? from, String? sectionId}) {
    recordKey.text = from != null ? '${from.key}_1' : '';
    recordValue.text = from?.value ?? '';
    recordLabel.text = from?.label ?? '';
    recordType = from?.type ?? 'text';
    recordFormat = from?.format ?? 'default';
    recordOriginSectionId = sectionId;
    recordKeyWarning = null;
    recordSuggestedKey = null;
    recordTypeWarning = null;
    recordDetectedType = null;
    pickedFileName = null;
    pickedFileBytes = null;
    isSubmittingRecord = false;
  }

  final ObservableTextController sectionKey = ObservableTextController();
  final ObservableTextController sectionName = ObservableTextController();

  @observable
  String? sectionKeyWarning;

  @observable
  String? sectionSuggestedKey;

  @observable
  String? sectionError;

  @observable
  bool isSubmittingSection = false;

  /// Prepares the drawer for a new section, or for duplicating [from].
  @action
  void startSectionDraft({Section? from}) {
    sectionKey.text = from != null ? '${from.key}_1' : '';
    sectionName.text = from?.name ?? '';
    sectionKeyWarning = null;
    sectionSuggestedKey = null;
    sectionError = null;
    isSubmittingSection = false;
  }

  @action
  void setSectionKeyCheck({String? warning, String? suggestion}) {
    sectionKeyWarning = warning;
    sectionSuggestedKey = suggestion;
  }

  @action
  void setSectionError(String? value) => sectionError = value;

  @action
  void setSubmittingSection(bool value) => isSubmittingSection = value;

  final ObservableTextController renameSectionName = ObservableTextController();

  @observable
  String? renameSectionError;

  @observable
  bool isRenamingSection = false;

  @action
  void startSectionRename(Section section) {
    renameSectionName.text = section.name;
    renameSectionError = null;
    isRenamingSection = false;
  }

  @action
  void setRenameSectionError(String? value) => renameSectionError = value;

  @action
  void setRenamingSection(bool value) => isRenamingSection = value;

  final ObservableTextController editRecordLabel = ObservableTextController();
  final ObservableTextController editRecordValue = ObservableTextController();

  @observable
  String editRecordType = 'text';

  @observable
  String editRecordFormat = 'default';

  @observable
  String? editRecordTypeWarning;

  @observable
  String? editRecordDetectedType;

  @observable
  bool isSubmittingEditRecord = false;

  @action
  void startRecordEdit(models.Record record) {
    editRecordLabel.text = record.label;
    editRecordValue.text = record.value;
    editRecordFilename.text = record.displayName;
    editRecordType = record.type;
    editRecordFormat = record.format;
    editRecordTypeWarning = null;
    editRecordDetectedType = null;
    editPickedFileName = null;
    editPickedFileBytes = null;
    isSubmittingEditRecord = false;
  }

  /// A file staged to replace the record's current one, held until save so a
  /// rename and a replacement land in a single write.
  @observable
  String? editPickedFileName;

  @observable
  Uint8List? editPickedFileBytes;

  @action
  void setEditPickedFile(String name, Uint8List bytes) {
    editPickedFileName = name;
    editPickedFileBytes = bytes;
  }

  @action
  void setEditRecordType(String value) => editRecordType = value;

  @action
  void setEditRecordFormat(String value) => editRecordFormat = value;

  @action
  void setEditRecordTypeCheck({String? warning, String? detected}) {
    editRecordTypeWarning = warning;
    editRecordDetectedType = detected;
  }

  @action
  void setSubmittingEditRecord(bool value) => isSubmittingEditRecord = value;

  /// Records whose hidden value the user has chosen to reveal, by id. Keyed
  /// rather than held per-card so no card carries state of its own.
  final ObservableSet<String> revealedRecords = ObservableSet<String>();

  bool isRevealed(String id) => revealedRecords.contains(id);

  @action
  void toggleRevealed(String id) {
    if (!revealedRecords.remove(id)) revealedRecords.add(id);
  }

  @computed
  int get recordCount => records.length;

  /// Loads all records and sections for the workspace into the store,
  /// replacing the current lists.
  @action
  Future<void> loadRecords() async {
    isLoading = true;
    errorMessage = null;
    try {
      final recordsData = await _api.get(
        '/api/collections/${AppConfig.recordsCollection}/records',
        queryParams: {'page': '1', 'perPage': '50', 'sort': '-created'},
      );
      final recordItems = (recordsData['items'] as List<dynamic>?) ?? [];
      records = ObservableList.of(
        recordItems.map(
          (e) => models.Record.fromJson(e as Map<String, dynamic>),
        ),
      );

      final sectionsData = await _api.get(
        '/api/collections/${AppConfig.sectionsCollection}/records',
        queryParams: {
          'page': '1',
          'perPage': '50',
          'sort': '-created',
          'expand': 'records',
        },
      );
      final sectionItems = (sectionsData['items'] as List<dynamic>?) ?? [];
      sections = ObservableList.of(
        sectionItems.map((e) => Section.fromJson(e as Map<String, dynamic>)),
      );
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> createRecord({
    required String key,
    required String value,
    required String label,
    required String type,
    required String format,
    required String user,
    required String workspace,
    String? fileName,
    Uint8List? fileBytes,
  }) async {
    isLoading = true;
    errorMessage = null;
    try {
      final record = await _create(
        key: key,
        value: value,
        label: label,
        type: type,
        format: format,
        user: user,
        workspace: workspace,
        fileName: fileName,
        fileBytes: fileBytes,
      );
      records.insert(0, record);
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> deleteRecord(String id) async {
    try {
      await _api.delete(VaultStore.deleteRecordSpec(id).path);
      records.removeWhere((r) => r.id == id);
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    }
  }

  /// Ids of records whose file is being fetched, so each row can show its own
  /// spinner.
  @observable
  ObservableSet<String> downloadingRecordIds = ObservableSet<String>();

  /// Replaces a file record's file — the rotation gesture: every active share
  /// serves the new bytes on its next resolve.
  @action
  Future<bool> updateRecordFile(
    String id,
    String uploadName,
    Uint8List bytes, {
    Map<String, String> fields = const {},
  }) async {
    isLoading = true;
    errorMessage = null;
    try {
      final spec = VaultStore.updateRecordSpec(id, const {});
      final data = await _api.patchMultipart(
        spec.path,
        fields: fields,
        fileField: 'file',
        filename: uploadName,
        bytes: bytes,
      );
      final updated = models.Record.fromJson(data as Map<String, dynamic>);
      final index = records.indexWhere((r) => r.id == id);
      if (index != -1) {
        records[index] = updated;
      }
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  /// Fetches the owner's own file through PocketBase's rule-checked file
  /// token — the field is protected, so a bare file URL serves nothing.
  @action
  Future<Uint8List?> fetchRecordFileBytes(models.Record record) async {
    final filename = record.file;
    if (filename == null || filename.isEmpty) return null;
    downloadingRecordIds.add(record.id);
    try {
      final tokenData = await _api.post('/api/files/token');
      final token = (tokenData as Map<String, dynamic>)['token'] as String;
      return await _api.getPublicBytes(
        null,
        '/api/files/${AppConfig.recordsCollection}/${record.id}/$filename',
        queryParams: {'token': token},
      );
    } catch (e) {
      errorMessage = e.toString();
      return null;
    } finally {
      downloadingRecordIds.remove(record.id);
    }
  }

  @action
  Future<bool> updateRecord(String id, Map<String, dynamic> updates) async {
    isLoading = true;
    errorMessage = null;
    try {
      final spec = VaultStore.updateRecordSpec(id, updates);
      final data = await _api.patch(spec.path, body: spec.body);
      final updated = models.Record.fromJson(data as Map<String, dynamic>);
      final index = records.indexWhere((r) => r.id == id);
      if (index != -1) {
        records[index] = updated;
      }
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> createSection({
    required String key,
    required String name,
    required List<String> recordIds,
    required String user,
    required String workspace,
  }) async {
    isLoading = true;
    errorMessage = null;
    try {
      final section = await _createSection(
        key: key,
        name: name,
        records: recordIds,
        user: user,
        workspace: workspace,
      );
      sections.insert(0, section);
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> updateSection(String id, Map<String, dynamic> updates) async {
    try {
      final spec = VaultStore.updateSectionSpec(id, updates);
      final data = await _api.patch(spec.path, body: spec.body);
      final section = Section.fromJson(data as Map<String, dynamic>);
      final index = sections.indexWhere((s) => s.id == id);
      if (index != -1) {
        sections[index] = section;
      }
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    }
  }

  @action
  Future<bool> deleteSection(String id) async {
    try {
      await _api.delete(VaultStore.deleteSectionSpec(id).path);
      sections.removeWhere((s) => s.id == id);
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    }
  }

  /// Materializes a [Template] into the vault: creates its root records,
  /// then each section with its child records. Record and section keys are
  /// sanitized and de-duplicated against existing store state (suffixing
  /// `_1`, `_2`, … on collision) so import never clashes with current keys.
  @action
  Future<bool> createFromTemplate({
    required Template template,
    required String user,
    required String workspace,
  }) async {
    isLoading = true;
    errorMessage = null;
    try {
      final sectionsList = template.schema['sections'] as List<dynamic>? ?? [];
      final rootRecords = template.schema['records'] as List<dynamic>? ?? [];

      String makeUniqueKey(String baseKey, bool isSection) {
        String key = baseKey.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9_-]'),
          '_',
        );
        if (key.isEmpty) {
          key = isSection ? 'section' : 'key';
        }

        final exists = isSection
            ? sections.any((s) => s.key == key)
            : records.any((r) => r.key == key);
        if (!exists) {
          return key;
        }

        int counter = 1;
        while (true) {
          final candidate = '${key}_$counter';
          final existsAlt = isSection
              ? sections.any((s) => s.key == candidate)
              : records.any((r) => r.key == candidate);
          if (!existsAlt) {
            return candidate;
          }
          counter++;
        }
      }

      for (final recMap in rootRecords) {
        if (recMap is! Map) continue;
        final baseKey = (recMap['key'] as String? ?? '').trim();
        final label = (recMap['label'] as String? ?? 'Record').trim();
        final value = (recMap['value'] as String? ?? '').trim();
        final type = (recMap['type'] as String? ?? 'text').trim();
        final format = (recMap['format'] as String? ?? 'default').trim();

        final uniqueKey = makeUniqueKey(baseKey, false);
        final createdRecord = await _create(
          key: uniqueKey,
          value: value,
          label: label,
          type: type,
          format: format,
          user: user,
          workspace: workspace,
        );
        records.insert(0, createdRecord);
      }

      for (final secMap in sectionsList) {
        if (secMap is! Map) continue;
        final baseSecKey = (secMap['key'] as String? ?? '').trim();
        final name = (secMap['name'] as String? ?? 'Section').trim();
        final childRecords = secMap['records'] as List<dynamic>? ?? [];

        final createdChildIds = <String>[];
        final uniqueSecKey = makeUniqueKey(baseSecKey, true);

        for (final recMap in childRecords) {
          if (recMap is! Map) continue;
          final baseKey = (recMap['key'] as String? ?? '').trim();
          final label = (recMap['label'] as String? ?? 'Record').trim();
          final value = (recMap['value'] as String? ?? '').trim();
          final type = (recMap['type'] as String? ?? 'text').trim();
          final format = (recMap['format'] as String? ?? 'default').trim();

          final uniqueKey = makeUniqueKey(baseKey, false);
          final createdRecord = await _create(
            key: uniqueKey,
            value: value,
            label: label,
            type: type,
            format: format,
            user: user,
            workspace: workspace,
          );
          records.insert(0, createdRecord);
          createdChildIds.add(createdRecord.id);
        }

        final createdSection = await _createSection(
          key: uniqueSecKey,
          name: name,
          records: createdChildIds,
          user: user,
          workspace: workspace,
        );
        sections.insert(0, createdSection);
      }

      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  void clearError() {
    errorMessage = null;
  }

  Future<models.Record> _create({
    required String key,
    required String value,
    required String label,
    required String type,
    required String format,
    required String user,
    required String workspace,
    String? fileName,
    Uint8List? fileBytes,
  }) async {
    final spec = VaultStore.createRecordSpec(
      key: key,
      value: value,
      label: label,
      type: type,
      format: format,
      user: user,
      workspace: workspace,
    );
    final dynamic data;
    if (fileBytes != null && fileName != null) {
      data = await _api.postMultipart(
        spec.path,
        fields: {
          'key': key,
          'label': label,
          'type': type,
          'format': format,
          'user': user,
          'workspace': workspace,
        },
        fileField: 'file',
        filename: fileName,
        bytes: fileBytes,
      );
    } else {
      data = await _api.post(spec.path, body: spec.body);
    }
    return models.Record.fromJson(data as Map<String, dynamic>);
  }

  Future<Section> _createSection({
    required String key,
    required String name,
    required List<String> records,
    required String user,
    required String workspace,
  }) async {
    final spec = VaultStore.createSectionSpec(
      key: key,
      name: name,
      records: records,
      user: user,
      workspace: workspace,
    );
    final data = await _api.post(spec.path, body: spec.body);
    return Section.fromJson(data as Map<String, dynamic>);
  }
}
