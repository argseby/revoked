import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {Calculator, House, X} from 'lucide-react';
import {Arrow} from '../components/flow';
import {LinkCard} from '../components/linkcard';
import {LinkPanel} from '../components/panel';
import {Caption, Cursor, Pill, Strong} from '../components/ui';
import {RENTAL, TAX, VaultCard, sectionBox} from '../components/vault';
import {C, FONT, prog} from '../theme';

const V = {x: 90, y: 400, w: 540};
const CARD = {x: 750, w: 440};
const A_Y = 410;
const B_Y = 720;
const PX = 1310;
const PW = 520;
const CLICK = 165;

export const Revoke: React.FC = () => {
  const f = useCurrentFrame();
  const sections = [RENTAL(), TAX];
  const r = sectionBox(V.x, V.y, V.w, sections, 0, true);
  const t = sectionBox(V.x, V.y, V.w, sections, 1, true);
  const revoked = f >= CLICK + 4;
  const broken = prog(f, CLICK + 8, 16);
  const refused = prog(f, CLICK + 26, 18);
  const press = prog(f, CLICK, 5) * (1 - prog(f, CLICK + 5, 8));
  const aMid = A_Y + 88;
  const bMid = B_Y + 88;
  return (
    <AbsoluteFill>
      <Caption
        kicker="3 · Revoke"
        title="Revoke a link, and access stops."
        beats={[
          {
            at: 0,
            text: (
              <>
                Two links from one vault: the landlord’s, and the tax advisor’s to <Strong>Tax &amp; bank</Strong>.
              </>
            ),
          },
          {
            at: 150,
            text: (
              <>
                Mia revokes the landlord’s link. <Strong color={C.danger}>The very next read is refused.</Strong>
              </>
            ),
          },
          {
            at: 300,
            text: (
              <>
                Each link stands alone — the tax advisor’s keeps working.
              </>
            ),
          },
        ]}
      />
      <VaultCard x={V.x} y={V.y} w={V.w} compact sections={sections} />
      <div style={{position: 'absolute', left: CARD.x, top: A_Y - 50, fontFamily: FONT, fontSize: 20, fontWeight: 720, letterSpacing: '0.1em', color: C.muted}}>
        MIA’S LINKS
      </div>
      <Arrow id="va" from={{x: r.right + 8, y: r.cy}} to={{x: CARD.x - 12, y: aMid}} bend={0} at={6} head={false} width={3} color={C.border} />
      <Arrow id="vb" from={{x: t.right + 8, y: t.cy}} to={{x: CARD.x - 12, y: bMid}} bend={0} at={12} head={false} width={3} color={C.border} />
      <LinkCard
        x={CARD.x}
        y={A_Y}
        w={CARD.w}
        at={8}
        title="Landlord"
        sub="Rental · /s/k7Qx…"
        status={revoked ? 'revoked' : 'active'}
        statusText={revoked ? 'revoked' : 'active'}
        pressed={press}
        outline={revoked ? C.dangerTint : undefined}
      />
      <LinkCard x={CARD.x} y={B_Y} w={CARD.w} at={16} title="Tax advisor" sub="Tax & bank · /s/Rb3n…" status="active" statusText="active" />
      <Arrow id="al" from={{x: CARD.x + CARD.w + 10, y: aMid}} to={{x: PX - 12, y: aMid}} at={24} live broken={broken} color={C.brand} />
      <Arrow id="bl" from={{x: CARD.x + CARD.w + 10, y: bMid}} to={{x: PX - 12, y: bMid}} at={30} live color={C.brand} />
      {broken > 0 && (
        <div
          style={{
            position: 'absolute',
            left: (CARD.x + CARD.w + PX) / 2 - 22,
            top: aMid - 22,
            width: 44,
            height: 44,
            borderRadius: '50%',
            background: C.danger,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            transform: `scale(${broken})`,
          }}
        >
          <X size={28} color={C.white} strokeWidth={3} />
        </div>
      )}
      <LinkPanel
        x={PX}
        y={A_Y + 10}
        w={PW}
        at={20}
        icon={House}
        title="Landlord opens it"
        rows={RENTAL().rows.slice(0, 2)}
        status={revoked ? 'revoked' : 'active'}
        statusText={revoked ? '410' : 'live'}
        refused={refused}
      />
      <LinkPanel x={PX} y={B_Y + 10} w={PW} at={26} icon={Calculator} title="Tax advisor opens it" rows={TAX.rows} statusText="live" />
      <Cursor x={970} y={528} from={{x: 1120, y: 700}} at={110} click={CLICK} out={CLICK + 40} />
      <div style={{position: 'absolute', left: 0, width: 1920, top: 976, display: 'flex', justifyContent: 'center', gap: 22}}>
        <div style={{opacity: prog(f, 320, 16)}}>
          <Pill tone="paused" dot size={24}>
            Pause — refuses for now, resume any time
          </Pill>
        </div>
        <div style={{opacity: prog(f, 332, 16)}}>
          <Pill tone="revoked" dot size={24}>
            Revoke — permanent
          </Pill>
        </div>
      </div>
    </AbsoluteFill>
  );
};
