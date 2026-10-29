import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {Arrow} from '../components/flow';
import {Caption, Code, Person, Ring, Strong} from '../components/ui';
import {RENTAL, TAX, VaultCard, sectionBox} from '../components/vault';
import {C, FONT, prog} from '../theme';

const V = {x: 680, y: 400, w: 960};

export const VaultScene: React.FC = () => {
  const f = useCurrentFrame();
  const badge = prog(f, 120, 16);
  const rental = RENTAL();
  rental.rows = rental.rows.map((r) => ({...r, badge: r.kind === 'file' ? 'file' : 'text', badgeP: badge}));
  const tax = {...TAX, rows: TAX.rows.map((r) => ({...r, badge: r.kind === 'hidden' ? 'hidden' : 'text', badgeP: badge}))};
  const sections = [
    {...rental, ring: prog(f, 200, 14) * (1 - prog(f, 250, 12))},
    {...tax, ring: prog(f, 220, 14) * (1 - prog(f, 270, 12))},
  ];
  const r0 = sectionBox(V.x, V.y, V.w, sections, 0);
  return (
    <AbsoluteFill>
      <Caption
        kicker="1 · Vault"
        title="Everything starts in Mia’s vault."
        beats={[
          {
            at: 0,
            text: (
              <>
                The vault holds <Strong>records</Strong>: a key and a value — text, a number, a file.
              </>
            ),
          },
          {
            at: 190,
            text: (
              <>
                <Strong>Sections</Strong> group records. The vault lives on Mia’s server, under its own domain.
              </>
            ),
          },
        ]}
      />
      <Person kind="mia" x={320} y={640} at={4} />
      <Arrow id="owns" from={{x: 400, y: 640}} to={{x: V.x - 24, y: r0.cy + 40}} bend={-30} at={30} dur={22} />
      <VaultCard x={V.x} y={V.y} w={V.w} at={14} stagger={9} sections={sections} />
      <Ring x={V.x + V.w - 228} y={V.y + 20} w={208} h={38} p={prog(f, 290, 14)} />
      <div style={{position: 'absolute', left: V.x, top: 920, fontSize: 24, opacity: prog(f, 140, 18), fontFamily: FONT}}>
        <span style={{color: C.muted}}>
          Keys like <Code>tax_id</Code> are how templates, requests and scripts refer to a record.
        </span>
      </div>
    </AbsoluteFill>
  );
};
