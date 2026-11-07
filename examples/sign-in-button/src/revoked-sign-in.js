// "Continue with Revoked" as one element: the button, and the panel it opens.
//
// This is the source. `node build.mjs` turns it and qrcode.mjs into the single
// file ../revoked-sign-in.js that services copy; edit here, then rebuild.
//
//   <script type="module" src="/revoked/revoked-sign-in.js"></script>
//   <revoked-sign-in start="/auth/revoked/start" wait="/auth/revoked/wait"></revoked-sign-in>
//
// `start` and `wait` are the service's own routes; docs/api/sign-in.md says
// what they answer. When the sign-in finishes the page reloads, or goes to
// `done="…"` if set; calling preventDefault() on the `revoked-sign-in-done`
// event keeps it where it is.
//
// Look: label="continue|signin|signup|icon", theme="black|white|outline|auto",
// shape="rounded|pill", size="s|m|l", width="fit|full", lang="en|de".

import qrcode from '../qrcode.mjs';

const ASK_EVERY_MS = 2000;

const STRINGS = {
  en: {
    continue: 'Continue with Revoked',
    signin: 'Sign in with Revoked',
    signup: 'Sign up with Revoked',
    opening: 'Opening Revoked…',
    scan: 'Scan this code with the Revoked app on your phone.',
    scanElsewhere: 'On another device? Scan this code there.',
    open: 'Open Revoked on this device',
    openPhone: 'Open Revoked',
    check: 'Approve only if the app shows {code}.',
    waiting: 'Waiting for approval…',
    close: 'Close',
    qr: 'QR code to sign in with Revoked',
    startAgain: 'Start again',
    declined: 'Sign-in declined.',
    expired: 'This sign-in has expired.',
    failed: 'Signing in didn’t work. Please try again.',
  },
  de: {
    continue: 'Weiter mit Revoked',
    signin: 'Mit Revoked anmelden',
    signup: 'Mit Revoked registrieren',
    opening: 'Revoked wird geöffnet …',
    scan: 'Scanne diesen Code mit der Revoked-App auf deinem Handy.',
    scanElsewhere: 'Auf einem anderen Gerät? Scanne den Code dort.',
    open: 'Revoked auf diesem Gerät öffnen',
    openPhone: 'Revoked öffnen',
    check: 'Bestätige nur, wenn die App {code} zeigt.',
    waiting: 'Warte auf Bestätigung …',
    close: 'Schließen',
    qr: 'QR-Code zum Anmelden mit Revoked',
    startAgain: 'Erneut starten',
    declined: 'Anmeldung abgelehnt.',
    expired: 'Diese Anmeldung ist abgelaufen.',
    failed: 'Die Anmeldung hat nicht geklappt. Bitte versuche es erneut.',
  },
};

const LABELS = ['continue', 'signin', 'signup', 'icon'];
const THEMES = ['black', 'white', 'outline', 'auto'];
const SIZES = ['s', 'm', 'l'];

// Adopted rather than a <style> element, so a page with a strict
// Content-Security-Policy needs no 'unsafe-inline' for it.
//
// Sizes are pixels with a floor in rem: a page that shrinks its root font
// (the 62.5 % trick) keeps a full-size button, and a visitor who raises
// their default text size gets a larger one. Heights are minimums, so a
// long label wraps instead of being cut off.
const sheet = new CSSStyleSheet();
sheet.replaceSync(`
:host { display: inline-block; vertical-align: middle; max-width: 100%;
  --fg: #191c20; --muted: #50565f; --bg: #fff; --line: #d9dde5; --solid: #000; --on-solid: #fff; }
:host([width="full"]) { display: block; }
:host([hidden]) { display: none; }
@media (prefers-color-scheme: dark) {
  :host { --fg: #e1e2e8; --muted: #a9aeb7; --bg: #181c21; --line: #2c3137; --solid: #fff; --on-solid: #000; }
}
* { box-sizing: border-box; }
.sr { position: absolute; width: 1px; height: 1px; margin: -1px; padding: 0; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; border: 0; }
button { font-family: system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; -webkit-tap-highlight-color: transparent; }

/* The button */
.go {
  --h: 44px; --px: 18px; --gap: 10px; --fs: max(16px, 1rem); --r: 10px;
  --b: #000; --f: #fff; --edge: rgb(255 255 255 / .2); --hover: #24272d; --press: #383c44;
  display: inline-flex; align-items: center; justify-content: center; gap: var(--gap);
  min-height: var(--h); min-width: var(--h); max-width: 100%; margin: 0;
  padding-block: 8px; padding-inline: var(--px);
  font-size: var(--fs); font-weight: 600; line-height: 1.25; letter-spacing: .005em;
  text-align: center; text-wrap: balance; overflow-wrap: anywhere;
  color: var(--f); background: var(--b); border: 1px solid var(--edge); border-radius: var(--r);
  cursor: pointer; transition: background-color .12s ease;
}
.go svg { width: 1.125em; height: 1.125em; flex: none; fill: currentColor; }
.go:hover { background: var(--hover); }
.go:active { background: var(--press); }
.go[aria-busy="true"] { cursor: progress; }
.go.s { --h: 36px; --px: 14px; --gap: 8px; --fs: max(14px, .875rem); --r: 8px; }
.go.l { --h: 52px; --px: 22px; --gap: 12px; --fs: max(17px, 1.0625rem); --r: 12px; }
.go.pill { --r: 999px; }
.go.icon { padding-inline: 0; width: var(--h); }
.go.icon svg { width: 1.25em; height: 1.25em; }
:host([width="full"]) .go:not(.icon) { display: flex; width: 100%; }
.go.white { --b: #fff; --f: #000; --edge: rgb(0 0 0 / .16); --hover: #eef0f3; --press: #e0e3e8; }
.go.outline { --b: transparent; --f: currentColor; --edge: currentColor; --hover: rgb(127 127 127 / .12); --press: rgb(127 127 127 / .2); }
@media (prefers-color-scheme: dark) {
  .go.auto { --b: #fff; --f: #000; --edge: rgb(0 0 0 / .16); --hover: #eef0f3; --press: #e0e3e8; }
}

/* Focus: a white band and a black ring. Every colour has at least 4.5:1
   against black or against white, so one of the two always shows. */
.go:focus-visible, .act:focus-visible, .alt:focus-visible, .x:focus-visible { outline: 2px solid #000; outline-offset: 2px; box-shadow: 0 0 0 2px #fff; }

.go[aria-busy="true"] svg rect { animation: bars 1.2s infinite ease-in-out; }
.go[aria-busy="true"] svg rect:nth-child(2) { animation-delay: .12s; }
.go[aria-busy="true"] svg rect:nth-child(3) { animation-delay: .24s; }
.go[aria-busy="true"] svg rect:nth-child(4) { animation-delay: .36s; }
@keyframes bars { 0%, 100% { opacity: 1; } 50% { opacity: .3; } }

/* The theme says what the page behind the button looks like, so the error
   colour follows the theme: black sits on light pages, white on dark ones,
   outline takes the page's own text colour. */
.problem { display: flex; align-items: flex-start; gap: 6px; margin: 8px 0 0; max-width: 34ch; color: #b3261e;
  font: 14px/1.4 system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif; }
:host([theme="white"]) .problem { color: #ffb4ab; }
:host([theme="outline"]) .problem { color: inherit; }
@media (prefers-color-scheme: dark) { :host([theme="auto"]) .problem { color: #ffb4ab; } }
.problem[hidden] { display: none; }
.problem svg { width: 1em; height: 1em; flex: none; margin-top: .2em; fill: currentColor; }

/* The panel. Three kinds of text only: the title, body text (instructions,
   buttons, status alike) and the check code. */
dialog { width: min(360px, calc(100vw - 32px)); max-height: calc(100dvh - 32px); overflow: auto; padding: 20px;
  color: var(--fg); background: var(--bg); border: 1px solid var(--line); border-radius: 16px;
  font: 14px/1.45 system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif; }
dialog::backdrop { background: rgb(0 0 0 / .6); }
.head { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
h2 { display: flex; align-items: center; gap: 8px; margin: 0; font-size: 17px; font-weight: 600; line-height: 1.3; }
h2 svg { width: 16px; height: 16px; flex: none; fill: currentColor; }
.x { display: grid; place-items: center; flex: none; width: 36px; height: 36px; margin: -6px -8px -6px 0; padding: 0; color: var(--fg); background: transparent;
  border: 0; border-radius: 8px; cursor: pointer; }
.x:hover { background: rgb(127 127 127 / .14); }
.x svg { width: 14px; height: 14px; stroke: currentColor; stroke-width: 2; stroke-linecap: round; fill: none; }
p { margin: 0; }
.panel { display: flex; flex-direction: column; gap: 16px; text-align: center; }
.qr { display: block; width: min(208px, 100%); margin: 0 auto; background: #fff; border-radius: 8px; }
.code { font: 700 1em/1 ui-monospace, 'SF Mono', SFMono-Regular, Menlo, Consolas, monospace; letter-spacing: .06em;
  font-variant-numeric: slashed-zero; white-space: nowrap; }
.act, .alt { display: flex; align-items: center; justify-content: center; min-height: 44px; margin: 0; padding: 10px 16px;
  font: inherit; font-weight: 600; text-align: center; border-radius: 10px; cursor: pointer; }
.act { color: var(--on-solid); background: var(--solid); border: 1px solid var(--solid); }
.act:hover { opacity: .88; }
.alt { color: var(--fg); background: transparent; border: 1px solid var(--line); }
.alt:hover { background: rgb(127 127 127 / .1); }
.act[aria-busy="true"] { cursor: progress; }
.status { display: flex; align-items: center; justify-content: center; gap: 10px; margin: 0 -20px -20px; padding: 14px 20px; border-top: 1px solid var(--line); }
.status svg { width: 14px; height: 14px; flex: none; fill: currentColor; }
.status svg rect { animation: bars 1.2s infinite ease-in-out; }
.status svg rect:nth-child(2) { animation-delay: .12s; }
.status svg rect:nth-child(3) { animation-delay: .24s; }
.status svg rect:nth-child(4) { animation-delay: .36s; }

@media (max-height: 520px) and (min-width: 560px) {
  dialog { width: min(600px, calc(100vw - 32px)); padding: 14px 20px 20px; }
  .head { margin-bottom: 8px; }
  .panel { display: grid; grid-template-columns: 180px 1fr; column-gap: 20px; row-gap: 12px; align-content: start; text-align: start; }
  .panel > * { grid-column: 2; }
  .panel > .qr { grid-column: 1; grid-row: 1 / span 4; }
  .status { margin: 0; padding: 12px 0 0; }
}

@media (prefers-reduced-motion: reduce) {
  .go { transition: none; }
  .go[aria-busy="true"] svg rect, .status svg rect { animation: none; opacity: .55; }
}

@media (forced-colors: active) {
  .go, .act, .alt { color: ButtonText; background: ButtonFace; border: 1px solid ButtonText; }
  .x { border: 1px solid ButtonText; }
  .go:focus-visible, .act:focus-visible, .alt:focus-visible, .x:focus-visible { outline-color: Highlight; box-shadow: none; }
}
`);

const SVG = 'http://www.w3.org/2000/svg';

function svgEl(name, attrs) {
  const node = document.createElementNS(SVG, name);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  return node;
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text) node.textContent = text;
  return node;
}

function markSvg() {
  const svg = svgEl('svg', { viewBox: '100 100 300 300', 'aria-hidden': 'true', focusable: 'false' });
  for (const [x, y, width] of [[100, 100, 300], [140, 185.33, 220], [100, 270.67, 300], [180, 356, 140]]) {
    svg.append(svgEl('rect', { x, y, width, height: 44 }));
  }
  return svg;
}

function warnSvg() {
  const svg = svgEl('svg', { viewBox: '0 0 16 16', 'aria-hidden': 'true', focusable: 'false' });
  svg.append(svgEl('path', { d: 'M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1Zm-.75 3.5h1.5v5h-1.5v-5Zm0 6.25h1.5v1.5h-1.5v-1.5Z' }));
  return svg;
}

function crossSvg() {
  const svg = svgEl('svg', { viewBox: '0 0 14 14', 'aria-hidden': 'true', focusable: 'false' });
  svg.append(svgEl('path', { d: 'M2 2l10 10M12 2L2 12' }));
  return svg;
}

function qrSvg(text, label) {
  const code = qrcode(0, 'L');
  code.addData(text);
  code.make();
  const size = code.getModuleCount();
  const quiet = 4;
  let path = '';
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (code.isDark(y, x)) path += `M${x + quiet} ${y + quiet}h1v1h-1z`;
    }
  }
  const svg = svgEl('svg', {
    class: 'qr',
    viewBox: `0 0 ${size + quiet * 2} ${size + quiet * 2}`,
    role: 'img',
    'aria-label': label,
    'shape-rendering': 'crispEdges',
  });
  svg.append(svgEl('path', { d: path, fill: '#000' }));
  return svg;
}

// "0D2-99B" is read out as "0 D 2, 9 9 B", one character at a time.
function spelled(code) {
  return code.split('-').map((group) => [...group].join(' ')).join(', ');
}

// A web page cannot tell whether the app is on this device. A phone most
// likely holds it, so there the link leads; on a computer the code does.
function onPhone() {
  return navigator.userAgentData?.mobile ?? /Android|iPhone|iPad|iPod/.test(navigator.userAgent);
}

async function post(url, body) {
  const res = await fetch(url, {
    method: 'POST',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: res.status, ok: res.ok, json: res.ok ? await res.json() : null };
}

function pick(value, allowed, fallback) {
  return allowed.includes(value) ? value : fallback;
}

class RevokedSignIn extends HTMLElement {
  static observedAttributes = ['label', 'theme', 'shape', 'size', 'lang'];

  #timer = null;
  #asking = false;
  #busy = false;
  #wait = '';
  #dialog = null;
  #panel = null;
  #button = null;
  #label = null;
  #problem = null;
  #announce = null;

  connectedCallback() {
    if (this.shadowRoot) return;
    const root = this.attachShadow({ mode: 'open' });
    root.adoptedStyleSheets = [sheet];

    this.#button = el('button', 'go');
    this.#button.type = 'button';
    this.#button.setAttribute('part', 'button');
    this.#label = el('span');
    this.#button.append(markSvg(), this.#label);
    this.#button.addEventListener('click', () => this.#start());

    this.#problem = el('p', 'problem');
    this.#problem.setAttribute('part', 'error');
    this.#problem.setAttribute('role', 'alert');
    this.#problem.hidden = true;

    // Announces "Opening Revoked…" while the button waits for `start`.
    this.#announce = el('span', 'sr');
    this.#announce.setAttribute('role', 'status');

    root.append(this.#button, this.#problem, this.#announce);
    this.#render();
  }

  attributeChangedCallback() {
    if (this.#button) this.#render();
  }

  disconnectedCallback() {
    this.#stop();
    this.#dialog?.close();
  }

  #lang() {
    const lang = (this.lang || this.closest('[lang]')?.lang || document.documentElement.lang || navigator.language || 'en')
      .slice(0, 2)
      .toLowerCase();
    return STRINGS[lang] ? lang : 'en';
  }

  #t(key) {
    return STRINGS[this.#lang()][key];
  }

  #labelKey() {
    return pick(this.getAttribute('label'), LABELS, 'continue');
  }

  #title() {
    const key = this.#labelKey();
    return this.#t(key === 'icon' ? 'continue' : key);
  }

  #render() {
    const label = this.#labelKey();
    const theme = pick(this.getAttribute('theme'), THEMES, 'black');
    const size = pick(this.getAttribute('size'), SIZES, 'm');
    const pill = this.getAttribute('shape') === 'pill';
    const b = this.#button;
    b.className = ['go', theme, size, pill ? 'pill' : '', label === 'icon' ? 'icon' : ''].filter(Boolean).join(' ');
    b.lang = this.#lang();
    this.#problem.lang = b.lang;
    if (label === 'icon') {
      this.#label.textContent = '';
      this.#label.hidden = true;
      b.setAttribute('aria-label', this.#title());
    } else {
      this.#label.textContent = this.#title();
      this.#label.hidden = false;
      b.removeAttribute('aria-label');
    }
  }

  #say(key) {
    this.#problem.replaceChildren();
    if (key) this.#problem.append(warnSvg(), el('span', '', this.#t(key)));
    this.#problem.hidden = !key;
  }

  #setBusy(on) {
    this.#busy = on;
    // Busy, not disabled: the button keeps its focus and stays in the tab order.
    if (on) {
      this.#button.setAttribute('aria-busy', 'true');
      this.#button.setAttribute('aria-disabled', 'true');
      this.#announce.textContent = this.#t('opening');
    } else {
      this.#button.removeAttribute('aria-busy');
      this.#button.removeAttribute('aria-disabled');
      this.#announce.textContent = '';
    }
  }

  async #start() {
    if (this.#busy) return;
    this.#say(null);
    this.#setBusy(true);
    try {
      const start = this.getAttribute('start');
      if (!start || !this.getAttribute('wait')) throw new Error('the start and wait attributes are both needed');
      const { ok, json } = await post(start, {});
      if (!ok) throw new Error('start refused');
      if (!json?.app_link?.startsWith('revoked://signin?') || !json.wait) throw new Error('start answered badly');
      this.#wait = json.wait;
      this.#show(json.app_link, json.check_code);
    } catch (err) {
      console.error('revoked-sign-in:', err);
      if (this.#dialog?.open) this.#showEnd('failed');
      else this.#say('failed');
    } finally {
      this.#setBusy(false);
    }
  }

  #openDialog() {
    if (this.#dialog?.open) return;
    const dialog = el('dialog', onPhone() ? 'phone' : '');
    dialog.lang = this.#lang();
    dialog.setAttribute('part', 'panel');
    dialog.setAttribute('aria-labelledby', 'revoked-title');

    const title = el('h2');
    title.id = 'revoked-title';
    title.append(markSvg(), this.#title());
    const close = el('button', 'x');
    close.type = 'button';
    close.setAttribute('aria-label', this.#t('close'));
    close.append(crossSvg());
    close.addEventListener('click', () => dialog.close());
    const head = el('div', 'head');
    head.append(title, close);

    this.#panel = el('div', 'panel');
    dialog.append(head, this.#panel);
    dialog.addEventListener('close', () => {
      this.#stop();
      dialog.remove();
      if (this.#dialog === dialog) this.#dialog = null;
      // Back where the person was, even where the browser does not restore it.
      if (this.isConnected) this.#button.focus();
    });
    this.shadowRoot.append(dialog);
    this.#dialog = dialog;
    dialog.showModal();
  }

  #show(appLink, checkCode) {
    this.#openDialog();
    // A phone most likely holds the app, so opening it leads there; on a
    // computer the code does, and opening it here is the quiet alternative.
    const phone = this.#dialog.classList.contains('phone');

    const open = el('button', phone ? 'act' : 'alt', this.#t(phone ? 'openPhone' : 'open'));
    open.type = 'button';
    // Stays on this page, which keeps waiting for the answer.
    open.addEventListener('click', () => location.assign(appLink));

    // "Approve only if the app shows 0D2-99B." The code is read out one
    // character at a time; the sentence around it stays as written.
    const check = el('p', 'check');
    const [before, after] = this.#t('check').split('{code}');
    const code = el('span', 'code', checkCode);
    code.setAttribute('aria-hidden', 'true');
    check.append(before, code, el('span', 'sr', spelled(checkCode || '')), after);

    // Filled a moment after the panel opens, so it is announced once.
    const said = el('span');
    const status = el('p', 'status');
    status.setAttribute('role', 'status');
    status.append(markSvg(), said);
    setTimeout(() => (said.textContent = this.#t('waiting')), 400);

    const scan = el('p', '', this.#t(phone ? 'scanElsewhere' : 'scan'));
    const qr = qrSvg(appLink, this.#t('qr'));
    this.#panel.replaceChildren(...(phone ? [open, check, scan, qr, status] : [scan, qr, check, open, status]));
    open.focus();

    this.#stop();
    this.#timer = setInterval(() => this.#ask(), ASK_EVERY_MS);
    // A phone browser sleeps while the app is open, so ask the moment it's back.
    document.addEventListener('visibilitychange', this.#onVisible);
  }

  // The sign-in is over without an answer: say why, and offer a new one in place.
  #showEnd(key) {
    this.#stop();
    const said = el('p', '', this.#t(key));
    said.setAttribute('role', 'alert');
    const again = el('button', 'act', this.#t('startAgain'));
    again.type = 'button';
    const note = el('p', 'sr');
    note.setAttribute('role', 'status');
    again.addEventListener('click', () => {
      if (this.#busy) return;
      // The button outside the panel is hidden behind it, so the panel shows
      // and announces the wait itself.
      again.setAttribute('aria-busy', 'true');
      again.replaceChildren(this.#t('opening'));
      note.textContent = this.#t('opening');
      this.#start();
    });
    this.#panel.replaceChildren(said, again, note);
    again.focus();
  }

  #onVisible = () => {
    if (document.visibilityState === 'visible') this.#ask();
  };

  #stop() {
    clearInterval(this.#timer);
    this.#timer = null;
    document.removeEventListener('visibilitychange', this.#onVisible);
  }

  async #ask() {
    if (this.#asking || !this.#timer) return;
    this.#asking = true;
    try {
      const { status, ok, json } = await post(this.getAttribute('wait'), { wait: this.#wait });
      if (!this.#timer) return;
      if (status === 401 || status === 404 || status === 410) return this.#showEnd('expired');
      if (ok && json.done) {
        if (json.error) return this.#end(json.error === 'access_denied' ? 'declined' : 'failed');
        this.#end(null);
        const go = this.dispatchEvent(new CustomEvent('revoked-sign-in-done', { bubbles: true, composed: true, cancelable: true }));
        if (go) location.assign(this.getAttribute('done') || location.href);
      }
      // Anything else is a bad moment, not an answer: ask again.
    } catch {
      // Likewise: a phone loses its connection when it is put away.
    } finally {
      this.#asking = false;
    }
  }

  #end(problem) {
    this.#stop();
    this.#dialog?.close();
    this.#say(problem);
  }
}

if (!customElements.get('revoked-sign-in')) customElements.define('revoked-sign-in', RevokedSignIn);
