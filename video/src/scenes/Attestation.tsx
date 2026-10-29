import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {Award, Check, Fingerprint, KeyRound, Lock, PenLine, ShieldCheck, Ban} from 'lucide-react';
import {Arrow, Packet, Tag} from '../components/flow';
import {Button, Caption, Card, Person, Pill, Strong} from '../components/ui';
import {C, FONT, MONO, prog} from '../theme';

const EMP = {x: 300, y: 500};
const PORTAL = {x: 1620, y: 500};
const PHONE = {x: 755, y: 350, w: 410, h: 650};
const RES = {x: 1350, y: 650, w: 480};

const T = {offer: 24, accept: 180, challenge: 205, signed: 250, credential: 292, held: 330, ask: 360, choose: 460, uncheck: 490, show: 530, present: 536, result: 580, revoke: 620};

const CLAIMS = [
  {k: 'employed', v: 'yes'},
  {k: 'permanent_contract', v: 'yes'},
  {k: 'position', v: 'Engineer'},
];

const phase = (f: number, a: number, b: number) => prog(f, a, 14) * (1 - prog(f, b, 12));

const Box: React.FC<{on: boolean}> = ({on}) => (
  <span
    style={{
      width: 24,
      height: 24,
      borderRadius: 7,
      border: `2px solid ${on ? C.brand : C.border}`,
      background: on ? C.brand : C.white,
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      flexShrink: 0,
    }}
  >
    {on && <Check size={18} color={C.white} strokeWidth={3.2} />}
  </span>
);

const Screen: React.FC<{p: number; children: React.ReactNode}> = ({p, children}) =>
  p <= 0 ? null : (
    <div style={{position: 'absolute', left: 24, right: 24, top: 150, opacity: p, transform: `translateY(${(1 - p) * 12}px)`}}>
      {children}
    </div>
  );

const Phone: React.FC = () => {
  const f = useCurrentFrame();
  const revoked = f >= T.revoke + 14;
  const signing = prog(f, T.accept + 8, 10);
  const keyPulse = prog(f, T.challenge + 28, 8) * (1 - prog(f, T.challenge + 36, 14)) + prog(f, T.show + 2, 6) * (1 - prog(f, T.show + 8, 14));
  const withheld = f >= T.uncheck;
  return (
    <div
      style={{
        position: 'absolute',
        left: PHONE.x,
        top: PHONE.y,
        width: PHONE.w,
        height: PHONE.h,
        borderRadius: 48,
        background: C.white,
        border: `3px solid ${C.ink}`,
        boxShadow: '0 24px 60px rgba(22,21,31,0.14)',
        fontFamily: FONT,
        color: C.ink,
        opacity: prog(f, 0, 18),
        overflow: 'hidden',
      }}
    >
      <div style={{position: 'absolute', left: PHONE.w / 2 - 50, top: 14, width: 100, height: 22, borderRadius: 999, background: C.ink}} />
      <div style={{position: 'absolute', left: 22, right: 22, top: 54, display: 'flex', alignItems: 'center', gap: 12}}>
        <Person kind="mia" x={24} y={24} size={48} label="none" />
        <div style={{marginLeft: 60}}>
          <div style={{fontSize: 22, fontWeight: 720}}>Mia Berger</div>
          <div style={{fontFamily: MONO, fontSize: 16, color: C.muted, display: 'flex', alignItems: 'center', gap: 6, whiteSpace: 'nowrap'}}>
            <Fingerprint size={16} /> 3fa2…c91 · home.example
          </div>
        </div>
      </div>

      <Screen p={phase(f, T.offer + 40, T.held)}>
        <div style={{fontSize: 19, fontWeight: 720, letterSpacing: '0.1em', color: C.muted}}>ATTESTATION OFFER</div>
        <div style={{fontSize: 30, fontWeight: 740, marginTop: 6, letterSpacing: '-0.02em'}}>employment</div>
        <div style={{fontSize: 21, color: C.success, fontWeight: 650, display: 'flex', alignItems: 'center', gap: 6, marginTop: 4}}>
          <ShieldCheck size={20} /> employer.example
        </div>
        <div style={{marginTop: 14, background: C.card, borderRadius: 14, padding: '6px 14px'}}>
          {CLAIMS.map((c) => (
            <div key={c.k} style={{display: 'flex', justifyContent: 'space-between', padding: '9px 0', fontSize: 21}}>
              <span style={{fontFamily: MONO, color: C.muted, fontSize: 19}}>{c.k}</span>
              <span style={{fontWeight: 650}}>{c.v}</span>
            </div>
          ))}
        </div>
        <div style={{marginTop: 22, opacity: 1 - signing}}>
          <Button size={23} pressed={prog(f, T.accept, 4) * (1 - prog(f, T.accept + 4, 8))}>
            Accept
          </Button>
        </div>
        <div style={{marginTop: -46, opacity: signing, display: 'flex', alignItems: 'center', gap: 10, fontSize: 22, fontWeight: 650, color: C.brand}}>
          <PenLine size={22} /> signing the challenge…
        </div>
      </Screen>

      <Screen p={phase(f, T.held, T.choose - 6)}>
        <div style={{fontSize: 19, fontWeight: 720, letterSpacing: '0.1em', color: C.muted}}>HELD</div>
        <div style={{marginTop: 10, border: `2px solid ${C.divider}`, borderRadius: 16, padding: 16}}>
          <div style={{display: 'flex', alignItems: 'center', gap: 10}}>
            <Award size={28} color={C.brand} />
            <span style={{fontSize: 28, fontWeight: 740, flex: 1}}>employment</span>
          </div>
          <div style={{fontSize: 21, color: C.muted, marginTop: 6}}>by employer.example</div>
          <div style={{marginTop: 12}}>
            <Pill tone="active" dot size={18}>
              Verified
            </Pill>
          </div>
        </div>
      </Screen>

      <Screen p={prog(f, T.choose - 6, 14)}>
        <div style={{fontSize: 19, fontWeight: 720, letterSpacing: '0.1em', color: C.muted}}>LETTING.EXAMPLE ASKS</div>
        <div style={{display: 'flex', alignItems: 'center', gap: 10, marginTop: 8}}>
          <span style={{fontSize: 28, fontWeight: 740, flex: 1}}>employment</span>
          <Pill tone={revoked ? 'revoked' : 'active'} dot size={16}>
            {revoked ? 'Revoked' : 'Verified'}
          </Pill>
        </div>
        <div style={{marginTop: 12}}>
          {CLAIMS.map((c, i) => {
            const on = i < 2 || !withheld;
            return (
              <div key={c.k} style={{display: 'flex', alignItems: 'center', gap: 12, padding: '12px 0', borderBottom: i < 2 ? `1px solid ${C.divider}` : undefined, opacity: on ? 1 : 0.55}}>
                <Box on={on} />
                <span style={{fontFamily: MONO, fontSize: 19, flex: 1}}>{c.k}</span>
                <span style={{fontSize: 21, fontWeight: 650}}>{on ? c.v : 'withheld'}</span>
              </div>
            );
          })}
        </div>
        <div style={{marginTop: 22}}>
          <Button size={23} pressed={prog(f, T.show, 4) * (1 - prog(f, T.show + 4, 8))}>
            Show it
          </Button>
        </div>
      </Screen>

      <div
        style={{
          position: 'absolute',
          left: 18,
          right: 18,
          bottom: 22,
          borderRadius: 16,
          background: C.brandTint,
          padding: '12px 16px',
          display: 'flex',
          alignItems: 'center',
          gap: 12,
          boxShadow: keyPulse ? `0 0 0 ${keyPulse * 8}px rgba(61,53,181,0.25)` : undefined,
        }}
      >
        <KeyRound size={30} color={C.brand} strokeWidth={2.2} />
        <div>
          <div style={{fontSize: 19, fontWeight: 720, color: C.onBrandTint}}>identity key</div>
          <div style={{fontSize: 16, color: C.onBrandTint, display: 'flex', alignItems: 'center', gap: 5}}>
            <Lock size={14} /> stays on this phone
          </div>
        </div>
      </div>
    </div>
  );
};

const Result: React.FC = () => {
  const f = useCurrentFrame();
  const revoked = f >= T.revoke + 30;
  return (
    <Card x={RES.x} y={RES.y} w={RES.w} h={250} at={T.result} outline={revoked ? C.dangerTint : undefined}>
      <div style={{padding: '16px 22px'}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 10}}>
          <span style={{fontSize: 24, fontWeight: 740, flex: 1}}>Presentation</span>
          <Pill tone={revoked ? 'revoked' : 'active'} dot size={18}>
            {revoked ? 'revoked' : 'verified'}
          </Pill>
        </div>
        <div style={{fontSize: 19, color: C.muted, marginTop: 4}}>employer.example attests, checked via its DNS</div>
        <div style={{marginTop: 12, opacity: revoked ? 0.4 : 1}}>
          {CLAIMS.slice(0, 2).map((c) => (
            <div key={c.k} style={{display: 'flex', alignItems: 'center', gap: 10, padding: '4px 0', fontSize: 20}}>
              <Check size={20} color={C.success} strokeWidth={3} />
              <span style={{fontFamily: MONO, fontSize: 18, flex: 1}}>{c.k}</span>
              <span style={{fontWeight: 650}}>{c.v}</span>
            </div>
          ))}
          <div style={{fontSize: 18, color: C.muted, marginTop: 4}}>+ 1 claim withheld</div>
        </div>
      </div>
    </Card>
  );
};

const chip = (text: React.ReactNode, tone: 'brand' | 'quiet' = 'brand') => (
  <div
    style={{
      display: 'inline-flex',
      alignItems: 'center',
      gap: 8,
      background: tone === 'brand' ? C.brand : C.white,
      color: tone === 'brand' ? C.white : C.onBrandTint,
      border: tone === 'brand' ? 'none' : `2px solid ${C.brand}`,
      borderRadius: 999,
      padding: '8px 18px',
      fontFamily: FONT,
      fontSize: 21,
      fontWeight: 680,
      whiteSpace: 'nowrap',
      boxShadow: '0 8px 22px rgba(61,53,181,0.22)',
    }}
  >
    {text}
  </div>
);

export const Attestation: React.FC = () => {
  const f = useCurrentFrame();
  const eTop = {x: EMP.x + 80, y: EMP.y - 40};
  const pTop = {x: PHONE.x - 14, y: 470};
  const eBot = {x: EMP.x + 80, y: EMP.y + 40};
  const pBot = {x: PHONE.x - 14, y: 590};
  const portalIn = {x: PORTAL.x - 80, y: PORTAL.y - 10};
  const phoneR = {x: PHONE.x + PHONE.w + 14, y: 520};
  return (
    <AbsoluteFill>
      <Caption
        kicker="5 · Attestations"
        title="What others confirm about Mia."
        beats={[
          {at: 0, text: 'The employer attests Mia’s employment — to Mia’s identity, in the name of employer.example.'},
          {
            at: T.accept - 10,
            text: (
              <>
                Mia accepts by signing a challenge. <Strong>The private key never leaves Mia’s phone.</Strong>
              </>
            ),
          },
          {at: T.ask - 10, text: 'Later, the landlord’s letting portal asks: is Mia employed?'},
          {
            at: T.choose,
            text: (
              <>
                Mia picks which claims to show. The portal checks them against <Strong>employer.example</Strong>.
              </>
            ),
          },
          {
            at: T.revoke,
            text: (
              <>
                If the employer revokes it, <Strong color={C.danger}>verifiers learn within minutes</Strong>.
              </>
            ),
          },
        ]}
      />
      <Person kind="employer" x={EMP.x} y={EMP.y} at={4} size={110} />
      <Person kind="portal" x={PORTAL.x} y={PORTAL.y} at={T.ask - 20} size={110} />
      <Phone />

      <Arrow id="offer" from={eTop} to={pTop} bend={-30} at={T.offer} dur={26} fade={prog(f, T.ask, 20) * 0.7} />
      <Packet from={eTop} to={pTop} bend={-30} at={T.offer + 4} dur={40} hold={false}>
        {chip(<span style={{fontFamily: MONO, fontSize: 19}}>revoked://a/…</span>)}
      </Packet>
      <Packet from={eTop} to={pTop} bend={-30} at={T.challenge} dur={32} hold={false}>
        {chip('challenge', 'quiet')}
      </Packet>
      <Arrow id="back" from={pBot} to={eBot} bend={-30} at={T.signed - 6} dur={22} fade={prog(f, T.ask, 20) * 0.7} />
      <Packet from={pBot} to={eBot} bend={-30} at={T.signed} dur={32} hold={false}>
        {chip(
          <>
            <PenLine size={20} /> signature
          </>,
          'quiet',
        )}
      </Packet>
      <Packet from={eTop} to={pTop} bend={-30} at={T.credential} dur={34} hold={false}>
        {chip(
          <>
            <Award size={20} /> credential
          </>,
        )}
      </Packet>
      <Tag x={(EMP.x + PHONE.x) / 2 + 30} y={680} at={T.signed + 10} out={T.ask} color={C.onBrandTint} bg={C.brandTint}>
        <Lock size={18} /> only the signature travels
      </Tag>

      <Arrow id="ask" from={portalIn} to={phoneR} bend={30} at={T.ask} dur={26} />
      <Packet from={portalIn} to={phoneR} bend={30} at={T.ask + 4} dur={40} hold={false}>
        {chip('employed?', 'quiet')}
      </Packet>
      <Arrow id="present" from={{x: phoneR.x, y: 640}} to={{x: RES.x - 14, y: RES.y + 110}} bend={-20} at={T.present} dur={24} />
      <Packet from={{x: phoneR.x, y: 640}} to={{x: RES.x - 14, y: RES.y + 110}} bend={-20} at={T.present + 2} dur={36} hold={false}>
        {chip(
          <>
            <ShieldCheck size={20} /> presentation
          </>,
        )}
      </Packet>
      <Result />

      <div style={{position: 'absolute', left: EMP.x - 80, top: EMP.y + 150, opacity: prog(f, T.revoke - 20, 14)}}>
        <Button tone="danger" icon={Ban} size={21} pressed={prog(f, T.revoke, 4) * (1 - prog(f, T.revoke + 4, 8))}>
          Revoke
        </Button>
      </div>
    </AbsoluteFill>
  );
};
