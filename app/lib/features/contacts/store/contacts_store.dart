import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/contact.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/state/load_state.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';

part 'contacts_store.g.dart';

// ignore: library_private_types_in_public_api
class ContactsStore = _ContactsStore with _$ContactsStore;

/// The people this workspace sends to and asks from.
///
/// Workspace data, like shares: a contact follows the workspace rather than
/// whoever typed it in. Whether one is proven is the server's to say, so
/// nothing here writes trustState.
abstract class _ContactsStore with Store {
  final ApiClient _api;

  _ContactsStore(this._api);

  String get _basePath =>
      '/api/collections/${AppConfig.contactsCollection}/records';

  final ObservableTextController name = ObservableTextController();
  final ObservableTextController email = ObservableTextController();
  final ObservableTextController peerDomain = ObservableTextController();

  /// The rename sheet's field, so the sheet itself holds nothing.
  final ObservableTextController renameName = ObservableTextController();

  /// What a send or an ask is called, which is what the other person sees.
  final ObservableTextController grantLabel = ObservableTextController();

  /// Which contact the open send or ask sheet is for.
  @observable
  String? grantContactId;

  /// What a send gives out. Sections go as units, so entries added to one
  /// later are shared too.
  final ObservableSet<String> draftRecords = ObservableSet<String>();
  final ObservableSet<String> draftSections = ObservableSet<String>();

  /// The identity an ask is signed with, and the form it asks for.
  @observable
  String? askIdentityId;

  @observable
  String? askTemplateId;

  @observable
  ObservableList<Contact> contacts = ObservableList<Contact>();

  @observable
  bool isLoading = false;

  @observable
  bool isSaving = false;

  @observable
  bool isHandingOver = false;

  /// What came back from the last send or ask, so the view can show the link
  /// and say whether it arrived.
  @observable
  ContactGrant? lastGrant;

  @observable
  AppErrorMessage? error;

  /// How far this server will mail a grant, from `GET /api/server`. Null until
  /// asked — and a server too old to report it is treated as off, because a
  /// server that cannot say it will not mail.
  @observable
  String? mailRecipients;

  /// A contact needs a name and a way to reach someone; the server refuses
  /// one that reaches nobody, and the form should not offer to try.
  @computed
  bool get canSave =>
      name.text.trim().isNotEmpty &&
      (email.text.trim().isNotEmpty || peerDomain.text.trim().isNotEmpty);

  /// The contacts whose address has already been resolved to an account here.
  /// Every contact with an address may be sent to; this is only the ones
  /// already known to receive it in the app.
  @computed
  List<Contact> get knownHere =>
      contacts.where((c) => c.isHere).toList(growable: false);

  /// A send needs something to give and a name for it.
  @computed
  bool get canSend =>
      grantLabel.text.trim().isNotEmpty &&
      (draftRecords.isNotEmpty || draftSections.isNotEmpty);

  /// An ask needs a name and the identity it is signed with — that is what
  /// the other person is being asked to trust.
  @computed
  bool get canAsk =>
      grantLabel.text.trim().isNotEmpty && (askIdentityId ?? '').isNotEmpty;

  Contact? byId(String id) {
    for (final c in contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Reads the operator's mail policy. Failing silently like the attestation
  /// one: not knowing it only costs a sentence in the sheet.
  @action
  Future<void> loadPolicy() async {
    try {
      final data = await _api.get('/api/server');
      final info = data as Map<String, dynamic>;
      final mail = info['mail'];
      if (mail is Map<String, dynamic>) {
        mailRecipients = mail['recipients'] as String?;
      }
      serverDomain = info['domain'] as String? ?? '';
      final signups = info['signups'];
      if (signups is Map<String, dynamic>) {
        signupsOpen = signups['open'] as bool? ?? false;
      }
    } catch (_) {
      // Leave it null; emailReason then reads as off.
    }
  }

  /// Why an email will not reach [c], or null when one will.
  ///
  /// This never gates the Send button — the grant is minted either way and
  /// the slug comes back — it just sets the expectation before the tap.
  String? emailReason(Contact c, {required bool isAsk}) {
    if (c.isHere) return null;
    final address = c.email.trim();
    if (address.isEmpty) return 'no email address';
    if (isAsk && !signupsOpen) return 'answering needs an account here';
    switch (mailRecipients) {
      case 'all':
        return null;
      case 'trusted':
        return null;
      case 'same-domain':
        return _sameDomain(address) ? null : 'outside this server\'s domain';
      default:
        return 'this server does not send email';
    }
  }

  /// Whether anyone may make an account here, which is what an emailed ask
  /// needs. Read from the same `/api/server` call.
  @observable
  bool signupsOpen = false;

  /// This server's own domain, for the same-domain policy.
  @observable
  String serverDomain = '';

  bool _sameDomain(String address) {
    final at = address.lastIndexOf('@');
    final domain = at < 0 ? '' : address.substring(at + 1).toLowerCase();
    return domain.isNotEmpty && domain == serverDomain.toLowerCase();
  }

  /// Tracks this list for the cache and the first-load skeleton.
  final LoadState loadState = LoadState();

  /// [load], unless what's here is still fresh.
  Future<void> loadIfDue() async {
    if (loadState.isDue) await load();
  }

  @action
  Future<void> load() async {
    isLoading = true;
    error = null;
    final ticket = loadState.begin();
    try {
      final data = await _api.get(
        _basePath,
        queryParams: {'perPage': '200', 'sort': 'name'},
      );
      final items = (data['items'] as List<dynamic>?) ?? const [];
      if (!loadState.isCurrent(ticket)) return;
      contacts = ObservableList.of(
        items.map((e) => Contact.fromJson(e as Map<String, dynamic>)),
      );
      await loadPolicy();
      loadState.succeed(ticket);
    } catch (e) {
      if (!loadState.isCurrent(ticket)) return;
      error = AppErrorMessage.fromException(e);
      loadState.fail(ticket, error!.description);
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> create({required String workspace}) async {
    if (!canSave) return false;
    isSaving = true;
    error = null;
    try {
      final body = <String, dynamic>{
        'workspace': workspace,
        'name': name.text.trim(),
      };
      final address = email.text.trim();
      final domain = peerDomain.text.trim();
      if (address.isNotEmpty) body['email'] = address;
      if (domain.isNotEmpty) body['peerDomain'] = domain;

      final data = await _api.post(_basePath, body: body);
      contacts.add(Contact.fromJson(data as Map<String, dynamic>));
      clearForm();
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  /// Starts a send or an ask to [contactId] on an empty form. An ask opens
  /// on the workspace's primary identity, which is the one to sign with
  /// unless there is a reason to pick another.
  @action
  void startGrant(String contactId, {String? identityId}) {
    grantContactId = contactId;
    grantLabel.clear();
    draftRecords.clear();
    draftSections.clear();
    askIdentityId = identityId;
    askTemplateId = null;
    lastGrant = null;
    error = null;
  }

  @action
  void toggleDraftRecord(String id) => draftRecords.contains(id)
      ? draftRecords.remove(id)
      : draftRecords.add(id);

  @action
  void toggleDraftSection(String id) => draftSections.contains(id)
      ? draftSections.remove(id)
      : draftSections.add(id);

  @action
  void setAskIdentity(String? id) => askIdentityId = id;

  @action
  void setAskTemplate(String? id) => askTemplateId = id;

  /// Shares the drafted entries with the contact the form is for.
  ///
  /// The share is minted in this workspace, so it stays pausable and
  /// revocable here. Whether it reached the other person in the app is the
  /// server's answer, not a guess from [Contact.isHere]: it resolves the
  /// address at send time.
  @action
  Future<ContactGrant?> submitSend() async {
    final contactId = grantContactId;
    if (contactId == null || !canSend) return null;
    return _handOver(contactId, 'send', {
      'records': draftRecords.toList(),
      'sections': draftSections.toList(),
      'label': grantLabel.text.trim(),
    });
  }

  /// Asks the contact the form is for to send something back.
  @action
  Future<ContactGrant?> submitAsk() async {
    final contactId = grantContactId;
    if (contactId == null || !canAsk) return null;
    final template = askTemplateId ?? '';
    return _handOver(contactId, 'ask', {
      'label': grantLabel.text.trim(),
      'identity': askIdentityId,
      if (template.isNotEmpty) 'template': template,
    });
  }

  /// Starts the rename sheet on the contact's current name.
  @action
  void startRename(String id) => renameName.text = byId(id)?.name ?? '';

  @action
  Future<bool> rename(String id) =>
      _patch(id, {'name': renameName.text.trim()});

  @action
  Future<bool> remove(String id) async {
    error = null;
    try {
      await _api.delete('$_basePath/$id');
      contacts.removeWhere((c) => c.id == id);
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    }
  }

  @action
  void clearForm() {
    name.clear();
    email.clear();
    peerDomain.clear();
  }

  @action
  Future<ContactGrant?> _handOver(
    String contactId,
    String action,
    Map<String, dynamic> body,
  ) async {
    isHandingOver = true;
    error = null;
    lastGrant = null;
    try {
      final data = await _api.post(
        '/api/contacts/$contactId/$action',
        body: body,
      );
      final grant = ContactGrant.fromJson(data as Map<String, dynamic>);
      lastGrant = grant;
      // The server stamped when it was used and which account it resolved to.
      await _reload(contactId);
      return grant;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return null;
    } finally {
      isHandingOver = false;
    }
  }

  @action
  Future<void> _reload(String id) async {
    try {
      final data = await _api.get('$_basePath/$id');
      final updated = Contact.fromJson(data as Map<String, dynamic>);
      final idx = contacts.indexWhere((c) => c.id == id);
      if (idx != -1) contacts[idx] = updated;
    } catch (_) {
      // The grant went out; a stale row in the list is not worth a failure.
    }
  }

  @action
  Future<bool> _patch(String id, Map<String, dynamic> body) async {
    isSaving = true;
    error = null;
    try {
      final data = await _api.patch('$_basePath/$id', body: body);
      final updated = Contact.fromJson(data as Map<String, dynamic>);
      final idx = contacts.indexWhere((c) => c.id == id);
      if (idx != -1) contacts[idx] = updated;
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    } finally {
      isSaving = false;
    }
  }
}
