// "Sign in with Revoked" as one element. Copy this folder next to your other
// static files; nothing is fetched from anywhere else.
//
//   <script type="module" src="/revoked-sign-in.js"></script>
//   <revoked-sign-in start="/auth/revoked/start" wait="/auth/revoked/wait"></revoked-sign-in>
//
// `start` and `wait` are your own routes. docs/api/sign-in.md says what they
// answer. When the sign-in finishes the page reloads, or goes to `done="…"`
// if set; calling preventDefault() on the `revoked-sign-in-done` event keeps
// it where it is.

import qrcode from './qrcode.mjs';

const ASK_EVERY_MS = 2000;

const STRINGS = {
  en: {
    button: 'Sign in with Revoked',
    scan: 'Scan this code with your phone, then approve in the Revoked app.',
    scanElsewhere: 'Is Revoked on another device? Scan this code there.',
    open: 'Open Revoked here',
    check: 'Only continue if the app shows this code:',
    waiting: 'Waiting for you to approve…',
    needsApp: 'You need the Revoked app on your phone or on this device.',
    close: 'Close',
    qr: 'QR code to sign in with Revoked',
    declined: 'Sign-in declined.',
    expired: 'This sign-in took too long. Please try again.',
    failed: 'Signing in didn’t work. Please try again.',
  },
  de: {
    button: 'Mit Revoked anmelden',
    scan: 'Scanne diesen Code mit deinem Handy und bestätige in der Revoked-App.',
    scanElsewhere: 'Ist Revoked auf einem anderen Gerät? Scanne den Code dort.',
    open: 'Revoked hier öffnen',
    check: 'Fahre nur fort, wenn die App diesen Code zeigt:',
    waiting: 'Wir warten auf deine Bestätigung …',
    needsApp: 'Du brauchst die Revoked-App auf deinem Handy oder auf diesem Gerät.',
    close: 'Schließen',
    qr: 'QR-Code zum Anmelden mit Revoked',
    declined: 'Anmeldung abgelehnt.',
    expired: 'Die Anmeldung hat zu lange gedauert. Bitte versuche es erneut.',
    failed: 'Die Anmeldung hat nicht geklappt. Bitte versuche es erneut.',
  },
};

// Adopted rather than a <style> element, so a page with a strict
// Content-Security-Policy needs no 'unsafe-inline' for it.
const sheet = new CSSStyleSheet();
sheet.replaceSync(`
:host { display: inline-block; --fg: #191c20; --muted: #555b64; --bg: #fff; --line: #dde1e8; --bad: #ba1a1a; }
@media (prefers-color-scheme: dark) {
  :host { --fg: #e3e5ea; --muted: #a9aeb7; --bg: #181c21; --line: #2c3137; --bad: #ffb4ab; }
}
* { box-sizing: border-box; font-family: system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif; }
button { cursor: pointer; font-weight: 600; font-size: 15px; line-height: 1; border-radius: 10px; }
button:focus-visible { outline: 2px solid currentColor; outline-offset: 2px; }
.signin { display: inline-flex; align-items: center; gap: 10px; padding: 10px 18px; background: #000; color: #fff; border: 1px solid rgba(255, 255, 255, .18); }
.signin:disabled { opacity: .6; cursor: progress; }
.signin svg { width: 18px; height: 18px; fill: #fff; flex: none; }
.problem { margin: 8px 0 0; color: var(--bad); font-size: 13px; }
dialog { width: min(360px, calc(100vw - 32px)); max-height: calc(100dvh - 32px); overflow: auto; padding: 20px; color: var(--fg); background: var(--bg); border: 1px solid var(--line); border-radius: 16px; }
dialog::backdrop { background: rgba(0, 0, 0, .6); }
h2 { margin: 0 0 12px; font-size: 18px; }
p { margin: 0; font-size: 14px; line-height: 1.45; }
.panel { display: flex; flex-direction: column; gap: 12px; }
.phone .here { order: -1; }
.qr { display: block; width: min(240px, 100%); margin: 0 auto; background: #fff; border-radius: 8px; }
.check { text-align: center; }
code { display: block; margin-top: 2px; font: 700 20px/1.3 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; letter-spacing: .08em; }
.quiet { color: var(--muted); font-size: 13px; }
.here, .close { padding: 12px 16px; color: var(--fg); background: transparent; border: 1px solid var(--line); }
.phone .here { color: #fff; background: #000; border-color: rgba(255, 255, 255, .18); }
.close { align-self: flex-end; }
@media (max-height: 520px) and (min-width: 560px) {
  dialog { width: min(640px, calc(100vw - 32px)); padding: 14px 20px; }
  h2 { margin-bottom: 8px; }
  .panel { gap: 8px; }
  .panel { display: grid; grid-template-columns: 200px 1fr; column-gap: 20px; align-items: start; }
  .here, .close { padding: 10px 16px; }
  .scan { grid-column: 2; }
  .qr { grid-column: 1; grid-row: 1 / span 6; }
  .check, .here, .status, .needs, .close { grid-column: 2; }
  .phone .here { order: 0; }
}
`);

function svgEl(name, attrs) {
  const node = document.createElementNS('http://www.w3.org/2000/svg', name);
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
  const svg = svgEl('svg', { viewBox: '100 100 300 300', 'aria-hidden': 'true' });
  for (const [x, y, width] of [[100, 100, 300], [140, 185.33, 220], [100, 270.67, 300], [180, 356, 140]]) {
    svg.append(svgEl('rect', { x, y, width, height: 44 }));
  }
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

class RevokedSignIn extends HTMLElement {
  #timer = null;
  #asking = false;
  #wait = '';
  #dialog = null;
  #button = null;
  #problem = null;

  connectedCallback() {
    if (this.shadowRoot) return;
    const root = this.attachShadow({ mode: 'open' });
    root.adoptedStyleSheets = [sheet];
    this.#button = el('button', 'signin');
    this.#button.type = 'button';
    this.#button.append(markSvg(), this.#t('button'));
    this.#button.addEventListener('click', () => this.#start());
    this.#problem = el('p', 'problem');
    this.#problem.setAttribute('role', 'alert');
    this.#problem.hidden = true;
    root.append(this.#button, this.#problem);
  }

  disconnectedCallback() {
    this.#stop();
  }

  #t(key) {
    const lang = (this.lang || document.documentElement.lang || navigator.language || 'en').slice(0, 2);
    return (STRINGS[lang] ?? STRINGS.en)[key];
  }

  #say(key) {
    this.#problem.textContent = key ? this.#t(key) : '';
    this.#problem.hidden = !key;
  }

  async #start() {
    this.#say(null);
    this.#button.disabled = true;
    try {
      const { ok, json } = await post(this.getAttribute('start'), {});
      if (!ok) throw new Error('start refused');
      if (!json.app_link?.startsWith('revoked://signin?') || !json.wait) throw new Error('start answered badly');
      this.#wait = json.wait;
      this.#show(json.app_link, json.check_code);
    } catch (err) {
      console.error('revoked-sign-in:', err);
      this.#say('failed');
    } finally {
      this.#button.disabled = false;
    }
  }

  #show(appLink, checkCode) {
    const phone = onPhone();
    const dialog = el('dialog', phone ? 'phone' : '');
    dialog.setAttribute('aria-labelledby', 'revoked-title');
    const title = el('h2', '', this.#t('button'));
    title.id = 'revoked-title';

    const here = el('button', 'here', this.#t('open'));
    here.type = 'button';
    // Stays on this page, which keeps waiting for the answer.
    here.addEventListener('click', () => location.assign(appLink));

    const check = el('p', 'check', this.#t('check'));
    check.append(el('code', '', checkCode));

    const status = el('p', 'quiet status', this.#t('waiting'));
    status.setAttribute('role', 'status');

    const close = el('button', 'close', this.#t('close'));
    close.type = 'button';
    close.addEventListener('click', () => dialog.close());

    const panel = el('div', 'panel');
    panel.append(
      el('p', 'scan', this.#t(phone ? 'scanElsewhere' : 'scan')),
      qrSvg(appLink, this.#t('qr')),
      check,
      here,
      status,
      el('p', 'quiet needs', this.#t('needsApp')),
      close,
    );
    dialog.append(title, panel);
    dialog.addEventListener('close', () => {
      this.#stop();
      dialog.remove();
    });
    this.shadowRoot.append(dialog);
    this.#dialog = dialog;
    dialog.showModal();
    this.#timer = setInterval(() => this.#ask(), ASK_EVERY_MS);
    // A phone browser sleeps while the app is open, so ask the moment it's back.
    document.addEventListener('visibilitychange', this.#onVisible);
  }

  #onVisible = () => {
    if (document.visibilityState === 'visible') this.#ask();
  };

  #stop() {
    clearInterval(this.#timer);
    document.removeEventListener('visibilitychange', this.#onVisible);
  }

  async #ask() {
    if (this.#asking) return;
    this.#asking = true;
    try {
      const { status, ok, json } = await post(this.getAttribute('wait'), { wait: this.#wait });
      if (status === 401 || status === 404 || status === 410) return this.#end('expired');
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

customElements.define('revoked-sign-in', RevokedSignIn);
