import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/state/shell_slots.dart';

/// A record opened over the vault claims the top bar; closing it must hand
/// the bar back to the vault still mounted underneath, which never claims
/// again. When the slot held a single builder, the release blanked it and the
/// vault's search was gone until the tab was switched.
void main() {
  Widget list(BuildContext _) => const SizedBox();
  Widget detail(BuildContext _) => const SizedBox();
  Widget otherTab(BuildContext _) => const SizedBox();

  test('releasing a detail page hands the slot back to its list', () {
    final slot = ShellSlot();
    slot.claim(list);
    slot.claim(detail);
    expect(slot.builder, detail);

    slot.release(detail);
    expect(slot.builder, list);

    slot.release(list);
    expect(slot.builder, isNull);
  });

  test('a late release does not wipe the next screen\'s claim', () {
    final slot = ShellSlot();
    slot.claim(list);
    // Switching tabs: the new screen claims before the old one disposes.
    slot.claim(otherTab);
    slot.release(list);
    expect(slot.builder, otherTab);
  });

  test('claiming again moves a screen to the top without duplicating it', () {
    final slot = ShellSlot();
    slot.claim(list);
    slot.claim(detail);
    slot.claim(list);
    expect(slot.builder, list);

    slot.release(list);
    expect(slot.builder, detail);
  });
}
