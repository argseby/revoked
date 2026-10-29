import React from 'react';
import {useCurrentFrame} from 'remotion';
import {LockKeyhole, Server} from 'lucide-react';
import {C, MONO, prog} from '../theme';
import {Card, Row, type RowKind, SectionHead} from './ui';

export type RowSpec = {
  k: string;
  v: React.ReactNode;
  kind?: RowKind;
  flash?: number;
  dim?: number;
  badge?: React.ReactNode;
  badgeP?: number;
};
export type SectionSpec = {name: string; rows: RowSpec[]; ring?: number; right?: React.ReactNode};

const HEADER = 78;
const HEAD = 42;
const GAP = 14;
const PAD = 10;
const rowH = (compact: boolean) => (compact ? 50 : 58);

/** Where section `i` sits on screen, for pointing arrows at it. */
export const sectionBox = (x: number, y: number, w: number, sections: SectionSpec[], i: number, compact = false) => {
  let top = y + HEADER + PAD;
  for (let j = 0; j < i; j++) top += HEAD + sections[j].rows.length * rowH(compact) + GAP;
  const h = HEAD + sections[i].rows.length * rowH(compact);
  return {x, y: top, w, h, cy: top + h / 2, left: x, right: x + w};
};

export const vaultHeight = (sections: SectionSpec[], compact = false) =>
  HEADER + PAD * 2 + sections.reduce((a, s) => a + HEAD + s.rows.length * rowH(compact), 0) + GAP * (sections.length - 1);

export const VaultCard: React.FC<{
  x: number;
  y: number;
  w: number;
  at?: number;
  stagger?: number;
  sections: SectionSpec[];
  compact?: boolean;
  title?: string;
}> = ({x, y, w, at = 0, stagger = 0, sections, compact = false, title = 'Mia’s vault'}) => {
  const f = useCurrentFrame();
  let n = 0;
  return (
    <>
      <Card x={x} y={y} w={w} h={vaultHeight(sections, compact)} at={at}>
        <div
          style={{
            height: HEADER,
            display: 'flex',
            alignItems: 'center',
            gap: 14,
            padding: '0 24px',
            borderBottom: `2px solid ${C.divider}`,
          }}
        >
          <LockKeyhole size={30} color={C.brand} strokeWidth={2.2} />
          <span style={{fontSize: 30, fontWeight: 740, letterSpacing: '-0.02em', flex: 1}}>{title}</span>
          <span
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 8,
              fontFamily: MONO,
              fontSize: 19,
              color: C.muted,
              background: C.sunken,
              borderRadius: 999,
              padding: '4px 14px',
            }}
          >
            <Server size={18} strokeWidth={2.2} /> home.example
          </span>
        </div>
        <div style={{padding: `${PAD}px 6px`}}>
          {sections.map((s, i) => (
            <div key={s.name} style={{marginTop: i === 0 ? 0 : GAP}}>
              <SectionHead name={s.name} highlight={s.ring} right={s.right} />
              {s.rows.map((r) => {
                const p = stagger ? prog(f, at + 10 + n++ * stagger, 16) : 1;
                return (
                  <div key={r.k} style={{opacity: p, transform: `translateX(${(1 - p) * 20}px)`}}>
                    <Row {...r} compact={compact} />
                  </div>
                );
              })}
            </div>
          ))}
        </div>
      </Card>
      {sections.map((s, i) => {
        if (!s.ring) return null;
        const b = sectionBox(x, y, w, sections, i, compact);
        return (
          <div
            key={s.name}
            style={{
              position: 'absolute',
              left: b.x + 4,
              top: b.y - 6,
              width: b.w - 8,
              height: b.h + 10,
              borderRadius: 14,
              border: `3px solid ${C.brand}`,
              opacity: s.ring,
            }}
          />
        );
      })}
    </>
  );
};

export const RENTAL = (payslip: React.ReactNode = 'payslip-sept.pdf', flash = 0): SectionSpec => ({
  name: 'Rental',
  rows: [
    {k: 'full_name', v: 'Mia Berger'},
    {k: 'phone', v: '+49 151 2345 6789'},
    {k: 'payslip', v: payslip, kind: 'file', flash},
  ],
});

export const TAX: SectionSpec = {
  name: 'Tax & bank',
  rows: [
    {k: 'tax_id', v: '12 345 678 901'},
    {k: 'iban', v: 'DE89 •••• •••• 4821', kind: 'hidden'},
  ],
};
