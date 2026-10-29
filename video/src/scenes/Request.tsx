import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {Check, CircleUserRound, ClipboardList, Link2, Send, ShieldCheck} from 'lucide-react';
import {Arrow, Tag} from '../components/flow';
import {LinkCard} from '../components/linkcard';
import {LinkPanel} from '../components/panel';
import {Button, Caption, Person, Strong} from '../components/ui';
import {TAX, VaultCard} from '../components/vault';
import {C, FONT, MONO, mix, prog} from '../theme';

const WS = {x: 70, y: 360, w: 620, h: 590};
const V = {x: 100, y: 440, w: 560};
const FORM = {x: 760, y: 400, w: 440};
const EMP = {x: 1580, y: 430};
const EP = {x: 1330, y: 620, w: 500};
const ANSWER = {x: 100, y: 730, w: 560};

const T = {travel: 30, trust: 160, account: 280, fill: 400, send: 455, gone: 470, answer: 478, read: 540};

const Field: React.FC<{name: string; p: number}> = ({name, p}) => (
  <div style={{padding: '0 22px', height: 80, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 6}}>
    <span style={{fontFamily: MONO, fontSize: 19, color: C.muted}}>{name}</span>
    <div
      style={{
        height: 44,
        borderRadius: 12,
        border: `2px solid ${p > 0 ? C.brand : C.divider}`,
        background: p > 0 ? C.brandTint : C.white,
        display: 'flex',
        alignItems: 'center',
        padding: '0 12px',
      }}
    >
      <span style={{opacity: p, display: 'inline-flex', alignItems: 'center', gap: 8, fontSize: 20, fontWeight: 650, color: C.onBrandTint}}>
        <Link2 size={20} strokeWidth={2.4} /> linked from vault · <span style={{fontFamily: MONO}}>{name}</span>
      </span>
    </div>
  </div>
);

const Form: React.FC = () => {
  const f = useCurrentFrame();
  const checks = ['DNS', 'root key', 'signature'];
  const verified = prog(f, T.trust + 50, 14);
  const account = prog(f, T.account, 16);
  return (
    <div style={{fontFamily: FONT, color: C.ink}}>
      <div style={{height: 70, display: 'flex', alignItems: 'center', gap: 12, padding: '0 22px', borderBottom: `2px solid ${C.divider}`}}>
        <ClipboardList size={28} color={C.brand} strokeWidth={2.2} />
        <span style={{fontSize: 26, fontWeight: 740, letterSpacing: '-0.02em', flex: 1}}>Onboarding</span>
        <span style={{fontFamily: MONO, fontSize: 19, color: C.muted}}>/r/onboarding</span>
      </div>
      <div style={{height: 58, display: 'flex', alignItems: 'center', gap: 10, padding: '0 22px', borderBottom: `2px solid ${C.divider}`}}>
        {verified < 1 &&
          checks.map((c, i) => {
            const p = prog(f, T.trust + 8 + i * 12, 10);
            return (
              <span key={c} style={{opacity: p * (1 - verified), display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 19, color: C.success, fontWeight: 650}}>
                <Check size={18} strokeWidth={3} /> {c}
              </span>
            );
          })}
        {verified > 0 && (
          <span style={{position: 'absolute', opacity: verified, display: 'inline-flex', alignItems: 'center', gap: 10, fontSize: 21, fontWeight: 680, color: C.success}}>
            <ShieldCheck size={24} strokeWidth={2.4} /> employer.example · verified
          </span>
        )}
      </div>
      <Field name="tax_id" p={prog(f, T.fill + 20, 12)} />
      <Field name="iban" p={prog(f, T.fill + 34, 12)} />
      <div style={{height: 52, display: 'flex', alignItems: 'center', gap: 10, padding: '0 22px', opacity: account, fontSize: 20, color: C.muted}}>
        <CircleUserRound size={22} color={C.success} strokeWidth={2.2} />
        signed in as <span style={{fontFamily: MONO, color: C.ink}}>mia@home.example</span>
      </div>
      <div style={{padding: '6px 22px 0'}}>
        <Button icon={Send} size={21} pressed={prog(f, T.send, 4) * (1 - prog(f, T.send + 4, 8))}>
          Send answer
        </Button>
      </div>
    </div>
  );
};

export const Request: React.FC = () => {
  const f = useCurrentFrame();
  const travel = prog(f, T.travel, 46);
  const gone = prog(f, T.gone, 16);
  const ws = prog(f, 0, 20);
  return (
    <AbsoluteFill>
      <Caption
        kicker="4 · Requests"
        title="A request asks Mia for data."
        beats={[
          {at: 0, text: 'Mia’s new employer needs a tax ID and an IBAN, so it sends a request: a form at its own link.'},
          {
            at: T.trust - 10,
            text: (
              <>
                Before anything is sent, Mia’s app checks <Strong>who is asking</Strong> — against the employer’s DNS.
              </>
            ),
          },
          {
            at: T.account - 10,
            text: (
              <>
                Answering needs an account. <Strong>There are no anonymous answers.</Strong>
              </>
            ),
          },
          {
            at: T.fill - 10,
            text: (
              <>
                Mia answers from the vault. The answer becomes a link — <Strong color={C.brand}>in Mia’s own workspace</Strong>.
              </>
            ),
          },
          {
            at: T.read,
            text: (
              <>
                The employer reads it live. Mia can <Strong>update</Strong> or <Strong color={C.danger}>revoke</Strong> it at any time.
              </>
            ),
          },
        ]}
      />
      <div
        style={{
          position: 'absolute',
          left: WS.x,
          top: WS.y,
          width: WS.w,
          height: WS.h,
          borderRadius: 26,
          border: `3px dashed ${C.brand}`,
          background: 'rgba(233,230,251,0.35)',
          opacity: ws,
        }}
      />
      <div style={{position: 'absolute', left: WS.x + 24, top: WS.y + 18, display: 'flex', alignItems: 'center', gap: 12, opacity: ws, fontFamily: FONT}}>
        <Person kind="mia" x={20} y={20} size={44} label="none" />
        <span style={{marginLeft: 36, fontSize: 24, fontWeight: 720, color: C.onBrandTint, letterSpacing: '-0.01em'}}>Mia’s workspace</span>
      </div>
      <VaultCard x={V.x} y={V.y} w={V.w} compact sections={[TAX]} at={4} />
      <Person kind="employer" x={EMP.x} y={EMP.y} at={6} size={104} />

      <Arrow id="req" from={{x: EMP.x - 70, y: EMP.y}} to={{x: FORM.x + FORM.w + 14, y: FORM.y + 60}} bend={-30} at={T.travel + 10} dur={30} fade={gone} />
      <div
        style={{
          position: 'absolute',
          left: mix(EMP.x - 120, FORM.x, travel),
          top: mix(EMP.y - 20, FORM.y, travel),
          width: FORM.w,
          height: 440,
          transformOrigin: '0 0',
          transform: `scale(${mix(0.35, 1, travel) * mix(1, 0.92, gone)})`,
          opacity: prog(f, T.travel - 6, 8) * (1 - gone),
          background: C.white,
          border: `2px solid ${C.divider}`,
          borderRadius: 18,
          boxShadow: '0 16px 44px rgba(22,21,31,0.10)',
          overflow: 'hidden',
        }}
      >
        <Form />
      </div>
      <Arrow id="f1" from={{x: V.x + V.w + 8, y: 585}} to={{x: FORM.x - 8, y: FORM.y + 128 + 62}} at={T.fill} dur={22} fade={gone} />
      <Arrow id="f2" from={{x: V.x + V.w + 8, y: 635}} to={{x: FORM.x - 8, y: FORM.y + 208 + 62}} at={T.fill + 14} dur={22} fade={gone} />

      <LinkCard
        x={ANSWER.x}
        y={ANSWER.y}
        w={ANSWER.w}
        at={T.answer}
        title="Employer"
        sub="answer to Onboarding"
        status="active"
        statusText="active"
        update
        outline={C.brand}
      />
      <Tag x={ANSWER.x + ANSWER.w / 2} y={ANSWER.y - 16} at={T.answer + 16} color={C.white} bg={C.brand}>
        new link · owned by Mia
      </Tag>
      <LinkPanel
        x={EP.x}
        y={EP.y}
        w={EP.w}
        at={T.read - 10}
        title="Onboarding · Mia’s answer"
        rows={TAX.rows}
        fill={T.read + 34}
      />
      <Arrow id="live" from={{x: ANSWER.x + ANSWER.w + 10, y: ANSWER.y + 88}} to={{x: EP.x - 12, y: EP.y + 120}} bend={30} at={T.read} dur={30} live />
      <Tag x={(ANSWER.x + ANSWER.w + EP.x) / 2} y={(ANSWER.y + 88 + EP.y + 120) / 2 + 52} at={T.read + 20}>
        employer reads live
      </Tag>
      <div style={{position: 'absolute', left: EP.x, top: EP.y + 220, width: EP.w, fontFamily: FONT, fontSize: 22, color: C.muted, opacity: prog(f, T.read + 70, 16), lineHeight: 1.4}}>
        What the employer holds is a link to Mia’s records. The records stay in Mia’s vault.
      </div>
    </AbsoluteFill>
  );
};
