import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/models/contact.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/stores.dart';

enum ContactDeliveryStep { contacts, review, results }

class ContactDeliveryResult {
  final Contact contact;
  final ContactGrant? grant;
  final String? error;
  const ContactDeliveryResult(this.contact, {this.grant, this.error});
}

/// State belongs to this delivery, never to a later create or a contact's draft.
/// Only explicit Send/Retry actions make outbound calls.
class ContactDeliveryStore {
  final Link? share;
  final DataRequest? request;
  final String owner = Stores.auth.userId;
  final String serverBase = Stores.api.baseUrl;
  final query = ObservableTextController();
  final selected = ObservableMap<String, Contact>();
  final results = ObservableMap<String, ContactDeliveryResult>();
  final _step = Observable(ContactDeliveryStep.contacts);
  final _busy = Observable(false);
  final _loading = Observable(false);
  final _sendingId = Observable<String?>(null);

  ContactDeliveryStore({this.share, this.request})
    : assert((share == null) != (request == null));

  ContactDeliveryStep get step => _step.value;
  bool get busy => _busy.value;
  bool get loading => _loading.value;
  String? get sendingId => _sendingId.value;
  bool get isRequest => request != null;
  String get kind => isRequest ? 'request' : 'share';
  String get id => request?.id ?? share!.id;
  String get slug => request?.slug ?? share!.slug;
  String get title => request?.label ?? share!.label;
  String get workspace => request?.workspace ?? share!.workspace;
  bool get encrypted => share?.encrypted ?? false;
  bool get contextMatches =>
      Stores.auth.userId == owner &&
      Stores.auth.activeWorkspace == workspace &&
      Stores.api.baseUrl == serverBase;
  bool get hasFailures => results.values.any((r) => r.error != null);
  List<Contact> get recipients => selected.values.toList();
  List<Contact> get matchingContacts {
    final text = query.text.trim().toLowerCase();
    return Stores.contacts.contacts
        .where(
          (c) =>
              c.workspace == workspace &&
              (text.isEmpty ||
                  '${c.name} ${c.email} ${c.where}'.toLowerCase().contains(
                    text,
                  )),
        )
        .toList();
  }

  Future<void> load() async {
    runInAction(() => _loading.value = true);
    try {
      await Stores.contacts.loadIfDue();
    } finally {
      runInAction(() => _loading.value = false);
    }
  }

  void toggle(Contact contact) => runInAction(() {
    if (busy) return;
    if (selected.containsKey(contact.id)) {
      selected.remove(contact.id);
    } else {
      selected[contact.id] = contact;
    }
  });

  void review() => runInAction(() {
    if (!busy && selected.isNotEmpty) _step.value = ContactDeliveryStep.review;
  });

  void changeRecipients() => runInAction(() {
    if (!busy) _step.value = ContactDeliveryStep.contacts;
  });

  String routeFor(Contact contact) {
    if (encrypted) return 'Share the encrypted link manually';
    if (contact.isHere) return 'In Revoked';
    if (Stores.contacts.emailReason(contact, isAsk: isRequest) != null) {
      return 'Manual link available; in-app delivery if possible';
    }
    return 'In-app delivery or email invitation';
  }

  /// Retries only unsuccessful calls; acknowledged deliveries are retained.
  Future<void> send() async {
    if (busy || selected.isEmpty) return;
    final pending = recipients
        .where((c) => results[c.id]?.grant == null)
        .toList();
    runInAction(() {
      _busy.value = true;
      _step.value = ContactDeliveryStep.results;
    });
    try {
      for (final contact in pending) {
        runInAction(() => _sendingId.value = contact.id);
        if (!contextMatches) {
          runInAction(
            () => results[contact.id] = ContactDeliveryResult(
              contact,
              error: 'The account, server or workspace changed. Open the saved item to send it.',
            ),
          );
          continue;
        }
        try {
          // Never pass the fragment key to the server. Encrypted links need
          // the existing device-side share sheet until key delivery is supported.
          final grant = encrypted
              ? ContactGrant(
                  id: id,
                  slug: slug,
                  kind: kind,
                  delivered: false,
                  channel: ContactChannel.manual,
                )
              : await Stores.contacts.deliverExisting(
                  contact.id,
                  id: id,
                  kind: kind,
                );
          runInAction(
            () => results[contact.id] = ContactDeliveryResult(
              contact,
              grant: grant,
            ),
          );
        } catch (e) {
          runInAction(
            () => results[contact.id] = ContactDeliveryResult(
              contact,
              error: AppErrorMessage.fromException(e).description,
            ),
          );
        }
      }
    } finally {
      runInAction(() {
        _busy.value = false;
        _sendingId.value = null;
      });
    }
  }

  List<String> get contentNames {
    if (isRequest) {
      final template = Stores.templates.templates
          .where((t) => t.id == request!.templateId)
          .firstOrNull;
      if (template == null) {
        return [
          if (request!.templateId.isNotEmpty) 'Requested form',
          if (request!.allowExtraFields) 'Additional fields allowed',
        ];
      }
      final schema = template.schema;
      final fields = <String>[];
      void collect(dynamic entries) {
        if (entries is! List) return;
        for (final entry in entries.whereType<Map>()) {
          final label = entry['label'] ?? entry['key'];
          if (label is String && label.isNotEmpty) fields.add(label);
        }
      }

      collect(schema['records']);
      for (final section
          in (schema['sections'] as List? ?? const []).whereType<Map>()) {
        collect(section['records']);
      }
      return fields.isEmpty ? [template.name] : fields;
    }
    final records = {
      for (final r in [...Stores.vault.sharedRecords, ...Stores.vault.records])
        r.id: r,
    };
    final sections = {
      for (final s in [
        ...Stores.vault.sharedSections,
        ...Stores.vault.sections,
      ])
        s.id: s,
    };
    final ids = <String>{...share!.records};
    for (final section in share!.sections) {
      ids.addAll(sections[section]?.records ?? const []);
    }
    return [
      for (final id in ids)
        if (records[id] case final record?)
          record.label.isEmpty ? record.key : record.label,
    ];
  }

  void dispose() => query.dispose();
}
