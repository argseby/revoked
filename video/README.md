# Explainer video

A 2 min 25 s animated explainer of how revoked's vault, shares, requests and
attestations fit together, following one person (Mia) and the landlord,
employer and tax advisor who need Mia's data. Built with
[Remotion](https://www.remotion.dev): every frame is a React component, so
the video is re-rendered from source, never edited by hand.

- `out/revoked-explainer.mp4` — the rendered video (1920×1080, 30 fps, H.264)
- [STORYBOARD.md](STORYBOARD.md) — the scene list, and which doc or code path
  each claim comes from
- `src/scenes/` — one file per scene; `src/Root.tsx` sets their order and length
- `src/components/` — the shared pieces: people, cards, the vault, arrows
- `src/theme.ts` — colours (the app's light palette), fonts, easing

## Rendering

Needs Node and an installed Chrome or Chromium. Remotion would otherwise
download its own headless Chrome; `remotion.config.ts` points it at
`/usr/bin/google-chrome-stable`, or whatever `REMOTION_CHROME` names.

```bash
cd video
npm install
npm run render            # → out/revoked-explainer.mp4, a few minutes
```

To iterate:

```bash
npm run studio            # live preview with a timeline, in the browser
node scripts/stills.mts /tmp/stills scene-share:120,280 scene-revoke:200
```

Each scene is also registered on its own (`scene-intro`, `scene-share`, …), so
a still or a render of one scene does not have to wait for the others.
`npm run typecheck` checks the TypeScript.

## Changing it

- Wording lives in each scene's `<Caption beats=…>`. A beat stays on screen
  until the next one starts; keep each one readable in about three seconds.
- Timing is in frames (30 per second). Scene lengths are in `SCENES` in
  `src/Root.tsx`; neighbouring scenes cross-fade over 15 frames.
- Keep claims grounded: if the product changes, check the scene against
  STORYBOARD.md's source column before re-rendering.

Fonts are Inter and Noto Sans Mono (both SIL Open Font License), copied into
`public/`. Remotion is free for individuals and companies of up to three
people; larger organisations need a [company licence](https://www.remotion.dev/license).
