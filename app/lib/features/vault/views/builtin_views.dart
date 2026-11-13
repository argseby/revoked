import 'dart:convert';

import 'package:revoked_app/features/vault/views/view_spec.dart';

/// The views that ship with the app, written in the same format a template
/// will carry for its own. Ordered from the most specific match to the
/// least, as the first that matches a section is the one it shows.
///
/// From easy to hard:
///  1. Wi-Fi: a header, a secret, a join code that waits for the secret.
///  2. Emergency card: conditional badges, a grid of facts and call
///     buttons, drawn from the three sections the template fills.
///  3. Vehicle: a countdown that warns before the inspection is due.
///  4. Medication plan: a record group laid out as a daily schedule, with
///     the next dose and the day the stock runs out worked out for it.
final List<ViewSpec> builtinViews = [
  for (final json in builtinViewJson) ?ViewSpec.parse(json),
];

/// The same views as JSON, as an editor offers them to start from.
final List<Map<String, dynamic>> builtinViewJson = [
  for (final source in [_medication, _vehicle, _emergency, _wifi])
    jsonDecode(source) as Map<String, dynamic>,
];

const _wifi = r'''
{
  "version": 1, "id": "wifi", "name": "Wi-Fi network", "accent": "teal",
  "match": ["network_name", "wifi_password"],
  "blocks": [
    { "type": "split",
      "main": [
        { "type": "header", "icon": "wifi", "eyebrow": "Wi-Fi network",
          "title": "{network_name}" },
        { "type": "badges", "items": [
          { "text": "Guest network", "tone": "accent",
            "when": { "key": "guest_network", "is": "true" } } ] },
        { "type": "secret", "label": "Password", "key": "wifi_password" },
        { "type": "actions", "items": [
          { "label": "Router admin", "key": "router_admin", "kind": "url" } ] }
      ],
      "side": [
        { "type": "qr", "revealWith": "wifi_password",
          "data": "WIFI:T:WPA;S:{network_name|wifi};P:{wifi_password|wifi};;",
          "caption": "Scan with a phone camera to join." }
      ] }
  ]
}
''';

const _emergency = r'''
{
  "version": 1, "id": "emergency", "name": "Emergency card", "accent": "red",
  "match": ["blood_type"],
  "blocks": [
    { "type": "header", "icon": "health", "eyebrow": "Medical emergency card",
      "title": "{full_name}" },
    { "type": "badges", "items": [
      { "text": "Organ donor", "tone": "success",
        "when": { "key": "organ_donor", "is": "true" } },
      { "text": "Blood type {blood_type}", "tone": "danger",
        "when": { "key": "blood_type" } } ] },
    { "type": "facts", "items": [
      { "label": "Allergies", "value": "{allergies}" },
      { "label": "Medications", "value": "{medications}" },
      { "label": "Insurance", "value": "{insurance_provider}" },
      { "label": "Insurance number", "value": "{insurance_number}", "mono": true }
    ] },
    { "type": "divider", "when": { "key": "contact_name" } },
    { "type": "facts", "items": [
      { "label": "Emergency contact", "value": "{contact_name}" },
      { "label": "Relation", "value": "{contact_relation}" },
      { "label": "Doctor", "value": "{doctor_name}" }
    ] },
    { "type": "actions", "items": [
      { "label": "Call {contact_name}", "key": "contact_phone", "kind": "tel" },
      { "label": "Call the doctor", "key": "doctor_phone", "kind": "tel" } ] }
  ]
}
''';

const _vehicle = r'''
{
  "version": 1, "id": "vehicle", "name": "Vehicle", "accent": "blue",
  "match": ["license_plate"],
  "blocks": [
    { "type": "header", "icon": "car", "eyebrow": "{make_model}",
      "title": "{license_plate|upper}" },
    { "type": "countdown", "label": "Next inspection", "key": "inspection_due",
      "warnDays": 45 },
    { "type": "facts", "items": [
      { "label": "Vehicle identification number", "value": "{vin}", "mono": true },
      { "label": "Insurer", "value": "{insurer}" },
      { "label": "Policy number", "value": "{policy_number}", "mono": true }
    ] },
    { "type": "actions", "items": [
      { "label": "Call {insurer}", "key": "insurer_phone", "kind": "tel" } ] }
  ]
}
''';

const _medication = r'''
{
  "version": 1, "id": "medication", "name": "Medication plan",
  "accent": "violet",
  "match": ["group:medication"],
  "blocks": [
    { "type": "header", "icon": "medication", "eyebrow": "Medication plan",
      "title": "{patient_name}", "subtitle": "Prescribed by {prescriber}" },
    { "type": "schedule", "group": "medication", "heading": "Medicine",
      "label": "name", "detail": "dose", "note": "note", "until": "until",
      "columns": [
        { "field": "morning", "label": "Morn", "time": "08:00" },
        { "field": "noon", "label": "Noon", "time": "12:00" },
        { "field": "evening", "label": "Eve", "time": "18:00" },
        { "field": "night", "label": "Night", "time": "22:00" } ],
      "next": true,
      "refill": { "stock": "stock", "warnDays": 7 } },
    { "type": "text", "text": "Check with the doctor before changing a dose." }
  ]
}
''';
