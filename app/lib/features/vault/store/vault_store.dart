import 'dart:async';
import 'dart:typed_data';

import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/files/pending_upload.dart';
import 'package:revoked_app/core/state/load_state.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';

part 'vault_store.g.dart';

/// How encrypting an existing record went.
enum SealOutcome { sealed, linksAffected, failed }

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
  /// The id of the group holding entries other members published on their
  /// own, beside the sections they shared.
  static const sharedEntriesId = '__shared_entries__';

  static ApiRequestSpec createRecordSpec({
    required String key,
    required String value,
    required String label,
    required String type,
    required String format,
    required String user,
    required String workspace,
    String audienceKind = '',
    List<String> audienceGroups = const [],
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
        // Who sees it; empty leaves it to the workspace's default.
        if (audienceKind.isNotEmpty) 'audienceKind': audienceKind,
        if (audienceGroups.isNotEmpty) 'audienceGroups': audienceGroups,
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
    String audienceKind = '',
    List<String> audienceGroups = const [],
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
        // Who sees it; empty leaves it to the workspace's default.
        if (audienceKind.isNotEmpty) 'audienceKind': audienceKind,
        if (audienceGroups.isNotEmpty) 'audienceGroups': audienceGroups,
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

  /// Sections other members shared with this person, and the records in them.
  /// Read-only here; they stay their owners'.
  @observable
  ObservableList<Section> sharedSections = ObservableList<Section>();

  @observable
  ObservableList<models.Record> sharedRecords = ObservableList<models.Record>();

  /// Why the shared sections could not be loaded, apart from the vault's own.
  @observable
  String? sharedError;

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

  /// Whether the record being drafted is end-to-end encrypted.
  @observable
  bool recordSealed = false;

  @action
  void setRecordSealed(bool value) => recordSealed = value;

  @observable
  String? recordKeyWarning;

  @observable
  String? recordSuggestedKey;

  @observable
  String? recordTypeWarning;

  @observable
  String? recordDetectedType;

  /// The picked file for a file-type draft. A handle, not bytes: the draft
  /// outlives rebuilds and reroutes, and holding the content that long is what
  /// made a large file an out-of-memory kill.
  @observable
  PendingUpload? pickedFile;

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
  void setPickedFile(PendingUpload file) => pickedFile = file;

  @action
  void clearPickedFile() {
    pickedFile = null;
    pickedFilePreview = null;
    pickedFileError = null;
  }

  /// Prepares the drawer for a new record, or for duplicating [from].
  @action
  void startRecordDraft({models.Record? from, String? sectionId}) {
    recordKey.text = from != null ? '${from.key}_1' : '';
    recordValue.text = from?.value ?? '';
    recordLabel.text = from?.label ?? '';
    recordType = from?.type ?? 'text';
    recordFormat = from?.format ?? 'default';
    // A copy of something encrypted starts encrypted: the person would otherwise
    // write it out in plaintext just by duplicating it.
    recordSealed = from?.sealed ?? false;
    recordOriginSectionId = sectionId;
    recordKeyWarning = null;
    recordSuggestedKey = null;
    recordTypeWarning = null;
    recordDetectedType = null;
    pickedFile = null;
    pickedFilePreview = null;
    pickedFileError = null;
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
    editPickedFile = null;
    pickedFileError = null;
    isSubmittingEditRecord = false;
  }

  /// A file staged to replace the record's current one, held until save so a
  /// rename and a replacement land in a single write.
  @observable
  PendingUpload? editPickedFile;

  @action
  void setEditPickedFile(PendingUpload file) => editPickedFile = file;

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

  /// Template fill: the template whose fields are being answered in the
  /// vault's create drawer, and the value being typed into one of them.
  @observable
  String? fillTemplateId;

  @action
  void selectFillTemplate(String? id) => fillTemplateId = id;

  /// Keeps [record] known to the store, so answering its field edits it in
  /// place rather than writing a second record: the vault list is paged, and a
  /// record found by another query may not be on its first page.
  @action
  void rememberRecord(models.Record record) {
    final i = records.indexWhere((r) => r.id == record.id);
    if (i >= 0) {
      records[i] = record;
    } else {
      records.insert(0, record);
    }
  }

  final ObservableTextController fillValue = ObservableTextController();

  @observable
  bool isFillingField = false;

  @action
  void setFillingField(bool value) => isFillingField = value;

  /// A template field is answered when the vault already holds its key as
  /// the owner's own — that, not a saved template, is what "filled" means
  /// here. An answer someone sent to one of your requests is theirs.
  bool isKeyFilled(String key) =>
      records.any((r) => r.key == key && r.requestedBy == null);

  /// Answers one template field: creates the record it describes and files it
  /// in the section the caller names — created on the first answer, found by
  /// its key after that. Answering a
  /// field the vault already holds rewrites that record's value instead, which
  /// is what makes a filled row editable. Fields are answered one at a time on
  /// purpose: a template is a checklist, not an all-or-nothing import.
  @action
  Future<bool> fillTemplateField({
    required String key,
    required String label,
    required String value,
    required String type,
    required String format,
    String sectionKey = '',
    String sectionName = '',
    required String user,
    required String workspace,
    PendingUpload? file,
  }) async {
    errorMessage = null;

    // An answered field is edited in place. The section is left alone: the
    // record may have been in the vault before this template ever asked for
    // it, and answering again is no reason to move it.
    // Someone else's answer to one of your requests may share the key; it is
    // theirs, and answering a field never rewrites it.
    final existing = records
        .where((r) => r.key == key && r.requestedBy == null)
        .toList();
    if (existing.isNotEmpty) {
      final id = existing.first.id;
      if (file != null) {
        return updateRecordFile(
          id,
          file,
          fields: {'filename': file.name, 'label': label, 'format': format},
        );
      }
      return updateRecord(id, {
        'value': value,
        'label': label,
        'type': type,
        'format': format,
      });
    }

    try {
      final record = await _create(
        key: key,
        value: value,
        label: label,
        type: type,
        format: format,
        user: user,
        workspace: workspace,
        file: file,
      );
      records.insert(0, record);

      if (sectionKey.isNotEmpty) {
        final existing = sections.where((s) => s.key == sectionKey).toList();
        if (existing.isEmpty) {
          final section = await _createSection(
            key: sectionKey,
            name: sectionName.isEmpty ? sectionKey : sectionName,
            records: [record.id],
            user: user,
            workspace: workspace,
          );
          sections.insert(0, section);
        } else {
          // Appended on the server, not written back from the list held
          // here: one id in it that has since been deleted and the whole
          // update is refused, leaving the answer in no section at all.
          return await updateSection(existing.first.id, {
            'records+': [record.id],
          });
        }
      }
      return true;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    }
  }

  @computed
  int get recordCount => records.length;

  /// Loads all records and sections for the workspace into the store,
  /// replacing the current lists.
  /// Tracks this list for the cache and the first-load skeleton.
  final LoadState loadState = LoadState();

  /// [loadRecords], unless what's here is still fresh.
  Future<void> loadIfDue() async {
    if (loadState.isDue) await loadRecords();
  }

  @action
  Future<void> loadRecords() async {
    isLoading = true;
    errorMessage = null;
    final ticket = loadState.begin();
    // Started with the list, not after it: whether this device can read its
    // encrypted records is shown above the list, and must not wait for a
    // list that may fail.
    unawaited(Stores.keys.ensureLoaded());
    // Only this person's own: what other members share also passes the
    // server's rules now, and is listed apart through loadShared.
    final me = Stores.auth.userId;
    final ownOnly = me.isEmpty
        ? const <String, String>{}
        : {'filter': 'user = "$me"'};
    try {
      final recordsData = await _api.get(
        '/api/collections/${AppConfig.recordsCollection}/records',
        queryParams: {
          ...ownOnly,
          'page': '1',
          'perPage': '${AppConfig.listPageSize}',
          'sort': '-created',
        },
      );
      final recordItems = (recordsData['items'] as List<dynamic>?) ?? [];
      final opened = await _openAll(
        recordItems.map(
          (e) => models.Record.fromJson(e as Map<String, dynamic>),
        ),
      );
      if (!loadState.isCurrent(ticket)) return;
      records = ObservableList.of(opened);
      await _moveToCurrentKeys();

      final sectionsData = await _api.get(
        '/api/collections/${AppConfig.sectionsCollection}/records',
        queryParams: {
          ...ownOnly,
          'page': '1',
          'perPage': '${AppConfig.listPageSize}',
          'sort': '-created',
          'expand': 'records',
        },
      );
      final sectionItems = (sectionsData['items'] as List<dynamic>?) ?? [];
      if (!loadState.isCurrent(ticket)) return;
      sections = ObservableList.of(
        sectionItems.map((e) => Section.fromJson(e as Map<String, dynamic>)),
      );
      loadState.succeed(ticket);
      await loadShared();
    } catch (e) {
      if (!loadState.isCurrent(ticket)) return;
      errorMessage = describeError(e);
      loadState.fail(ticket, errorMessage!);
    } finally {
      isLoading = false;
    }
  }

  /// Who published each entry of [sharedEntriesId], by entry id.
  final ObservableMap<String, String> sharedEntryOwners =
      ObservableMap<String, String>();

  /// Entries of other members this person may change (VISIBILITY.md).
  final ObservableSet<String> sharedEditable = ObservableSet<String>();

  /// Whether this person may change a colleague's entry: through a section
  /// open to them for editing, or on its own.
  bool canEditShared(Section section, models.Record r) =>
      section.canEdit || sharedEditable.contains(r.id);

  /// What other members shared with this person. Its failure is its own: the
  /// vault still shows.
  @action
  Future<void> loadShared() async {
    sharedError = null;
    try {
      final data = await _api.get('/api/shared/vault') as Map<String, dynamic>;
      final opened = await _openAll(
        ((data['records'] as List<dynamic>?) ?? const []).map(
          (e) => models.Record.fromJson(e as Map<String, dynamic>),
        ),
      );
      sharedRecords = ObservableList.of(opened);
      // Entries other members published on their own (the company's root
      // vault): shown as one more shared group, after the sections.
      final entries = ((data['entries'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      sharedEntryOwners
        ..clear()
        ..addAll({
          for (final e in entries)
            e['id'] as String: e['ownerEmail'] as String? ?? '',
        });
      sharedEditable
        ..clear()
        ..addAll([
          for (final e in entries)
            if (e['canEdit'] == true) e['id'] as String,
        ]);
      sharedSections = ObservableList.of([
        ...((data['sections'] as List<dynamic>?) ?? const []).map(
          (e) => Section.fromJson(e as Map<String, dynamic>),
        ),
        if (entries.isNotEmpty)
          Section(
            id: VaultStore.sharedEntriesId,
            key: 'shared_entries',
            name: 'Shared entries',
            records: [for (final e in entries) e['id'] as String],
            user: '',
            workspace: Stores.auth.activeWorkspace ?? '',
            audienceKind: 'workspace',
          ),
      ]);
    } catch (e) {
      sharedError = describeError(e);
    }
  }

  /// Shares one of this person's sections with the workspace's members, or
  /// stops. Members who may read the vault then see its records.
  @action
  Future<bool> setSectionShared(String id, bool shared) =>
      updateSection(id, {'shared': shared});

  /// Sets who sees one of this person's sections beside them, and whether
  /// those members may change it (VISIBILITY.md). Only the owner can.
  Future<bool> setSectionAudience(
    String id, {
    required String kind,
    required String editing,
    List<String> groups = const [],
  }) => updateSection(id, {
    'audienceKind': kind,
    'editing': editing,
    'audienceGroups': groups,
  });

  /// Who sees and who edits a section or record, as the server computes it:
  /// `owner`, `readers` and `editors` (each a `count`, with `members` when
  /// this person may see them), `canEdit`, `canChangeAudience`, `audience`.
  Future<Map<String, dynamic>> loadAccess(String collection, String id) async =>
      await _api.get('/api/access/$collection/$id') as Map<String, dynamic>;

  /// The operator's per-file cap from GET /api/server, cached for the session.
  /// Negative means the operator set none.
  int? _maxFileSize;

  /// Why the last pick was refused, shown beside the file row. Cleared by the
  /// next accepted pick.
  @observable
  String? pickedFileError;

  /// Thumbnail bytes for a staged image, and the size above which there is no
  /// thumbnail: streaming the upload exists so the file is never resident, and
  /// a preview is not worth giving that up for a large one.
  @observable
  Uint8List? pickedFilePreview;

  static const int previewSizeLimit = 8 << 20;

  /// Stages a picked file after checking it against the server's cap, so an
  /// oversized file is refused before the upload is spent rather than after.
  @action
  Future<void> stageFile(PendingUpload file, {bool forEdit = false}) async {
    final refusal = await _refuseOversized(file);
    if (refusal != null) {
      pickedFileError = refusal;
      return;
    }
    pickedFileError = null;
    if (forEdit) {
      editPickedFile = file;
      return;
    }
    pickedFile = file;
    pickedFilePreview = file.isImage && file.size <= previewSizeLimit
        ? await file.readAll()
        : null;
  }

  Future<String?> _refuseOversized(PendingUpload file) async {
    if (_maxFileSize == null) {
      try {
        final info = await _api.get('/api/server');
        final limits = info is Map ? info['limits'] : null;
        final max = limits is Map ? limits['maxFileSize'] : null;
        _maxFileSize = max is int ? max : -1;
      } catch (_) {
        // A limit we could not read is not a reason to block the pick; the
        // server still refuses the write.
        _maxFileSize = -1;
      }
    }
    final max = _maxFileSize!;
    if (max < 0 || file.size <= max) return null;
    return '${file.name} is ${formatBytes(file.size)}. This server accepts '
        'files up to ${formatBytes(max)}.';
  }

  /// Bytes accepted so far for the upload in flight and the total it is working
  /// towards. A zero total means nothing is uploading.
  @observable
  int uploadSent = 0;

  @observable
  int uploadTotal = 0;

  @computed
  bool get isUploading => uploadTotal > 0;

  @computed
  double get uploadProgress =>
      uploadTotal <= 0 ? 0 : (uploadSent / uploadTotal).clamp(0.0, 1.0);

  UploadCancelToken? _uploadCancel;

  /// Abandons the upload in flight. The request then fails like any other, so
  /// the calling screen's error path already covers it.
  @action
  void cancelUpload() => _uploadCancel?.cancel();

  @action
  void _beginUpload(UploadCancelToken token, int total) {
    _uploadCancel = token;
    uploadSent = 0;
    uploadTotal = total;
  }

  @action
  void _endUpload() {
    _uploadCancel = null;
    uploadSent = 0;
    uploadTotal = 0;
  }

  /// Throttled to whole percent: the socket hands over a chunk every few tens
  /// of kilobytes, and rebuilding the drawer thousands of times to move a
  /// progress bar by a subpixel costs more than the upload does.
  @action
  void _reportUploadProgress(int sent, int total) {
    if (total <= 0) return;
    final step = total ~/ 100;
    if (sent < total && step > 0 && sent - uploadSent < step) return;
    uploadSent = sent;
    uploadTotal = total;
  }

  /// Decrypts what this device can. Anything it can't stays locked, with an
  /// empty value, so nothing downstream can mistake it for the real one.
  Future<List<models.Record>> _openAll(Iterable<models.Record> fetched) async {
    final keys = Stores.keys;
    await keys.ensureLoaded();
    return [for (final r in fetched) _open(r)];
  }

  models.Record _open(models.Record record) {
    final keys = Stores.keys;
    if (!record.sealed) {
      return keys.knewAsSealed(record.id)
          ? record.markedUnsealedElsewhere(true)
          : record;
    }
    final content = keys.openContent(record);
    return content == null
        ? record
        : record.withOpened(
            value: content.value,
            label: content.label,
            type: content.type,
            format: content.format,
          );
  }

  /// Re-encrypts readable records still under a replaced key. A removed device
  /// kept that key, and could otherwise forge a new version of any record nobody
  /// has edited since. Once a device has seen a record under the new key, it
  /// refuses anything under the old one. A failure here is retried on next load.
  Future<void> _moveToCurrentKeys() async {
    final keys = Stores.keys;
    for (final record in records.toList()) {
      if (!record.sealed || record.isLocked) continue;
      final epoch = keys.writableEpoch(record.workspace);
      if (epoch == null || record.keyEpoch >= epoch) continue;
      try {
        _replaceInList(await _writeSealed(record, record.value));
      } on ApiException {
        continue;
      } on SealingException {
        continue;
      }
    }
  }

  models.Record? _byId(String id) {
    for (final r in records) {
      if (r.id == id) return r;
    }
    return null;
  }

  void _replaceInList(models.Record record) {
    final index = records.indexWhere((r) => r.id == record.id);
    if (index != -1) records[index] = record;
    // A colleague's record, changed by someone they opened editing to.
    final shared = sharedRecords.indexWhere((r) => r.id == record.id);
    if (shared != -1) sharedRecords[shared] = record;
  }

  /// The value being typed for a colleague's record, when its section is
  /// open for this person to edit (VISIBILITY.md).
  final ObservableTextController sharedEditValue = ObservableTextController();

  static String _friendlyError(Object e) => describeError(e);

  static String _newRecordId() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return Sealing.randomBytes(
      15,
    ).map((b) => alphabet[b % alphabet.length]).join();
  }

  /// Runs a sealed write, reloading the keys once if another device replaced
  /// the workspace's key since this one last looked.
  Future<dynamic> _withFreshKeys(Future<dynamic> Function() write) async {
    try {
      return await write();
    } on ApiException catch (e) {
      if (e.code != AppErrorCode.sealedEpochStale) rethrow;
      await Stores.keys.load();
      return write();
    }
  }

  Future<models.Record> _createSealed({
    required String key,
    required String value,
    required String label,
    required String type,
    required String format,
    required String workspace,
  }) async {
    final id = _newRecordId();
    late SealedPayload payload;
    final data = await _withFreshKeys(() {
      payload = Stores.keys.sealValue(
        workspace: workspace,
        record: id,
        recordKey: key,
        version: 1,
        value: value,
        label: label,
        type: type,
        format: format,
      );
      return _api.post(
        '/api/sealed/records',
        body: {
          ...payload.toJson(),
          'id': id,
          'key': key,
          'label': label,
          'type': type,
          'format': format,
          'workspace': workspace,
        },
      );
    });
    Stores.keys.noteWritten(id, version: 1, epoch: payload.keyEpoch);
    return models.Record.fromJson(
      data as Map<String, dynamic>,
    ).withOpened(value: value, label: label, type: type, format: format);
  }

  /// Writes [value] encrypted, as this record's next version. The server sees
  /// only ciphertext, and clears any plain value the record held. What gets
  /// remembered is what this device sent, not what the server answered: a reply
  /// claiming a huge version would otherwise lock this record out for good.
  Future<models.Record> _writeSealed(
    models.Record record,
    String value, {
    String? label,
    String? type,
    String? format,
    bool dropLinks = false,
  }) async {
    final newLabel = label ?? record.label;
    final newType = type ?? record.type;
    final newFormat = format ?? record.format;
    final version = record.sealedVersion + 1;
    late SealedPayload payload;
    final data = await _withFreshKeys(() {
      payload = Stores.keys.sealValue(
        workspace: record.workspace,
        record: record.id,
        recordKey: record.key,
        version: version,
        value: value,
        label: newLabel,
        type: newType,
        format: newFormat,
      );
      return _api.put(
        '/api/sealed/records/${record.id}',
        body: {
          ...payload.toJson(),
          'expectedVersion': record.sealedVersion,
          'dropLinks': dropLinks,
          'key': record.key,
          'label': newLabel,
          'type': newType,
          'format': newFormat,
        },
      );
    });
    Stores.keys.noteWritten(
      record.id,
      version: version,
      epoch: payload.keyEpoch,
    );
    return models.Record.fromJson(data as Map<String, dynamic>).withOpened(
      value: value,
      label: newLabel,
      type: newType,
      format: newFormat,
    );
  }

  /// Encrypts an existing plain record. Live links would stop showing it, so
  /// the first attempt reports that rather than doing it.
  @action
  Future<SealOutcome> sealRecord(String id, {bool dropLinks = false}) async {
    errorMessage = null;
    final record = _byId(id);
    if (record == null || record.isLocked) return SealOutcome.failed;
    try {
      _replaceInList(
        await _writeSealed(record, record.value, dropLinks: dropLinks),
      );
      return SealOutcome.sealed;
    } on ApiException catch (e) {
      if (e.code == AppErrorCode.sealedLinksAffected) {
        return SealOutcome.linksAffected;
      }
      errorMessage = _friendlyError(e);
      return SealOutcome.failed;
    } catch (e) {
      errorMessage = describeError(e);
      return SealOutcome.failed;
    }
  }

  /// Stores an encrypted record in plain text again, at its owner's request.
  @action
  Future<bool> unsealRecord(String id) async {
    errorMessage = null;
    final record = _byId(id);
    if (record == null || record.isLocked) return false;
    try {
      final data = await _api.post(
        '/api/sealed/records/$id/unseal',
        body: {
          'expectedVersion': record.sealedVersion,
          'value': record.value,
          ...Stores.keys.signUnseal(
            record: id,
            expectedVersion: record.sealedVersion,
            value: record.value,
          ),
        },
      );
      await Stores.keys.acceptUnsealed(id);
      _replaceInList(models.Record.fromJson(data as Map<String, dynamic>));
      return true;
    } catch (e) {
      errorMessage = _friendlyError(e);
      return false;
    }
  }

  /// The person confirmed it was them who stopped encrypting this record.
  @action
  Future<void> acceptUnsealedRecord(String id) async {
    await Stores.keys.acceptUnsealed(id);
    final record = _byId(id);
    if (record != null) _replaceInList(record.markedUnsealedElsewhere(false));
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
    PendingUpload? file,
    bool sealed = false,
    String audienceKind = '',
    List<String> audienceGroups = const [],
  }) async {
    isLoading = true;
    errorMessage = null;

    if (sealed) {
      try {
        final existing = records
            .where((r) => r.key == key && r.requestedBy == null)
            .toList();
        if (existing.isEmpty) {
          var created = await _createSealed(
            key: key,
            value: value,
            label: label,
            type: type,
            format: format,
            workspace: workspace,
          );
          // An encrypted entry is made private through its own route, and
          // widened right after; never the other way round.
          if (audienceKind.isNotEmpty && audienceKind != 'private') {
            final spec = VaultStore.updateRecordSpec(created.id, {
              'audienceKind': audienceKind,
              'audienceGroups': audienceGroups,
            });
            created = _open(
              models.Record.fromJson(
                await _api.patch(spec.path, body: spec.body)
                    as Map<String, dynamic>,
              ),
            );
          }
          records.insert(0, created);
          return true;
        }
        final current = existing.first;
        if (current.isLocked) {
          errorMessage =
              'An encrypted record named $key already exists and is not '
              'readable on this device.';
          return false;
        }
        // Encrypted first and metadata after: the other order would write the
        // new value out in plaintext on the way. Links aren't dropped here. That
        // decision needs the warning on the record's own page.
        _replaceInList(
          await _writeSealed(
            current,
            value,
            label: label,
            type: type,
            format: format,
          ),
        );
        return true;
      } catch (e) {
        errorMessage = _friendlyError(e);
        return false;
      } finally {
        isLoading = false;
      }
    }

    // An answered field is edited in place. The section is left alone: the
    // record may have been in the vault before this template ever asked for
    // it, and answering again is no reason to move it.
    // Someone else's answer to one of your requests may share the key; it is
    // theirs, and answering a field never rewrites it.
    final existing = records
        .where((r) => r.key == key && r.requestedBy == null)
        .toList();
    if (existing.isNotEmpty) {
      final id = existing.first.id;
      if (file != null) {
        return updateRecordFile(
          id,
          file,
          fields: {'filename': file.name, 'label': label, 'format': format},
        );
      }
      return updateRecord(id, {
        'value': value,
        'label': label,
        'type': type,
        'format': format,
      });
    }

    try {
      final record = await _create(
        key: key,
        value: value,
        label: label,
        type: type,
        format: format,
        user: user,
        workspace: workspace,
        file: file,
        // A file stays with its owner: it has no member download path yet.
        audienceKind: file == null ? audienceKind : '',
        audienceGroups: file == null ? audienceGroups : const [],
      );
      records.insert(0, record);
      return true;
    } catch (e) {
      errorMessage = describeError(e);
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
      // The server drops the record from its sections; so does the store.
      for (var i = 0; i < sections.length; i++) {
        final s = sections[i];
        if (!s.records.contains(id)) continue;
        sections[i] = s.withRecords(s.records.where((r) => r != id).toList());
      }
      return true;
    } catch (e) {
      errorMessage = describeError(e);
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
    PendingUpload file, {
    Map<String, String> fields = const {},
  }) async {
    isLoading = true;
    errorMessage = null;
    final token = UploadCancelToken();
    _beginUpload(token, file.size);
    try {
      final spec = VaultStore.updateRecordSpec(id, const {});
      final data = await _api.patchMultipart(
        spec.path,
        fields: fields,
        fileField: 'file',
        filename: file.name,
        openFile: file.open,
        length: file.size,
        onProgress: _reportUploadProgress,
        cancelToken: token,
      );
      final updated = models.Record.fromJson(data as Map<String, dynamic>);
      _replaceInList(updated);
      return true;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    } finally {
      _endUpload();
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
      errorMessage = describeError(e);
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
      // A sealed value never goes through the collection API: the server refuses
      // it there, because that is how plaintext would get back in. The record
      // may also be past the first page, so it's looked up, not assumed plain.
      var current = _byId(id);
      if (current == null && updates.containsKey('value')) {
        current = _open(
          models.Record.fromJson(
            await _api.get(
                  '/api/collections/${AppConfig.recordsCollection}/records/$id',
                )
                as Map<String, dynamic>,
          ),
        );
      }
      var remaining = updates;
      if (current != null && current.sealed) {
        const inCiphertext = {'value', 'label', 'type', 'format'};
        if (current.isLocked) {
          if (updates.keys.any(inCiphertext.contains)) {
            errorMessage = 'This record cannot be changed on this device.';
            return false;
          }
        } else {
          final value = updates['value'] as String? ?? current.value;
          final label = updates['label'] as String? ?? current.label;
          final type = updates['type'] as String? ?? current.type;
          final format = updates['format'] as String? ?? current.format;
          if (value != current.value ||
              label != current.label ||
              type != current.type ||
              format != current.format) {
            _replaceInList(
              await _writeSealed(
                current,
                value,
                label: label,
                type: type,
                format: format,
              ),
            );
          }
        }
        remaining = {...updates}
          ..removeWhere((key, _) => inCiphertext.contains(key));
        if (remaining.isEmpty) return true;
      } else if (updates.containsKey('value') && Stores.keys.knewAsSealed(id)) {
        // The server says this is plain, and this device knows it was encrypted.
        // Believing it would send the new value out in plaintext.
        errorMessage =
            'This record is no longer encrypted. The change must be confirmed '
            'on the record before it can be edited.';
        return false;
      }
      final spec = VaultStore.updateRecordSpec(id, remaining);
      final data = await _api.patch(spec.path, body: spec.body);
      final updated = _open(
        models.Record.fromJson(data as Map<String, dynamic>),
      );
      final index = records.indexWhere((r) => r.id == id);
      if (index != -1) {
        records[index] = updated;
      }
      return true;
    } catch (e) {
      errorMessage = describeError(e);
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
    String audienceKind = '',
    List<String> audienceGroups = const [],
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
        audienceKind: audienceKind,
        audienceGroups: audienceGroups,
      );
      sections.insert(0, section);
      return true;
    } catch (e) {
      errorMessage = describeError(e);
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
      errorMessage = describeError(e);
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
      errorMessage = describeError(e);
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
      errorMessage = describeError(e);
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
    PendingUpload? file,
    String audienceKind = '',
    List<String> audienceGroups = const [],
  }) async {
    final spec = VaultStore.createRecordSpec(
      key: key,
      value: value,
      label: label,
      type: type,
      format: format,
      user: user,
      workspace: workspace,
      audienceKind: audienceKind,
      audienceGroups: audienceGroups,
    );
    final dynamic data;
    if (file != null) {
      final token = UploadCancelToken();
      _beginUpload(token, file.size);
      try {
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
          filename: file.name,
          openFile: file.open,
          length: file.size,
          onProgress: _reportUploadProgress,
          cancelToken: token,
        );
      } finally {
        _endUpload();
      }
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
    String audienceKind = '',
    List<String> audienceGroups = const [],
  }) async {
    final spec = VaultStore.createSectionSpec(
      key: key,
      name: name,
      records: records,
      user: user,
      workspace: workspace,
      audienceKind: audienceKind,
      audienceGroups: audienceGroups,
    );
    final data = await _api.post(spec.path, body: spec.body);
    return Section.fromJson(data as Map<String, dynamic>);
  }
}
