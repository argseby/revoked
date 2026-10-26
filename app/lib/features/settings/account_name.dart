import 'package:flutter/material.dart';

import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// Sets or changes the account's own name — what a service receives as
/// "Your name" when someone signs in there with Revoked and allows it.
///
/// Returns the saved name, or null when nothing was saved (cancelled,
/// unchanged, or refused by the server, which a toast then says). With
/// [allowEmpty] false an emptied field saves nothing: where a name is about
/// to be shared, removing it is done by not ticking it.
Future<String?> openAccountNameSheet(
  BuildContext context, {
  bool allowEmpty = true,
}) async {
  final auth = Stores.auth;
  final current = auth.currentUser?.name ?? '';
  final controller = auth.nameDraft..text = current;
  final done = await showAppEditSheet(
    context: context,
    title: current.isEmpty ? 'Add your name' : 'Change your name',
    description:
        'Services you sign in to with Revoked receive this name when you '
        'allow it. It does not change the name on your identity, which '
        'others see when you share or request data.',
    hint: 'Ada Lovelace',
    controller: controller,
    doneLabel: 'Save',
  );
  final next = controller.text.trim();
  if (!done || next == current || (next.isEmpty && !allowEmpty)) {
    return null;
  }
  final ok = await auth.updateName(next);
  if (!context.mounted) return ok ? next : null;
  if (ok) {
    AppToast.success(context, next.isEmpty ? 'Name removed' : 'Name saved');
    return next;
  }
  AppToast.error(
    context,
    'Could not save your name',
    subtitle: auth.errorMessage,
  );
  return null;
}
