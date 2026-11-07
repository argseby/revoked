# Continue with Revoked, as one element

The button, and the panel it opens: a QR code for a phone, a link for this
device, and the check code. It works whether or not the Revoked app is on the
device the person is using, and it fetches nothing from anywhere else.

Copy `revoked-sign-in.js` next to your static files, then:

```html
<script type="module" src="/revoked/revoked-sign-in.js"></script>
<revoked-sign-in start="/auth/revoked/start" wait="/auth/revoked/wait"></revoked-sign-in>
```

`start` and `wait` are your own routes.
[Add it to your service](../../docs/api/sign-in.md#add-it-to-your-service) says
what they answer, and [`examples/sign-in-demo`](../sign-in-demo) has them
running.

## Attributes

| Attribute | Values | Default | Meaning |
|---|---|---|---|
| `start` | a path | — | Your route that prepares a sign-in. Required. |
| `wait` | a path | — | Your route the page asks until the sign-in is finished. Required. |
| `done` | a path | this page | Where to go afterwards. Without it the page reloads. |
| `label` | `continue` · `signin` · `signup` · `icon` | `continue` | "Continue with Revoked", "Sign in with Revoked", "Sign up with Revoked", or the mark alone with the `continue` label as its accessible name. |
| `theme` | `black` · `white` · `outline` · `auto` | `black` | Black for light pages, white for dark pages, outline in the page's text colour, auto follows the visitor's light or dark mode. |
| `shape` | `rounded` · `pill` | `rounded` | Corner style. |
| `size` | `s` · `m` · `l` | `m` | At least 36, 44 or 52 px high. `s` is for pointer-only toolbars; `m` and `l` meet the 44 px touch target. |
| `width` | `fit` · `full` | `fit` | `full` fills its container, for login columns. |
| `lang` | `en` · `de` | the page's language | Language of the button and the panel. |

```html
<revoked-sign-in start="/auth/revoked/start" wait="/auth/revoked/wait"
  label="signin" theme="auto" shape="pill" size="l" width="full"></revoked-sign-in>
```

The element fires `revoked-sign-in-done` when the person is signed in. Call
`preventDefault()` on it to stay on the page.

## Look and accessibility

Text, mark and colours are fixed: the button is not meant to be recoloured or
reworded. `::part(button)`, `::part(error)` and `::part(panel)` are there for
spacing and placement around it.

- A native button with the visible label as its name. Icon-only buttons carry
  the full label as their name.
- 21 : 1 label contrast in the black and white themes. Outline uses the page's
  own text colour.
- The focus ring is a white band inside a black ring, so it shows on any
  background.
- The button grows with the visitor's text size, and a long label wraps instead
  of being cut off.
- While `start` answers, the button is busy rather than disabled: it keeps
  focus, and "Opening Revoked…" is announced. Errors appear in words under the
  button.
- The panel is a modal dialog. On a computer it leads with the QR code and
  offers "Open Revoked on this device"; on a phone it leads with "Open Revoked"
  and offers the QR code for another device. Focus starts on that button,
  Escape and the close button close the panel, and focus returns to the
  button. The check code is read out one character at a time. When a sign-in
  expires, the panel offers "Start again" in place, which shows and announces
  its own wait.
- Windows high contrast uses the system colours. The loading animation stops
  when the visitor asks for reduced motion.

A page with a Content-Security-Policy needs `script-src 'self'` and
`connect-src 'self'`; no inline styles or scripts are used.

## Changing it

`revoked-sign-in.js` is generated. Edit `src/revoked-sign-in.js`, then run:

```bash
node build.mjs
```

`qrcode.mjs` is [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator)
2.0.4 by Kazuhiko Arase, under the MIT license, unchanged. The build includes it
in `revoked-sign-in.js`.
