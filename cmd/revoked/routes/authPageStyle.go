package routes

// authPageStyle is the look of the pages a passkey ceremony runs on: the
// sign-in page and the flow pages (BROWSER.md §4). One stylesheet, so a person
// moving between them sees one product.
const authPageStyle = `* { box-sizing: border-box; margin: 0; padding: 0; }
body {
background: var(--bg);
color: var(--fg);
font-family: var(--font-sans);
font-size: 16px;
line-height: 1.45;
min-height: 100vh;
-webkit-font-smoothing: antialiased;
-webkit-tap-highlight-color: transparent;
}
svg { display: block; flex: none; }
button { font: inherit; }

header {
position: sticky;
top: 0;
z-index: 10;
background: color-mix(in srgb, var(--bg) 85%, transparent);
-webkit-backdrop-filter: blur(12px);
backdrop-filter: blur(12px);
border-bottom: 1px solid var(--border);
}
.nav {
max-width: 640px;
margin: 0 auto;
padding: 10px 16px;
display: flex;
align-items: center;
justify-content: space-between;
}
.brand { display: flex; align-items: center; gap: 8px; font-weight: 700; font-size: 16px; letter-spacing: -0.02em; color: var(--fg); }
.logo { width: 24px; height: 24px; border-radius: var(--radius-md); }
.logo-dark { display: none; }
html[data-theme="dark"] .logo-light { display: none; }
html[data-theme="dark"] .logo-dark { display: block; }
@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) .logo-light { display: none; }
html:not([data-theme="light"]) .logo-dark { display: block; }
}
.tools { display: flex; gap: 8px; }
.theme, .lang {
min-width: 38px; height: 38px; border-radius: var(--radius-md); border: 1px solid var(--control);
background: var(--bg); color: var(--fg); cursor: pointer;
display: inline-flex; align-items: center; justify-content: center;
}
.lang { padding: 0 10px; font-size: 13px; font-weight: 650; letter-spacing: .04em; }

.steps { display: flex; flex-direction: column; gap: 8px; }
.steps-t { display: flex; align-items: center; gap: 8px; font-size: 13px; font-weight: 500; color: var(--fg-muted); }
.steps-t img { width: 18px; height: 18px; border-radius: var(--radius-md); }
.steps ol { list-style: none; display: grid; grid-auto-flow: column; grid-auto-columns: 1fr; gap: 6px; }
.steps li { height: 4px; border-radius: var(--radius-pill); background: var(--border); transition: background .3s; }
.steps li.on { background: var(--primary); }

main {
max-width: 440px;
margin: 0 auto;
padding: 18px 16px calc(40px + env(safe-area-inset-bottom));
display: flex;
flex-direction: column;
gap: 16px;
}
@media (min-width: 600px) { main { padding-top: 10vh; gap: 18px; } }

.hero { display: flex; flex-direction: column; gap: 14px; }
.hero-tile {
width: 48px; height: 48px; border-radius: var(--radius-lg); flex: none;
display: flex; align-items: center; justify-content: center;
background: var(--surface-subtle); color: var(--fg);
transition: background .3s, color .3s;
}
.hero-tile.ok { background: var(--ok-subtle); color: var(--ok); }
.hero-tile.warn { background: var(--warn-subtle); color: var(--warn); }
.hero-tile.bad { background: var(--bad-subtle); color: var(--bad); }
.hero-tile:empty { display: none; }
.hero h1 .status-ic { display: inline-block; vertical-align: -2px; margin-right: 8px; }
.status-ic.ok { color: var(--ok); }
.status-ic.warn { color: var(--warn); }
.status-ic.bad { color: var(--bad); }
.hero-tile svg { animation: pop .3s var(--ease); }
.hero h1 { font-size: 24px; font-weight: 650; line-height: 1.2; letter-spacing: -0.03em; overflow-wrap: anywhere; }
@media (min-width: 600px) { .hero h1 { font-size: 26px; } }
.lead { color: var(--fg-muted); font-size: 15px; line-height: 1.45; margin-top: 6px; overflow-wrap: anywhere; }
.lead:empty { display: none; }

.card {
display: flex;
flex-direction: column;
gap: 12px;
overflow: visible;
animation: rise .4s var(--ease) both;
}

.callout {
display: flex; gap: 10px; align-items: flex-start;
padding: 12px 14px; border-radius: var(--radius-md);
background: var(--bad-subtle); color: var(--bad);
font-size: 14px; line-height: 1.45;
}

.field { display: flex; flex-direction: column; gap: 6px; font-size: 13px; font-weight: 600; color: var(--fg-muted); }
input {
width: 100%; height: 44px; padding: 0 12px;
font: inherit; font-size: 16px; font-weight: 400; color: var(--fg);
background: var(--field); border: 1px solid var(--control); border-radius: var(--radius-md);
transition: border-color .15s, box-shadow .15s;
}
input::placeholder { color: var(--fg-muted); opacity: .7; }
input:focus { outline: none; border-color: var(--fg); box-shadow: 0 0 0 3px color-mix(in srgb, var(--fg) 15%, transparent); }
#code { font-size: 20px; letter-spacing: .4em; font-variant-numeric: tabular-nums; text-align: center; }
.quiet:disabled { cursor: default; opacity: .6; }

/* One control height across the pages: 44px, the smallest comfortable touch
   target, so a field and the button under it read as one unit. */
.big, .quiet {
width: 100%; min-height: 44px; border-radius: var(--radius-md);
font-size: 15px; font-weight: 600;
display: flex; align-items: center; justify-content: center; gap: 8px;
padding: 10px 16px; text-align: center;
cursor: pointer; text-decoration: none;
transition: transform .12s var(--ease), filter .15s, background .15s;
}
.big { border: 0; background: var(--primary); color: var(--primary-fg); }
.big:hover { filter: brightness(1.06); }
.quiet { border: 1px solid var(--control); background: transparent; color: var(--fg); }
.quiet:hover { background: var(--surface-subtle); }
.big:active, .quiet:active { transform: scale(.985); }
.big:disabled { cursor: progress; opacity: .75; }
.big:focus-visible, .quiet:focus-visible, .theme:focus-visible, .lang:focus-visible { outline: 2px solid var(--primary); outline-offset: 2px; }
.spin { width: 16px; height: 16px; border-radius: 50%; border: 2px solid currentColor; border-right-color: transparent; animation: spin .7s linear infinite; display: none; flex: none; }
.big.loading .spin { display: block; }
.big.loading .big-ic { display: none; }
.big-logo { width: 20px; height: 20px; }
.big-ic svg { width: 18px; height: 18px; }

.hint {
display: flex; gap: 10px; align-items: flex-start;
padding: 10px 12px; border-radius: var(--radius-md);
background: var(--surface-subtle); color: var(--fg);
font-size: 13px; line-height: 1.45;
}
.hint svg { margin-top: 1px; color: var(--fg-muted); }
.fine { text-align: center; color: var(--fg-muted); font-size: 13px; line-height: 1.45; }
/* The way to the other mode, while creating an account: a quiet text link
   for a wrong tap, not a second choice beside the step being taken. */
.quiet.link { min-height: 44px; border: 0; font-size: 14px; font-weight: 500; color: var(--fg-muted); text-decoration: underline; text-underline-offset: 3px; }
.quiet.link:hover { background: transparent; color: var(--fg); }
.fine:empty { display: none; }
[hidden] { display: none !important; }
.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }

@keyframes spin { to { transform: rotate(360deg); } }
@keyframes rise { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: none; } }
@keyframes pop { 0% { transform: scale(.5); } 70% { transform: scale(1.15); } 100% { transform: scale(1); } }
@media (prefers-reduced-motion: reduce) {
*, *::before, *::after { animation: none !important; transition: none !important; }
}
`
