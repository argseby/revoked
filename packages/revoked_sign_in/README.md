# Continue with Revoked, for Flutter

The official sign-in button and the panel it opens, drawn natively to the same
spec as the web component in
[`examples/sign-in-button`](https://github.com/argseby/revoked/tree/main/examples/sign-in-button). It runs on Android,
iOS, macOS, Windows, Linux and the web, and uses no Material or Cupertino
widgets, so it fits any design system.

```dart
import 'package:revoked_sign_in/revoked_sign_in.dart';

RevokedSignInButton(
  start: Uri.parse('https://game.example/auth/revoked/start'),
  wait: Uri.parse('https://game.example/auth/revoked/wait'),
  onSignedIn: (answer) {
    // On the web the session is already a cookie. In an app, `answer`
    // carries what the wait route hands over, e.g. answer['session'].
  },
)
```

`start` and `wait` are the service's own routes.
[Add it to your service](https://docs.revoked.link/api/sign-in/#add-it-to-your-service) says
what they answer. Outside the web they must be absolute URLs.

## What happens on a press

1. The button calls `start` and shows the panel: on a computer the QR code
   leads and "Open Revoked on this device" is the quiet alternative; on a phone
   "Open Revoked" leads and the QR code is there for another device.
2. In a phone app, the Revoked app is opened at once. The panel waits behind it,
   and asks again the moment the app returns to the foreground.
3. The panel asks `wait` every two seconds. On approval it closes and
   `onSignedIn` receives the answer. A decline closes it with "Sign-in
   declined." under the button. An expired sign-in offers "Start again" in the
   panel.

Outside the web, each `wait` request carries `"client": "app"`, so the service
can answer with a session in the body instead of a cookie
([Native apps](https://docs.revoked.link/api/sign-in/#add-it-to-your-service)).

## Options

| Parameter | Values | Default |
|---|---|---|
| `label` | `continueWith` · `signIn` · `signUp` · `iconOnly` | `continueWith` |
| `theme` | `black` · `white` · `outline` · `auto` | `black` |
| `shape` | `rounded` · `pill` | `rounded` |
| `size` | `small` (36) · `medium` (44) · `large` (52) | `medium` |
| `expand` | fill the available width | `false` |
| `locale` | `en` or `de`; otherwise the app's locale | — |
| `onProblem` | told about `declined`, `expired`, `failed` | — |
| `httpClient`, `openApp` | replacements for tests | — |

Black is for light screens, white for dark ones, outline takes the surrounding
text colour, and auto follows light and dark mode.

## Accessibility

- One semantic button with the visible label as its name; icon-only buttons
  carry the full label. Enter and Space press it, and it is in the focus order.
- The focus ring is a white band inside a black ring, so it shows on any
  background. With "increase contrast" the ring and edges are stronger.
- Medium and large meet the 44-point target; on Android the touch area is
  48 points around the drawn button, as with Material buttons.
- The button grows with the text size, and long labels wrap.
- "Opening Revoked…" is announced while `start` answers. Problems are written
  under the button and announced.
- The panel is a modal route: focus moves in, Escape and the close button
  close it, and focus returns to the button. The check code is read out one
  character at a time, and the QR code has a label.
- The loading animation stands still when the platform asks for less motion.

The tests check Flutter's `androidTapTargetGuideline`, `iOSTapTargetGuideline`,
`labeledTapTargetGuideline` and `textContrastGuideline`.

## Development

```bash
flutter test
```

```bash
flutter analyze
```
