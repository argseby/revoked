// HTML for the three things the demo shows: the sign-in form, the account,
// and an error. Everything that came from elsewhere is escaped.

const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

export function escape(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ESCAPES[c]);
}

function layout(title, body) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)} · Corner Shop</title>
<link rel="stylesheet" href="/style.css">
</head>
<body>
<header><span class="brand">Corner Shop</span><span class="tag">Sign in with Revoked · demo</span></header>
<main>${body}</main>
</body>
</html>`;
}

export function signInPage({ defaultServer, requestedKeys, error }) {
  const asks = requestedKeys.length
    ? `<p class="muted">At checkout the shop asks for ${requestedKeys
        .map((k) => `<code>${escape(k)}</code>`)
        .join(', ')}. You choose which entries to share, and they stay in your vault.</p>`
    : '';
  return layout(
    'Sign in',
    `<section class="card">
  <h1>Sign in</h1>
  <p>The shop keeps no passwords. Sign in with your Revoked account.</p>
  ${error ? `<p class="error" role="alert">${escape(error)}</p>` : ''}
  <form method="post" action="/login/app">
    <button type="submit">Sign in with Revoked</button>
  </form>
  <p class="muted small">Opens the Revoked app, which continues on your own server.</p>
  ${asks}
  <details${error ? ' open' : ''}>
    <summary>No Revoked app on this device?</summary>
    <form method="post" action="/login">
      <label for="server">Your Revoked server</label>
      <input id="server" name="server" value="${escape(defaultServer)}" placeholder="revoked.example" autocomplete="url" required>
      <button class="quiet" type="submit">Continue in the browser</button>
    </form>
  </details>
</section>`,
  );
}

const STATUS_TEXT = {
  active: 'Shared',
  paused: 'Paused by you',
  revoked: 'Revoked by you',
  expired: 'Expired',
  not_found: 'No longer available',
};

function grantRows(grants) {
  if (!grants.length) {
    return '<p class="muted">Nothing was shared at sign-in. The shop would ask you for an address at checkout.</p>';
  }
  return grants
    .map((g) => {
      const rows = g.keys
        .map((key) => {
          const value = g.values[key];
          return `<tr><th><code>${escape(key)}</code></th><td>${
            value === undefined ? '<span class="muted">—</span>' : escape(value)
          }</td></tr>`;
        })
        .join('');
      const read = g.readAt
        ? `Read from your server at ${g.readAt.toLocaleTimeString('en-GB')}; kept for at most ${g.maxAge} s.`
        : '';
      return `<div class="grant">
  <span class="status status-${escape(g.status)}">${escape(STATUS_TEXT[g.status] ?? g.status)}</span>
  <table>${rows}</table>
  <p class="muted small">${escape(read)}</p>
</div>`;
    })
    .join('');
}

export function accountPage({ user, grants, grantError }) {
  const greeting = user.name ? `Hello, ${escape(user.name)}` : 'Hello';
  return layout(
    'Your account',
    `<section class="card">
  <h1>${greeting}</h1>
  <dl>
    <dt>Email</dt><dd>${user.email ? escape(user.email) : '<span class="muted">not shared</span>'}${
      user.email && !user.emailVerified ? ' <span class="muted">(unconfirmed)</span>' : ''
    }</dd>
    <dt>Signed in with</dt><dd>${escape(user.issuer)}</dd>
    <dt>Your id at this shop</dt><dd><code class="small">${escape(user.subject)}</code></dd>
  </dl>
  <p class="muted small">The id is the shop's own: the same person has a different one at every other service.</p>
</section>
<section class="card">
  <h2>Delivery details</h2>
  ${grantError ? `<p class="error" role="alert">${escape(grantError)}</p>` : grantRows(grants)}
  <p class="muted small">Edit or revoke these in your Revoked app, then reload this page.</p>
</section>
<form method="post" action="/logout"><button class="quiet" type="submit">Sign out</button></form>`,
  );
}

export function errorPage(message) {
  return layout(
    'Something went wrong',
    `<section class="card">
  <h1>Signing in did not work</h1>
  <p class="error" role="alert">${escape(message)}</p>
  <p><a href="/">Back to the start</a></p>
</section>`,
  );
}
