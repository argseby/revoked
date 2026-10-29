import React from 'react';
import {useCurrentFrame} from 'remotion';
import {C, FONT, easeInOut, prog} from '../theme';
import {curve, type Pt} from './geometry';

const svgStyle: React.CSSProperties = {
  position: 'absolute',
  left: 0,
  top: 0,
  width: 1920,
  height: 1080,
  overflow: 'visible',
  pointerEvents: 'none',
};

/**
 * A connection between two points. Solid lines are drawn in once; `live` lines
 * are dotted and keep moving toward `to`, which is how the video shows a link
 * reading the current value rather than holding a copy.
 */
export const Arrow: React.FC<{
  id: string;
  from: Pt;
  to: Pt;
  bend?: number;
  at: number;
  dur?: number;
  color?: string;
  width?: number;
  live?: boolean;
  head?: boolean;
  fade?: number;
  broken?: number;
}> = ({id, from, to, bend = 0, at, dur = 24, color = C.brand, width = 4, live = false, head = true, fade = 0, broken = 0}) => {
  const f = useCurrentFrame();
  const p = prog(f, at, dur, easeInOut);
  if (p <= 0) return null;
  const c = curve(from, to, bend);
  const tip = c.at(1);
  const ang = c.angle(1);
  const stroke = broken > 0 ? mixColor(color, C.border, broken) : color;
  const opacity = 1 - fade;
  return (
    <svg style={svgStyle} viewBox="0 0 1920 1080">
      <defs>
        <mask id={`m-${id}`} maskUnits="userSpaceOnUse" x={-200} y={-200} width={2320} height={1480}>
          <path
            d={c.d}
            fill="none"
            stroke="white"
            strokeWidth={width + 16}
            pathLength={1}
            strokeDasharray="1 1"
            strokeDashoffset={1 - p}
          />
          {broken > 0 && (
            <circle cx={c.at(0.5).x} cy={c.at(0.5).y} r={40 * broken} fill="black" />
          )}
        </mask>
      </defs>
      <g mask={`url(#m-${id})`} opacity={opacity}>
        <path
          d={c.d}
          fill="none"
          stroke={stroke}
          strokeWidth={width}
          strokeLinecap="round"
          strokeDasharray={live ? `0.1 ${width * 4}` : undefined}
          strokeDashoffset={live && broken === 0 ? -f * 1.6 : 0}
          style={live ? {strokeWidth: width * 1.6} : undefined}
        />
      </g>
      {head && (
        <g
          transform={`translate(${tip.x} ${tip.y}) rotate(${ang})`}
          opacity={prog(f, at + dur * 0.8, 8) * opacity * (1 - broken)}
        >
          <path d="M -18 -10 L 2 0 L -18 10 Z" fill={stroke} strokeLinejoin="round" />
        </g>
      )}
    </svg>
  );
};

function mixColor(a: string, b: string, t: number) {
  const pa = [1, 3, 5].map((i) => parseInt(a.slice(i, i + 2), 16));
  const pb = [1, 3, 5].map((i) => parseInt(b.slice(i, i + 2), 16));
  return `rgb(${pa.map((v, i) => Math.round(v + (pb[i] - v) * t)).join(',')})`;
}

/** Something travelling along a curve: a link chip, a form, a signature. */
export const Packet: React.FC<{
  from: Pt;
  to: Pt;
  bend?: number;
  at: number;
  dur?: number;
  hold?: boolean;
  children: React.ReactNode;
}> = ({from, to, bend = 0, at, dur = 40, hold = true, children}) => {
  const f = useCurrentFrame();
  const t = prog(f, at, dur, easeInOut);
  const shown = prog(f, at - 6, 8);
  const gone = hold ? 0 : prog(f, at + dur, 10);
  if (shown <= 0) return null;
  const pt = curve(from, to, bend).at(t);
  return (
    <div
      style={{
        position: 'absolute',
        left: pt.x,
        top: pt.y,
        transform: 'translate(-50%, -50%)',
        opacity: shown * (1 - gone),
      }}
    >
      {children}
    </div>
  );
};

/** A small label sitting on a connection. */
export const Tag: React.FC<{
  x: number;
  y: number;
  at: number;
  color?: string;
  bg?: string;
  out?: number;
  children: React.ReactNode;
}> = ({x, y, at, color = C.brand, bg = C.paper, out, children}) => {
  const f = useCurrentFrame();
  const p = prog(f, at, 16);
  const o = out === undefined ? 1 : 1 - prog(f, out, 12);
  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        transform: `translate(-50%, -50%) scale(${0.9 + 0.1 * p})`,
        opacity: p * o,
        fontFamily: FONT,
        fontSize: 22,
        fontWeight: 680,
        color,
        background: bg,
        padding: '4px 14px',
        borderRadius: 999,
        whiteSpace: 'nowrap',
        display: 'flex',
        alignItems: 'center',
        gap: 8,
      }}
    >
      {children}
    </div>
  );
};
