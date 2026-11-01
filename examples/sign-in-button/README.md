# Sign in with Revoked, as one element

The button, and the panel it opens: a QR code for a phone, a link for this
device, and the check code. It works whether or not the Revoked app is on the
device the person is using, and it fetches nothing from anywhere else.

Copy this folder next to your static files, then:

```html
<script type="module" src="/revoked/revoked-sign-in.js"></script>
<revoked-sign-in start="/auth/revoked/start" wait="/auth/revoked/wait"></revoked-sign-in>
```

`start` and `wait` are your own routes.
[Add it to your service](../../docs/api/sign-in.md#add-it-to-your-service) says
what they answer, and [`examples/sign-in-demo`](../sign-in-demo) has them
running.

| Attribute | Meaning |
|---|---|
| `start` | Your route that prepares a sign-in. |
| `wait` | Your route the page asks until the sign-in is finished. |
| `done` | Where to go afterwards. Without it the page reloads. |
| `lang` | `en` or `de`. Without it, the page's language. |

The element fires `revoked-sign-in-done` when the person is signed in. Call
`preventDefault()` on it to stay on the page.

A page with a Content-Security-Policy needs `script-src 'self'` and
`connect-src 'self'`; no inline styles or scripts are used.

`qrcode.mjs` is [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator)
2.0.4 by Kazuhiko Arase, under the MIT license, unchanged.
