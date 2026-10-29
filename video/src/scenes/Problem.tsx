import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {Undo2, X} from 'lucide-react';
import {Arrow, Packet, Tag} from '../components/flow';
import {DocChip} from '../components/chips';
import {Caption, Person, Strong} from '../components/ui';
import {C, FONT, mix, prog} from '../theme';

const MIA = {x: 400, y: 700};
const LL = {x: 1480, y: 700};

const COPIES = [
  {x: LL.x - 300, y: 440, tilt: -10, label: 'inbox'},
  {x: LL.x - 105, y: 405, tilt: -4, label: 'downloads'},
  {x: LL.x + 90, y: 405, tilt: 4, label: 'forwarded'},
  {x: LL.x + 280, y: 440, tilt: 10, label: 'printed'},
];

export const Problem: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill>
      <Caption
        kicker="The usual way"
        title="Sending data means sending a copy."
        beats={[
          {at: 0, text: 'Mia emails a payslip to a landlord.'},
          {at: 100, text: 'Copies pile up — in the inbox, in downloads, forwarded on.'},
          {
            at: 180,
            text: (
              <>
                Once a copy is out, it <Strong>can’t be updated or taken back.</Strong>
              </>
            ),
          },
        ]}
      />
      <Person kind="mia" x={MIA.x} y={MIA.y} at={6} />
      <Person kind="landlord" x={LL.x} y={LL.y} at={12} />
      <Arrow id="send" from={{x: MIA.x + 90, y: MIA.y - 20}} to={{x: LL.x - 100, y: LL.y - 20}} bend={-60} at={30} dur={30} color={C.border} />
      <Packet from={{x: MIA.x + 90, y: MIA.y - 20}} to={{x: LL.x - 30, y: LL.y - 60}} bend={-60} at={34} dur={46} hold={false}>
        <DocChip name="payslip.pdf" sub="September" />
      </Packet>
      {COPIES.map((c, i) => {
        const p = prog(f, 96 + i * 10, 22);
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: mix(LL.x, c.x, p) - 75,
              top: mix(LL.y - 100, c.y, p) - 95,
              opacity: p,
              transform: `scale(${mix(0.7, 0.82, p)})`,
            }}
          >
            <DocChip name="payslip.pdf" sub={c.label} tilt={c.tilt * p} />
          </div>
        );
      })}
      <Arrow id="recall" from={{x: LL.x - 150, y: LL.y + 40}} to={{x: MIA.x + 150, y: MIA.y + 40}} bend={-50} at={190} dur={26} color={C.danger} live />
      <Tag x={(LL.x + MIA.x) / 2} y={LL.y + 110} at={205} color={C.danger} bg={C.dangerTint}>
        <Undo2 size={22} strokeWidth={2.4} /> take it back?
        <X size={24} strokeWidth={2.8} />
      </Tag>
      <div
        style={{
          position: 'absolute',
          left: 0,
          width: 1920,
          top: 950,
          textAlign: 'center',
          fontFamily: FONT,
          fontSize: 28,
          color: C.muted,
          opacity: prog(f, 225, 20),
        }}
      >
        revoked replaces the copy with a <span style={{color: C.brand, fontWeight: 700}}>link to the current value</span>.
      </div>
    </AbsoluteFill>
  );
};
