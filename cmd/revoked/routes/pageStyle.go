package routes

// pageTokens is the app's design in CSS — the palette of
// app/lib/core/design/app_colors.dart, the square corners of radius.dart and
// the type scale of text_styles.dart — so the trip through the browser does
// not look like leaving the app.
//
// Every page the server renders splices this in ahead of its own rules and
// then names colours only through these variables, so the palette is kept in
// one place. The names are the union of what the pages ask for: a page that
// has no cards still gets --card, which costs nothing.
//
// The dark values are written twice on purpose: once for a theme the person
// chose on this origin (`data-theme`), once for the one their system asks
// for. A page without a theme toggle never sets the attribute and so only
// ever takes the second.
const pageTokens = `
:root {
--font-sans: system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
--font-mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
--ease: cubic-bezier(.2, .8, .2, 1);
}

:root,
html[data-theme="light"] {
color-scheme: light;
--bg: #ffffff;
--card: #fafafa;
--surface: #fafafa;
--field: #ffffff;
--surface-subtle: #f5f5f5;
--surface-hover: #f2f2f2;
--subtle: #f5f5f5;
--border: #e5e5e5;
--border-strong: #858585;
--control: #858585;
--fg: #0a0a0a;
--fg-muted: #525252;
--primary: #0a0a0a;
--primary-fg: #ffffff;
--primary-subtle: #f2f2f2;
--ok: #1d6b4c;
--ok-subtle: #d7f0e3;
--bad: #b42318;
--bad-subtle: #fce4e1;
--warn: #7a5600;
--warn-subtle: #ffefc9;
/* A web address carries the same ink tile as an address or a name: colour is
   kept for what a value's state is, never for what kind it is. */
--violet: #0a0a0a;
--violet-subtle: #f2f2f2;
/* The app is flat: a card is told apart by its border, not by a shadow. */
--shadow: none;
}

html[data-theme="dark"] {
color-scheme: dark;
--bg: #171717;
--card: #1f1f1f;
--surface: #1f1f1f;
--field: #171717;
--surface-subtle: #262626;
--surface-hover: #2a2a2a;
--subtle: #262626;
--border: #333333;
--border-strong: #808080;
--control: #808080;
--fg: #ededed;
--fg-muted: #adadad;
--primary: #ededed;
--primary-fg: #171717;
--primary-subtle: #333333;
--ok: #8ed5b1;
--ok-subtle: #12352a;
--bad: #ff6259;
--bad-subtle: #3f1512;
--warn: #f2c24b;
--warn-subtle: #3d2e05;
--violet: #ededed;
--violet-subtle: #333333;
--shadow: none;
}

@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) {
color-scheme: dark;
--bg: #171717;
--card: #1f1f1f;
--surface: #1f1f1f;
--field: #171717;
--surface-subtle: #262626;
--surface-hover: #2a2a2a;
--subtle: #262626;
--border: #333333;
--border-strong: #808080;
--control: #808080;
--fg: #ededed;
--fg-muted: #adadad;
--primary: #ededed;
--primary-fg: #171717;
--primary-subtle: #333333;
--ok: #8ed5b1;
--ok-subtle: #12352a;
--bad: #ff6259;
--bad-subtle: #3f1512;
--warn: #f2c24b;
--warn-subtle: #3d2e05;
--violet: #ededed;
--violet-subtle: #333333;
--shadow: none;
}
}
`
