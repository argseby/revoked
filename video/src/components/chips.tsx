import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {FileText, Link2} from 'lucide-react';
import {C, FONT, MONO, mix, prog} from '../theme';

export const LinkChip: React.FC<{slug: string; label?: string; scale?: number; muted?: boolean}> = ({
  slug,
  label,
  scale = 1,
  muted = false,
}) => (
  <div
    style={{
      display: 'inline-flex',
      alignItems: 'center',
      gap: 12 * scale,
      background: muted ? C.sunken : C.brand,
      color: muted ? C.muted : C.white,
      borderRadius: 999,
      padding: `${10 * scale}px ${22 * scale}px ${10 * scale}px ${16 * scale}px`,
      boxShadow: muted ? 'none' : '0 10px 26px rgba(61,53,181,0.30)',
      fontFamily: FONT,
      whiteSpace: 'nowrap',
    }}
  >
    <Link2 size={26 * scale} strokeWidth={2.4} />
    {label && <span style={{fontSize: 22 * scale, fontWeight: 700}}>{label}</span>}
    <span style={{fontFamily: MONO, fontSize: 22 * scale, opacity: 0.92}}>{slug}</span>
  </div>
);

export const DocChip: React.FC<{name: string; sub?: string; tilt?: number}> = ({name, sub, tilt = 0}) => (
  <div
    style={{
      width: 150,
      height: 190,
      background: C.white,
      border: `2px solid ${C.divider}`,
      borderRadius: 14,
      boxShadow: '0 12px 30px rgba(22,21,31,0.12)',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 10,
      transform: `rotate(${tilt}deg)`,
      fontFamily: FONT,
    }}
  >
    <FileText size={58} color={C.danger} strokeWidth={1.7} />
    <div style={{fontSize: 19, fontWeight: 680, color: C.ink}}>{name}</div>
    {sub && <div style={{fontSize: 16, color: C.muted}}>{sub}</div>}
  </div>
);

/** Paper background with a faint dot grid and two soft brand glows. */
export const Backdrop: React.FC = () => {
  const f = useCurrentFrame();
  const drift = Math.sin(f / 90) * 30;
  return (
    <AbsoluteFill style={{background: C.paper}}>
      <AbsoluteFill
        style={{
          backgroundImage: `radial-gradient(${C.divider} 1.6px, transparent 1.6px)`,
          backgroundSize: '36px 36px',
          opacity: 0.7,
        }}
      />
      <div
        style={{
          position: 'absolute',
          right: -260 + drift,
          top: -300,
          width: 900,
          height: 900,
          borderRadius: '50%',
          background: 'radial-gradient(circle, rgba(61,53,181,0.10), rgba(61,53,181,0) 65%)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: -340,
          bottom: -380 - drift,
          width: 1000,
          height: 1000,
          borderRadius: '50%',
          background: 'radial-gradient(circle, rgba(61,53,181,0.07), rgba(61,53,181,0) 65%)',
        }}
      />
    </AbsoluteFill>
  );
};

/** The four-bar mark from docs/assets/brand, drawn in bar by bar. */
export const Mark: React.FC<{size: number; at: number; accent?: boolean}> = ({size, at, accent = true}) => {
  const f = useCurrentFrame();
  const bars = [
    {x: 100, y: 100, w: 300},
    {x: 140, y: 185.33, w: 220},
    {x: 100, y: 270.67, w: 300},
    {x: 180, y: 356, w: 140},
  ];
  return (
    <svg width={size} height={size} viewBox="0 0 500 500">
      {bars.map((b, i) => {
        const p = prog(f, at + i * 5, 20);
        return (
          <rect
            key={i}
            x={b.x}
            y={b.y}
            width={b.w * p}
            height={44}
            rx={4}
            fill={accent && i === 3 ? C.brand : C.ink}
            opacity={mix(0, 1, Math.min(1, p * 3))}
          />
        );
      })}
    </svg>
  );
};
