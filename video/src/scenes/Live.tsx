import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {Arrow, Packet, Tag} from '../components/flow';
import {LinkChip} from '../components/chips';
import {LinkPanel} from '../components/panel';
import {Caption, Person, Strong} from '../components/ui';
import {RENTAL, VaultCard} from '../components/vault';
import {C, prog} from '../theme';
import {CHIP, LL, PANEL, SLUG, V, panelAnchor, rentalAnchor, sharedSections} from './Share';

const Swap: React.FC<{p: number; from: string; to: string}> = ({p, from, to}) => (
  <span style={{position: 'relative', display: 'inline-block'}}>
    <span style={{opacity: 1 - p, transform: `translateY(${-p * 14}px)`, display: 'inline-block'}}>{from}</span>
    <span style={{position: 'absolute', left: 0, top: 0, opacity: p, transform: `translateY(${(1 - p) * 14}px)`}}>{to}</span>
  </span>
);

export const Live: React.FC = () => {
  const f = useCurrentFrame();
  const a = rentalAnchor();
  const vaultSwap = prog(f, 50, 16);
  const vaultFlash = prog(f, 44, 10) * (1 - prog(f, 110, 30));
  const panelSwap = prog(f, 168, 16);
  const panelFlash = prog(f, 160, 10) * (1 - prog(f, 230, 30));
  const payslip = <Swap p={vaultSwap} from="payslip-sept.pdf" to="payslip-oct.pdf" />;
  const rows = RENTAL().rows.map((r) =>
    r.kind === 'file' ? {...r, v: <Swap p={panelSwap} from="payslip-sept.pdf" to="payslip-oct.pdf" />, flash: panelFlash} : r,
  );
  return (
    <AbsoluteFill>
      <Caption
        kicker="Living grants"
        title="Every read gets the current value."
        beats={[
          {at: 0, text: 'Mia uploads October’s payslip — in the vault, nowhere else.'},
          {
            at: 150,
            text: (
              <>
                The landlord’s next read shows it. <Strong>No resending, no republishing.</Strong>
              </>
            ),
          },
        ]}
      />
      <VaultCard x={V.x} y={V.y} w={V.w} compact sections={sharedSections(payslip, vaultFlash)} />
      <Person kind="landlord" x={LL.x} y={LL.y} size={104} role={false} />
      <div style={{position: 'absolute', left: CHIP.x, top: CHIP.y, transform: 'translate(-50%, -50%)'}}>
        <LinkChip slug={SLUG} />
      </div>
      <LinkPanel x={PANEL.x} y={PANEL.y} w={PANEL.w} at={-30} title="Rental · shared by Mia" rows={rows} />
      <Arrow id="read" from={a} to={panelAnchor} bend={40} at={-40} live />
      <Packet from={a} to={panelAnchor} bend={40} at={110} dur={50} hold={false}>
        <div
          style={{
            width: 26,
            height: 26,
            borderRadius: '50%',
            background: C.brand,
            boxShadow: `0 0 0 10px rgba(61,53,181,0.18), 0 0 30px rgba(61,53,181,0.5)`,
          }}
        />
      </Packet>
      <Tag x={(a.x + panelAnchor.x) / 2} y={(a.y + panelAnchor.y) / 2 + 84} at={-20}>
        reads the live value
      </Tag>
      <Tag x={960} y={960} at={240} color={C.onBrandTint} bg={C.brandTint}>
        One value, in one place. Every link follows it.
      </Tag>
    </AbsoluteFill>
  );
};
