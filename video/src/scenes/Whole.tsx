import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {Award, ClipboardList, KeyRound, Link2, LockKeyhole, X, type LucideIcon} from 'lucide-react';
import {Arrow, Tag} from '../components/flow';
import {Caption, Person, Pill} from '../components/ui';
import {C, FONT, prog} from '../theme';

const MIA = {x: 760, y: 620};
const LL = {x: 290, y: 450};
const TA = {x: 290, y: 820};
const EMP = {x: 1180, y: 620};

const LEGEND: {icon: LucideIcon; name: string; text: string}[] = [
  {icon: LockKeyhole, name: 'Vault', text: 'What Mia holds — records and files, in sections.'},
  {icon: Link2, name: 'Shares', text: 'Links that read the live value. Pause or revoke any time.'},
  {icon: ClipboardList, name: 'Requests', text: 'Others ask. Mia answers with a link Mia controls.'},
  {icon: Award, name: 'Attestations', text: 'What others confirm, bound to Mia’s key.'},
];

export const Whole: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill>
      <Caption
        kicker="Putting it together"
        title="One vault. Every grant can be ended."
        beats={[{at: 0, text: 'Each arrow can be withdrawn by the side that issued it.'}]}
      />
      <Arrow id="w-ll" from={{x: MIA.x - 80, y: MIA.y - 40}} to={{x: LL.x + 80, y: LL.y + 20}} bend={20} at={30} live broken={1} color={C.brand} />
      <div style={{position: 'absolute', left: (MIA.x + LL.x) / 2 - 20, top: (MIA.y + LL.y) / 2 - 34, opacity: prog(f, 40, 12)}}>
        <div style={{width: 40, height: 40, borderRadius: '50%', background: C.danger, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
          <X size={26} color={C.white} strokeWidth={3} />
        </div>
      </div>
      <Tag x={(MIA.x + LL.x) / 2} y={(MIA.y + LL.y) / 2 + 30} at={46} color={C.danger} bg={C.dangerTint}>
        share · revoked
      </Tag>
      <Arrow id="w-ta" from={{x: MIA.x - 80, y: MIA.y + 40}} to={{x: TA.x + 80, y: TA.y - 20}} bend={-20} at={50} live />
      <Tag x={(MIA.x + TA.x) / 2 + 20} y={(MIA.y + TA.y) / 2 + 30} at={64}>
        share · Tax &amp; bank
      </Tag>
      <Arrow id="w-ans" from={{x: MIA.x + 80, y: MIA.y - 30}} to={{x: EMP.x - 80, y: EMP.y - 30}} bend={-70} at={70} live />
      <Tag x={(MIA.x + EMP.x) / 2} y={MIA.y - 110} at={84}>
        answer · link in Mia’s workspace
      </Tag>
      <Arrow id="w-att" from={{x: EMP.x - 80, y: EMP.y + 30}} to={{x: MIA.x + 80, y: MIA.y + 30}} bend={-70} at={90} color={C.success} />
      <Tag x={(MIA.x + EMP.x) / 2} y={MIA.y + 110} at={104} color={C.success} bg={C.successTint}>
        <Award size={20} /> attestation
      </Tag>

      <Person kind="landlord" x={LL.x} y={LL.y} at={10} size={100} role={false} dim={0.6} />
      <Person kind="advisor" x={TA.x} y={TA.y} at={14} size={100} role={false} />
      <Person kind="employer" x={EMP.x} y={EMP.y} at={18} size={100} role={false} />
      <Person kind="mia" x={MIA.x} y={MIA.y} at={4} size={140} role={false} label="none" />
      <div style={{position: 'absolute', left: MIA.x - 150, top: MIA.y + 90, width: 300, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, opacity: prog(f, 20, 16)}}>
        <div style={{fontFamily: FONT, fontSize: 30, fontWeight: 740, color: C.ink}}>Mia</div>
      </div>
      <div style={{position: 'absolute', left: MIA.x - 200, top: MIA.y + 200, width: 400, display: 'flex', justifyContent: 'center', gap: 10, opacity: prog(f, 26, 16)}}>
        <Pill tone="brand" icon={LockKeyhole} size={19}>
          vault
        </Pill>
        <Pill tone="brand" icon={KeyRound} size={19}>
          key on device
        </Pill>
      </div>

      <div style={{position: 'absolute', left: 1380, top: 380, width: 470, display: 'flex', flexDirection: 'column', gap: 26, fontFamily: FONT}}>
        {LEGEND.map((l, i) => {
          const p = prog(f, 130 + i * 30, 18);
          return (
            <div key={l.name} style={{display: 'flex', gap: 18, opacity: p, transform: `translateX(${(1 - p) * 20}px)`}}>
              <div style={{width: 56, height: 56, borderRadius: 16, background: C.brandTint, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0}}>
                <l.icon size={28} color={C.brand} strokeWidth={2.2} />
              </div>
              <div>
                <div style={{fontSize: 28, fontWeight: 740, letterSpacing: '-0.02em', color: C.ink}}>{l.name}</div>
                <div style={{fontSize: 22, color: C.muted, lineHeight: 1.35, marginTop: 2}}>{l.text}</div>
              </div>
            </div>
          );
        })}
      </div>
      <div style={{position: 'absolute', left: 0, width: 1920, top: 1004, textAlign: 'center', fontFamily: FONT, fontSize: 24, color: C.muted, opacity: prog(f, 280, 20)}}>
        Viewing a share needs only the link · Answering a request needs an account · Private keys never leave the device
      </div>
    </AbsoluteFill>
  );
};
