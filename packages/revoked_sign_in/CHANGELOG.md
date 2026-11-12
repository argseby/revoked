## 0.1.2

- Builds against `qr` 4: the QR code is created with `QrPayload.fromString`
  and `QrErrorCorrectLevel.low`. 0.1.1 did not compile.
- Source formatted with `dart format`.

## 0.1.1

- `qr` dependency raised to `^4.0.1`.
- GPL-3.0 license added.

## 0.1.0

First release.

- `RevokedSignInButton`, drawn to spec v1 of the sign-in button: labels
  "Continue with", "Sign in with", "Sign up with" and icon only; black, white,
  outline and auto themes; rounded and pill shapes; sizes 36, 44 and 52; full
  width.
- The panel: QR code, opening the app on this device, the check code, waiting,
  and "Start again" when a sign-in expires. Phone apps open the Revoked app at
  once.
- English and German.
- `"client": "app"` on each `wait` request outside the web, so a service can
  answer with a session in the body.
- Keyboard use, screen reader labels, a focus ring that shows on any
  background, 48-point touch areas on Android, larger text, increased contrast
  and reduced motion.
