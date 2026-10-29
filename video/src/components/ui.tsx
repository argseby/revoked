import React from 'react';
import {useCurrentFrame} from 'remotion';
import {
  BriefcaseBusiness,
  Calculator,
  EyeOff,
  FileText,
  Globe,
  House,
  type LucideIcon,
} from 'lucide-react';
import {C, FONT, MONO, easeInOut, mix, prog} from '../theme';

type Abs = {x: number; y: number};

export const Appear: React.FC<{
  at: number;
  dur?: number;
  rise?: number;
  out?: number;
  style?: React.CSSProperties;
  children: React.ReactNode;
}> = ({at, dur = 18, rise = 20, out, style, children}) => {
  const f = useCurrentFrame();
  const p = prog(f, at, dur);
  const o = out === undefined ? 1 : 1 - prog(f, out, 12);
  return (
    <div
      style={{
        opacity: p * o,
        transform: `translateY(${(1 - p) * rise}px)`,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

export type Beat = {at: number; text: React.ReactNode};

/** Scene heading: kicker, title, and a body line that changes beat by beat. */
export const Caption: React.FC<{
  kicker: string;
  title: React.ReactNode;
  beats?: Beat[];
}> = ({kicker, title, beats = []}) => {
  const f = useCurrentFrame();
  return (
    <div style={{position: 'absolute', left: 120, top: 76, width: 1680}}>
      <Appear at={0} dur={16}>
        <div
          style={{
            fontFamily: FONT,
            fontSize: 24,
            fontWeight: 700,
            letterSpacing: '0.14em',
            textTransform: 'uppercase',
            color: C.brand,
          }}
        >
          {kicker}
        </div>
      </Appear>
      <Appear at={4} dur={20}>
        <div
          style={{
            fontFamily: FONT,
            fontSize: 62,
            fontWeight: 760,
            letterSpacing: '-0.03em',
            lineHeight: 1.1,
            color: C.ink,
            marginTop: 10,
          }}
        >
          {title}
        </div>
      </Appear>
      <div style={{position: 'relative', height: 92, marginTop: 16}}>
        {beats.map((b, i) => {
          const next = beats[i + 1]?.at;
          const pin = prog(f, b.at + 8, 18);
          const pout = next === undefined ? 0 : prog(f, next - 2, 10);
          return (
            <div
              key={i}
              style={{
                position: 'absolute',
                left: 0,
                top: 0,
                width: 1500,
                fontFamily: FONT,
                fontSize: 34,
                lineHeight: 1.3,
                color: C.muted,
                opacity: pin * (1 - pout),
                transform: `translateY(${(1 - pin) * 14}px)`,
              }}
            >
              {b.text}
            </div>
          );
        })}
      </div>
    </div>
  );
};

export const Strong: React.FC<{children: React.ReactNode; color?: string}> = ({
  children,
  color = C.ink,
}) => <span style={{color, fontWeight: 650}}>{children}</span>;

export const Code: React.FC<{children: React.ReactNode}> = ({children}) => (
  <span
    style={{
      fontFamily: MONO,
      fontSize: '0.86em',
      background: C.sunken,
      borderRadius: 8,
      padding: '1px 8px',
      color: C.ink,
    }}
  >
    {children}
  </span>
);

export type Kind = 'mia' | 'landlord' | 'employer' | 'advisor' | 'portal';

const PEOPLE: Record<Kind, {name: string; role: string; Icon?: LucideIcon}> = {
  mia: {name: 'Mia', role: 'looking for a flat'},
  landlord: {name: 'Landlord', role: 'has a flat to rent', Icon: House},
  employer: {name: 'Employer', role: 'employer.example', Icon: BriefcaseBusiness},
  advisor: {name: 'Tax advisor', role: 'files the tax return', Icon: Calculator},
  portal: {name: 'Letting portal', role: 'letting.example', Icon: Globe},
};

export const Person: React.FC<
  Abs & {
    kind: Kind;
    at?: number;
    size?: number;
    role?: boolean;
    label?: 'below' | 'right' | 'left' | 'none';
    dim?: number;
  }
> = ({x, y, kind, at = 0, size = 116, role = true, label = 'below', dim = 0}) => {
  const f = useCurrentFrame();
  const p = prog(f, at, 22);
  const scale = mix(0.6, 1, p);
  const {name, role: roleText, Icon} = PEOPLE[kind];
  const mia = kind === 'mia';
  const labelBox =
    label === 'below'
      ? {left: x - 200, top: y + size / 2 + 14, width: 400, textAlign: 'center' as const}
      : label === 'right'
        ? {left: x + size / 2 + 22, top: y - 34, width: 420, textAlign: 'left' as const}
        : {left: x - size / 2 - 442, top: y - 34, width: 420, textAlign: 'right' as const};
  return (
    <div style={{opacity: p * (1 - dim * 0.55), filter: dim ? `grayscale(${dim})` : undefined}}>
      <div
        style={{
          position: 'absolute',
          left: x - size / 2,
          top: y - size / 2,
          width: size,
          height: size,
          borderRadius: '50%',
          background: mia ? C.brand : C.brandTint,
          border: `3px solid ${mia ? C.brand : C.white}`,
          boxShadow: '0 10px 30px rgba(61,53,181,0.16)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          transform: `scale(${scale})`,
        }}
      >
        {Icon ? (
          <Icon size={size * 0.46} color={C.onBrandTint} strokeWidth={1.9} />
        ) : (
          <span
            style={{
              fontFamily: FONT,
              fontWeight: 760,
              fontSize: size * 0.46,
              color: C.white,
              letterSpacing: '-0.03em',
            }}
          >
            M
          </span>
        )}
      </div>
      {label !== 'none' && (
        <div style={{position: 'absolute', ...labelBox, fontFamily: FONT}}>
          <div style={{fontSize: 30, fontWeight: 720, color: C.ink, letterSpacing: '-0.02em'}}>
            {name}
          </div>
          {role && <div style={{fontSize: 22, color: C.muted, marginTop: 2}}>{roleText}</div>}
        </div>
      )}
    </div>
  );
};

export const Card: React.FC<
  Abs & {
    w: number;
    h?: number;
    at?: number;
    style?: React.CSSProperties;
    children?: React.ReactNode;
    outline?: string;
  }
> = ({x, y, w, h, at = 0, style, children, outline}) => {
  const f = useCurrentFrame();
  const p = prog(f, at, 20);
  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        width: w,
        height: h,
        background: C.white,
        border: `2px solid ${outline ?? C.divider}`,
        borderRadius: 18,
        boxShadow: '0 12px 36px rgba(22,21,31,0.07)',
        opacity: p,
        transform: `translateY(${(1 - p) * 24}px) scale(${mix(0.97, 1, p)})`,
        fontFamily: FONT,
        color: C.ink,
        overflow: 'hidden',
        ...style,
      }}
    >
      {children}
    </div>
  );
};

export type Tone = 'active' | 'paused' | 'revoked' | 'brand' | 'neutral';

const TONES: Record<Tone, {fg: string; bg: string}> = {
  active: {fg: C.success, bg: C.successTint},
  paused: {fg: C.warning, bg: C.warningTint},
  revoked: {fg: C.danger, bg: C.dangerTint},
  brand: {fg: C.onBrandTint, bg: C.brandTint},
  neutral: {fg: C.muted, bg: C.sunken},
};

export const Pill: React.FC<{
  tone: Tone;
  children: React.ReactNode;
  dot?: boolean;
  size?: number;
  icon?: LucideIcon;
  style?: React.CSSProperties;
}> = ({tone, children, dot = false, size = 20, icon: Icon, style}) => {
  const {fg, bg} = TONES[tone];
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 8,
        fontFamily: FONT,
        fontSize: size,
        fontWeight: 680,
        color: fg,
        background: bg,
        borderRadius: 999,
        padding: `${size * 0.22}px ${size * 0.7}px`,
        whiteSpace: 'nowrap',
        ...style,
      }}
    >
      {dot && (
        <span style={{width: size * 0.45, height: size * 0.45, borderRadius: '50%', background: fg}} />
      )}
      {Icon && <Icon size={size * 1.05} strokeWidth={2.2} />}
      {children}
    </span>
  );
};

export type RowKind = 'text' | 'file' | 'hidden';

/** A vault record: key on the left, value on the right. */
export const Row: React.FC<{
  k: string;
  v: React.ReactNode;
  kind?: RowKind;
  flash?: number;
  dim?: number;
  compact?: boolean;
  badge?: React.ReactNode;
  badgeP?: number;
}> = ({k, v, kind = 'text', flash = 0, dim = 0, compact = false, badge, badgeP = 1}) => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      gap: 16,
      height: compact ? 50 : 58,
      padding: '0 18px',
      borderRadius: 12,
      background: `rgba(61,53,181,${0.13 * flash})`,
      opacity: 1 - dim * 0.6,
    }}
  >
    <span style={{fontFamily: MONO, fontSize: compact ? 21 : 23, color: C.muted, width: compact ? 150 : 170}}>
      {k}
    </span>
    <span
      style={{
        flex: 1,
        display: 'flex',
        alignItems: 'center',
        gap: 10,
        fontSize: compact ? 22 : 24,
        fontWeight: 560,
        color: C.ink,
        whiteSpace: 'nowrap',
      }}
    >
      {kind === 'file' && <FileText size={24} color={C.brand} strokeWidth={2} />}
      {kind === 'hidden' && <EyeOff size={22} color={C.muted} strokeWidth={2} />}
      {v}
    </span>
    {badge && (
      <span style={{opacity: badgeP, transform: `scale(${0.85 + 0.15 * badgeP})`}}>
        <Pill tone="neutral" size={18}>
          {badge}
        </Pill>
      </span>
    )}
  </div>
);

export const SectionHead: React.FC<{name: string; highlight?: number; right?: React.ReactNode}> = ({
  name,
  highlight = 0,
  right,
}) => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '0 18px',
      height: 40,
      fontSize: 19,
      fontWeight: 720,
      letterSpacing: '0.1em',
      textTransform: 'uppercase',
      color: highlight > 0.5 ? C.brand : C.muted,
    }}
  >
    {name}
    {right}
  </div>
);

/** A soft indigo ring drawn around a box, for "this part is meant". */
export const Ring: React.FC<{x: number; y: number; w: number; h: number; p: number; color?: string}> = ({
  x,
  y,
  w,
  h,
  p,
  color = C.brand,
}) => (
  <div
    style={{
      position: 'absolute',
      left: x - 6,
      top: y - 6,
      width: w + 12,
      height: h + 12,
      borderRadius: 18,
      border: `3px solid ${color}`,
      opacity: p,
      transform: `scale(${mix(1.04, 1, p)})`,
    }}
  />
);

export const Cursor: React.FC<{x: number; y: number; at: number; click?: number; from?: Abs; out?: number}> = ({
  x: tx,
  y: ty,
  at,
  click,
  from,
  out,
}) => {
  const f = useCurrentFrame();
  const p = prog(f, at, 14) * (out === undefined ? 1 : 1 - prog(f, out, 14));
  const m = prog(f, at, 34, easeInOut);
  const x = from ? mix(from.x, tx, m) : tx;
  const y = from ? mix(from.y, ty, m) : ty;
  const c = click === undefined ? 0 : prog(f, click, 8) * (1 - prog(f, click + 8, 14));
  const ring = click === undefined ? 0 : prog(f, click, 20);
  return (
    <div style={{position: 'absolute', left: x, top: y, opacity: p, pointerEvents: 'none'}}>
      {click !== undefined && (
        <div
          style={{
            position: 'absolute',
            left: -30,
            top: -30,
            width: 60,
            height: 60,
            borderRadius: '50%',
            border: `3px solid ${C.brand}`,
            opacity: ring > 0 && ring < 1 ? 1 - ring : 0,
            transform: `scale(${mix(0.3, 1.4, ring)})`,
          }}
        />
      )}
      <svg width={40} height={44} viewBox="0 0 20 22" style={{transform: `scale(${1 - c * 0.15})`, transformOrigin: '0 0'}}>
        <path
          d="M2 1.5 L2 17 L6.2 13 L9.2 20 L12 18.8 L9.1 12 L15 12 Z"
          fill={C.ink}
          stroke={C.white}
          strokeWidth={1.4}
          strokeLinejoin="round"
        />
      </svg>
    </div>
  );
};

export const Button: React.FC<{
  tone?: 'brand' | 'danger' | 'quiet';
  children: React.ReactNode;
  pressed?: number;
  icon?: LucideIcon;
  size?: number;
}> = ({tone = 'brand', children, pressed = 0, icon: Icon, size = 22}) => {
  const bg = tone === 'brand' ? C.brand : tone === 'danger' ? C.danger : C.brandTint;
  const fg = tone === 'quiet' ? C.onBrandTint : C.white;
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 10,
        background: bg,
        color: fg,
        borderRadius: 12,
        padding: `${size * 0.45}px ${size * 0.9}px`,
        fontFamily: FONT,
        fontSize: size,
        fontWeight: 680,
        transform: `scale(${1 - pressed * 0.06})`,
        whiteSpace: 'nowrap',
      }}
    >
      {Icon && <Icon size={size * 1.05} strokeWidth={2.2} />}
      {children}
    </span>
  );
};
