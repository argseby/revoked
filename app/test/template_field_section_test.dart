import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/features/vault/view/template_field_fill.dart';

void main() {
  test('an answer is filed where the template put its field', () {
    final json =
        jsonDecode(
              File(
                '../templates/medical_emergency_card.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final template = Template(
      id: 't',
      name: json['name'] as String,
      description: '',
      workspace: '',
      schema: json['schema'] as Map<String, dynamic>,
      created: DateTime(2026),
      updated: DateTime(2026),
    );
    final sections = {
      for (final f in templateFieldsOf(template))
        f.key: templateFieldSection(template, f),
    };

    // A name is personal data, filed with the rest of it.
    expect(sections['full_name'], (
      key: 'personal_information',
      name: 'Personal information',
    ));
    // What the template lists on its own goes under the template's name.
    expect(sections['blood_type'], (
      key: 'medical_emergency_card',
      name: 'Medical emergency card',
    ));
    expect(sections['contact_phone'], (
      key: 'emergency_contact',
      name: 'Emergency contact',
    ));
    expect(sections['doctor_name'], (key: 'doctor', name: 'Doctor'));
  });
}
