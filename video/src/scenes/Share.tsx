import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {Clock, Eye, KeyRound, Lock} from 'lucide-react';
import {Arrow, Packet, Tag} from '../components/flow';
import {LinkChip} from '../components/chips';
import {LinkPanel} from '../components/panel';
import {Caption, Person, Pill, Strong} from '../components/ui';
import {RENTAL, TAX, VaultCard, sectionBox} from '../components/vault';
import {C, FONT, prog} from '../theme';

export const V = {x: 120, y: 390, w: 660};
export const LL = {x: 1660, y: 430};
export const CHIP = {x: 1330, y: 430};
export const PANEL = {x: 1220, y: 580, w: 600};
export const SLUG = '/s/k7Qx9mPz2w…';

export const sharedSections = (payslip?: React.ReactNode, flash = 0, ring = 0) => [
  {...RENTAL(payslip, flash), ring},
  TAX,
];

export const rentalAnchor = () => {
  const b = sectionBox(V.x, V.y, V.w, sharedSections(), 0, true);
  return {x: b.right + 8, y: b.cy};
};

export const panelAnchor = {x: PANEL.x - 10, y: PANEL.y + 150};

export const Share: React.FC = () => {
  const f = useCurrentFrame();
  const a = rentalAnchor();
  return (
    <AbsoluteFill>
      <Caption
        kicker="2 · Shares"
        title="A share is a link — not a copy."
        beats={[
          {
            at: 0,
            text: (
              <>
                Mia shares the <Strong>Rental</Strong> section. What travels to the landlord is only a link.
              </>
            ),
          },
          {
            at: 175,
            text: (
              <>
                When the landlord opens it, the link <Strong color={C.brand}>reads from Mia’s vault</Strong> — right
                then.
              </>
            ),
          },
          {
            at: 320,
            text: (
              <>
                The link itself is the key: long and random. Add a password, a view limit or an expiry on top.
              </>
            ),
          },
        ]}
      />
      <VaultCard x={V.x} y={V.y} w={V.w} at={0} compact sections={sharedSections(undefined, 0, prog(f, 14, 14))} />
      <Person kind="landlord" x={LL.x} y={LL.y} at={6} size={104} role={false} />
      <Arrow id="link" from={a} to={{x: CHIP.x - 190, y: CHIP.y}} bend={-50} at={50} dur={30} fade={prog(f, 175, 20) * 0.75} />
      <Packet from={a} to={CHIP} bend={-50} at={54} dur={52}>
        <LinkChip slug={SLUG} />
      </Packet>
      <Tag x={(a.x + CHIP.x) / 2 - 60} y={CHIP.y - 62} at={70} out={170}>
        a link travels
      </Tag>
      <LinkPanel
        x={PANEL.x}
        y={PANEL.y}
        w={PANEL.w}
        at={150}
        title="Rental · shared by Mia"
        rows={RENTAL().rows}
        fill={222}
      />
      <Arrow id="read" from={a} to={panelAnchor} bend={40} at={190} dur={30} live color={C.brand} />
      <Tag x={(a.x + panelAnchor.x) / 2} y={(a.y + panelAnchor.y) / 2 + 84} at={210}>
        reads the live value
      </Tag>
      <div
        style={{
          position: 'absolute',
          left: CHIP.x - 120,
          top: CHIP.y + 38,
          opacity: prog(f, 330, 16),
          fontFamily: FONT,
        }}
      >
        <Pill tone="brand" icon={KeyRound} size={19}>
          the slug is the key
        </Pill>
      </div>
      <div
        style={{
          position: 'absolute',
          left: PANEL.x,
          top: 930,
          display: 'flex',
          gap: 14,
        }}
      >
        {[
          {icon: Lock, t: 'password'},
          {icon: Eye, t: 'view limit'},
          {icon: Clock, t: 'expiry'},
        ].map((g, i) => (
          <div key={g.t} style={{opacity: prog(f, 350 + i * 8, 14), transform: `translateY(${(1 - prog(f, 350 + i * 8, 14)) * 10}px)`}}>
            <Pill tone="neutral" icon={g.icon} size={22}>
              {g.t}
            </Pill>
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};
