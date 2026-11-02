import React, {useEffect, useState} from 'react';
import {AbsoluteFill, continueRender, delayRender, useCurrentFrame, useVideoConfig} from 'remotion';
import {mix, prog} from '../theme';

export const INK = '#0A0A0A';
export const WHITE = '#FFFFFF';
export const GREY = '#5E5E5E';
export const SOFT = '#F4F4F4';
export const LINE = '#E2E2E2';
export const FONT = 'Geist, Inter, sans-serif';
export const MONO = '"Geist Mono", "Noto Sans Mono", monospace';

const FONTS_CSS =
  'https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@400;500&display=swap';

// The site's fonts. Falls back to the bundled faces if the network is down, so a
// render never hangs on it.
export const Fonts: React.FC = () => {
  const [handle] = useState(() => delayRender('Loading Geist'));
  useEffect(() => {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = FONTS_CSS;
    const done = () => continueRender(handle);
    link.onerror = done;
    link.onload = () => {
      Promise.all([
        document.fonts.load('600 80px Geist'),
        document.fonts.load('400 40px Geist'),
        document.fonts.load('500 40px Geist'),
        document.fonts.load('400 30px "Geist Mono"'),
      ]).then(done, done);
    };
    document.head.appendChild(link);
  }, [handle]);
  return null;
};

export const useWide = () => {
  const {width, height} = useVideoConfig();
  return width > height;
};

export const Fade: React.FC<{at: number; dur?: number; rise?: number; style?: React.CSSProperties; children: React.ReactNode}> = ({
  at,
  dur = 16,
  rise = 16,
  style,
  children,
}) => {
  const f = useCurrentFrame();
  const p = prog(f, at, dur);
  return <div style={{opacity: p, transform: `translateY(${(1 - p) * rise}px)`, ...style}}>{children}</div>;
};

export const Mark: React.FC<{size: number; at?: number; color?: string}> = ({size, at = 0, color = INK}) => {
  const f = useCurrentFrame();
  const bars = [
    {x: 100, y: 100, w: 300},
    {x: 140, y: 185.33, w: 220},
    {x: 100, y: 270.67, w: 300},
    {x: 180, y: 356, w: 140},
  ];
  return (
    <svg width={size} height={size} viewBox="100 100 300 300">
      {bars.map((b, i) => (
        <rect key={i} x={b.x} y={b.y} width={b.w * prog(f, at + i * 5, 20)} height={44} fill={color} />
      ))}
    </svg>
  );
};

/** One scene: a big title, a line that changes beat by beat, and the picture below. */
export const Scene: React.FC<{
  title: React.ReactNode;
  beats?: {at: number; text: React.ReactNode}[];
  dark?: boolean;
  children?: React.ReactNode;
}> = ({title, beats = [], dark = false, children}) => {
  const wide = useWide();
  const f = useCurrentFrame();
  return (
    <AbsoluteFill
      style={{
        background: dark ? INK : WHITE,
        color: dark ? WHITE : INK,
        fontFamily: FONT,
        padding: wide ? '84px 110px 76px' : '84px 64px 72px',
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      <Fade at={0}>
        <div style={{fontSize: wide ? 88 : 84, fontWeight: 600, letterSpacing: '-0.04em', lineHeight: 1.04}}>{title}</div>
      </Fade>
      <div style={{position: 'relative', height: wide ? 66 : 112, marginTop: wide ? 18 : 22, flex: 'none'}}>
        {beats.map((b, i) => {
          const next = beats[i + 1]?.at;
          const on = prog(f, b.at, 14);
          const off = next === undefined ? 0 : prog(f, next - 8, 8);
          return (
            <div
              key={i}
              style={{
                position: 'absolute',
                inset: 0,
                fontSize: wide ? 42 : 42,
                lineHeight: 1.3,
                letterSpacing: '-0.015em',
                color: dark ? '#B0B0B0' : GREY,
                opacity: on * (1 - off),
              }}
            >
              {b.text}
            </div>
          );
        })}
      </div>
      <div
        style={{
          flex: 1,
          minHeight: 0,
          marginTop: wide ? 34 : 30,
          display: 'flex',
          flexDirection: wide ? 'row' : 'column',
          alignItems: 'center',
          justifyContent: 'center',
          gap: wide ? 40 : 26,
        }}
      >
        {children}
      </div>
    </AbsoluteFill>
  );
};

export const Card: React.FC<{title: string; right?: React.ReactNode; at?: number; children: React.ReactNode}> = ({
  title,
  right,
  at = 0,
  children,
}) => {
  const wide = useWide();
  return (
    <Fade at={at} style={{width: wide ? 760 : '100%', flex: 'none'}}>
      <div style={{border: `2px solid ${INK}`, background: WHITE, color: INK, padding: wide ? '24px 30px 16px' : '20px 28px 12px'}}>
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            gap: 16,
            fontSize: 42,
            fontWeight: 600,
            letterSpacing: '-0.02em',
            paddingBottom: 12,
          }}
        >
          {title}
          {right}
        </div>
        {children}
      </div>
    </Fade>
  );
};

/** A key and its value. A value that is gone gets covered by a bar that wipes over it. */
export const Row: React.FC<{k: string; v: string; flash?: number; covered?: number}> = ({k, v, flash = 0, covered = 0}) => {
  const wide = useWide();
  return (
    <div
      style={{
        display: 'flex',
        gap: 18,
        alignItems: 'center',
        minHeight: wide ? 74 : 76,
        borderTop: `2px solid ${LINE}`,
        background: `rgba(10,10,10,${0.09 * flash})`,
      }}
    >
      <span style={{fontFamily: MONO, fontSize: 32, color: GREY, width: wide ? 236 : 244, flex: 'none'}}>{k}</span>
      <span style={{position: 'relative', fontSize: 40, fontWeight: 500, letterSpacing: '-0.015em', whiteSpace: 'nowrap'}}>
        {v}
        <span
          style={{
            position: 'absolute',
            left: -4,
            right: -4,
            top: 3,
            bottom: 3,
            background: INK,
            transform: `scaleX(${covered})`,
            transformOrigin: 'left',
          }}
        />
      </span>
    </div>
  );
};

export type Status = 'Active' | 'Paused' | 'Revoked';

export const Tag: React.FC<{children: string}> = ({children}) => {
  const solid = ['Active', 'Verified', 'DNS verified', 'Connected', 'Signed in'].includes(children);
  const gone = children === 'Revoked' || children === 'Disconnected';
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        height: 52,
        padding: '0 16px',
        fontSize: 32,
        fontWeight: 500,
        letterSpacing: '-0.01em',
        whiteSpace: 'nowrap',
        border: `2px solid ${gone ? LINE : INK}`,
        background: solid ? INK : WHITE,
        color: solid ? WHITE : gone ? GREY : INK,
        textDecoration: gone ? 'line-through' : undefined,
      }}
    >
      {children}
    </span>
  );
};

/** The link travelling from one side to the other. */
export const LinkChip: React.FC<{at: number; text?: string}> = ({at, text = '/s/k7Qx…'}) => {
  const wide = useWide();
  const f = useCurrentFrame();
  const p = prog(f, at, 30);
  const shift = mix(-46, 0, p);
  return (
    <div
      style={{
        flex: 'none',
        opacity: p,
        transform: wide ? `translateX(${shift}px)` : `translateY(${shift * 0.5}px)`,
        fontFamily: MONO,
        fontSize: 32,
        background: INK,
        color: WHITE,
        padding: '10px 16px',
        whiteSpace: 'nowrap',
      }}
    >
      {text}
    </div>
  );
};
