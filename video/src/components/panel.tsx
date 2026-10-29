import React from 'react';
import {useCurrentFrame} from 'remotion';
import {Ban, Link2, type LucideIcon} from 'lucide-react';
import {C, MONO, prog} from '../theme';
import {Card, Pill, Row, type Tone} from './ui';
import type {RowSpec} from './vault';

/** What a recipient sees when opening a link: the values it resolves right now. */
export const LinkPanel: React.FC<{
  x: number;
  y: number;
  w: number;
  at: number;
  title: string;
  rows: RowSpec[];
  fill?: number;
  status?: Tone;
  statusText?: string;
  refused?: number;
  icon?: LucideIcon;
}> = ({x, y, w, at, title, rows, fill = 0, status = 'active', statusText = 'active', refused = 0, icon: Icon = Link2}) => {
  const f = useCurrentFrame();
  const h = 70 + rows.length * 50 + 20;
  return (
    <Card x={x} y={y} w={w} h={h} at={at}>
      <div
        style={{
          height: 66,
          display: 'flex',
          alignItems: 'center',
          gap: 12,
          padding: '0 20px',
          borderBottom: `2px solid ${C.divider}`,
        }}
      >
        <Icon size={26} color={C.brand} strokeWidth={2.4} />
        <span style={{fontSize: 24, fontWeight: 720, flex: 1, letterSpacing: '-0.01em'}}>{title}</span>
        <Pill tone={status} dot size={18}>
          {statusText}
        </Pill>
      </div>
      <div style={{padding: '10px 4px', position: 'relative'}}>
        {rows.map((r, i) => {
          const p = prog(f, fill + i * 6, 14);
          return (
            <div key={r.k} style={{opacity: fill ? p * (1 - refused) : 1 - refused, filter: refused ? `blur(${refused * 6}px)` : undefined}}>
              <Row {...r} compact />
            </div>
          );
        })}
        {refused > 0 && (
          <div
            style={{
              position: 'absolute',
              inset: 10,
              borderRadius: 12,
              background: C.dangerTint,
              color: C.danger,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 6,
              opacity: refused,
              transform: `scale(${0.96 + 0.04 * refused})`,
            }}
          >
            <div style={{display: 'flex', alignItems: 'center', gap: 12, fontSize: 28, fontWeight: 740}}>
              <Ban size={30} strokeWidth={2.4} /> This link was revoked
            </div>
            <div style={{fontFamily: MONO, fontSize: 19, opacity: 0.85}}>410 · nothing resolves</div>
          </div>
        )}
      </div>
    </Card>
  );
};
