import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {FileText} from 'lucide-react';
import {prog} from '../theme';
import {Card, Fade, FONT, GREY, INK, LINE, LinkChip, Mark, MONO, Row, Scene, Tag, useWide, WHITE} from './ui';

const VALUES = {
  phone: '+49 151 2345 6789',
  address: 'Musterstraße 12, Berlin',
  sept: 'payslip-sept.pdf',
  oct: 'payslip-oct.pdf',
};

export const Open: React.FC = () => {
  const wide = useWide();
  return (
    <AbsoluteFill
      style={{
        background: INK,
        color: WHITE,
        fontFamily: FONT,
        padding: wide ? 110 : 64,
        justifyContent: 'center',
        gap: wide ? 54 : 48,
      }}
    >
      <Mark size={wide ? 150 : 170} at={2} color={WHITE} />
      <Fade at={26}>
        <div style={{fontSize: wide ? 136 : 94, fontWeight: 600, letterSpacing: '-0.045em', lineHeight: 1}}>
          Share any data.
        </div>
      </Fade>
      <Fade at={50} style={{marginTop: wide ? -44 : -38}}>
        <div style={{fontSize: wide ? 136 : 94, fontWeight: 600, letterSpacing: '-0.045em', lineHeight: 1}}>
          Take it back any time.
        </div>
      </Fade>
    </AbsoluteFill>
  );
};

export const Copies: React.FC = () => {
  const wide = useWide();
  const who = ['Landlord', 'Employer', 'Bank', 'Old gym'];
  return (
    <Scene
      title="Sending data means sending a copy."
      beats={[
        {at: 20, text: 'And another. And another.'},
        {at: 118, text: 'Once it’s out, you can’t change it or take it back.'},
      ]}
    >
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: wide ? 'repeat(4, 1fr)' : 'repeat(2, 1fr)',
          gap: 24,
          width: '100%',
        }}
      >
        {who.map((name, i) => (
          <Fade key={name} at={24 + i * 22}>
            <div style={{border: `2px solid ${INK}`, padding: 30, display: 'grid', gap: 18}}>
              <FileText size={72} color={INK} strokeWidth={1.6} />
              <div style={{fontFamily: MONO, fontSize: 32, color: GREY}}>passport.pdf</div>
              <div style={{fontSize: 42, fontWeight: 600, letterSpacing: '-0.02em'}}>{name}</div>
            </div>
          </Fade>
        ))}
      </div>
    </Scene>
  );
};

export const Share: React.FC = () => (
  <Scene
    title="Share a link instead."
    beats={[
      {at: 16, text: 'Your data stays in your vault.'},
      {at: 110, text: 'They open the link and see the latest version.'},
    ]}
  >
    <Card title="Your vault" at={10}>
      <Row k="phone" v={VALUES.phone} />
      <Row k="address" v={VALUES.address} />
      <Row k="payslip" v={VALUES.sept} />
    </Card>
    <LinkChip at={62} />
    <Card title="Landlord sees" at={112}>
      <Row k="phone" v={VALUES.phone} />
      <Row k="address" v={VALUES.address} />
      <Row k="payslip" v={VALUES.sept} />
    </Card>
  </Scene>
);

export const Update: React.FC = () => {
  const f = useCurrentFrame();
  const home = prog(f, 44, 8);
  const away = prog(f, 72, 8);
  const homeFlash = home * (1 - prog(f, 70, 40));
  const awayFlash = away * (1 - prog(f, 98, 40));
  return (
    <Scene title="Change it once." beats={[{at: 10, text: 'Everyone with the link sees the new one.'}]}>
      <Card title="Your vault">
        <Row k="phone" v={VALUES.phone} />
        <Row k="address" v={VALUES.address} />
        <Row k="payslip" v={home > 0.5 ? VALUES.oct : VALUES.sept} flash={homeFlash} />
      </Card>
      <LinkChip at={-30} />
      <Card title="Landlord sees">
        <Row k="phone" v={VALUES.phone} />
        <Row k="address" v={VALUES.address} />
        <Row k="payslip" v={away > 0.5 ? VALUES.oct : VALUES.sept} flash={awayFlash} />
      </Card>
    </Scene>
  );
};

const LinkLine: React.FC<{name: string; what: string; status: 'Active' | 'Revoked'; pressed?: number; action?: boolean}> = ({
  name,
  what,
  status,
  pressed = 0,
  action = false,
}) => (
  <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 14, minHeight: 104, borderTop: `2px solid ${LINE}`}}>
    <div>
      <div style={{fontSize: 40, fontWeight: 500, letterSpacing: '-0.015em'}}>{name}</div>
      <div style={{fontFamily: MONO, fontSize: 30, color: GREY}}>{what}</div>
    </div>
    <div style={{display: 'flex', gap: 12, alignItems: 'center'}}>
      {action && status === 'Active' && (
        <span
          style={{
            height: 52,
            display: 'inline-flex',
            alignItems: 'center',
            padding: '0 16px',
            fontSize: 32,
            fontWeight: 500,
            border: `2px solid ${INK}`,
            background: pressed > 0 ? INK : WHITE,
            color: pressed > 0 ? WHITE : INK,
            transform: `scale(${1 - pressed * 0.06})`,
          }}
        >
          Revoke
        </span>
      )}
      <Tag>{status}</Tag>
    </div>
  </div>
);

export const TakeBack: React.FC = () => {
  const f = useCurrentFrame();
  const AT = 62;
  const pressed = prog(f, AT - 8, 8) * (1 - prog(f, AT, 8));
  const done = f >= AT;
  return (
    <Scene
      title="Revoke it. Access stops."
      beats={[
        {at: 12, text: 'You don’t ask them to delete anything.'},
        {at: AT + 44, text: 'Your other links keep working.'},
      ]}
    >
      <Card title="Your links">
        <LinkLine name="Landlord" what="phone, address, payslip" status={done ? 'Revoked' : 'Active'} pressed={pressed} action />
        <LinkLine name="Tax advisor" what="tax_id, iban" status="Active" />
      </Card>
      <Card title="Landlord sees">
        <Row k="phone" v={VALUES.phone} covered={prog(f, AT + 2, 12)} />
        <Row k="address" v={VALUES.address} covered={prog(f, AT + 8, 12)} />
        <Row k="payslip" v={VALUES.oct} covered={prog(f, AT + 14, 12)} />
        <Fade at={AT + 26} rise={6}>
          <div style={{borderTop: `2px solid ${LINE}`, padding: '14px 0 6px', fontSize: 36, fontWeight: 500}}>
            This link has been revoked.
          </div>
        </Fade>
      </Card>
    </Scene>
  );
};

export const Ask: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <Scene
      title="Ask for data the same way."
      beats={[
        {at: 12, text: 'An employer sends you a form as a link.'},
        {at: 74, text: 'The app checks who’s really asking.'},
        {at: 136, text: 'You answer from your vault.'},
        {at: 196, text: 'Your answer stays yours. Revoke it any time.'},
      ]}
    >
      <Card title="Request" right={<span style={{opacity: prog(f, 80, 12)}}><Tag>Verified</Tag></span>} at={10}>
        <div style={{fontFamily: MONO, fontSize: 32, color: GREY, padding: '0 0 12px'}}>employer.example</div>
        <Row k="tax_id" v={f >= 148 ? '12 345 678 901' : '…'} />
        <Row k="iban" v={f >= 164 ? 'DE89 •••• •••• 4821' : '…'} />
      </Card>
      <Card title="Your links" at={190}>
        <LinkLine name="Employer" what="tax_id, iban" status="Active" />
      </Card>
    </Scene>
  );
};

export const Fact: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <Scene
      title="Show a fact, not the document."
      beats={[
        {at: 12, text: 'Another domain confirms it.'},
        {at: 70, text: 'You choose what to show.'},
      ]}
    >
      <Card title="Age check" right={<span style={{opacity: prog(f, 40, 12)}}><Tag>Verified</Tag></span>} at={8}>
        <div style={{fontFamily: MONO, fontSize: 32, color: GREY, padding: '0 0 12px'}}>verify.example</div>
        <Row k="age_over_18" v="Yes" />
        <Row k="birth_date" v="1991-03-14" covered={prog(f, 76, 12)} />
        <Row k="address" v={VALUES.address} covered={prog(f, 84, 12)} />
      </Card>
    </Scene>
  );
};

export const Code: React.FC = () => {
  const wide = useWide();
  const f = useCurrentFrame();
  const gone = f >= 84;
  const k = (s: string) => <span style={{color: '#A8A8A8'}}>"{s}"</span>;
  return (
    <Scene
      dark
      title="Everything the app does, your code can do."
      beats={[{at: 14, text: 'One public API. No private endpoints.'}]}
    >
      <Fade at={14} style={{width: wide ? 1100 : '100%'}}>
        <div style={{border: '2px solid #2C2C2C', padding: wide ? '26px 34px' : '24px 26px', fontFamily: MONO, fontSize: wide ? 34 : 31, lineHeight: 1.5, minHeight: wide ? 400 : 420, whiteSpace: 'pre'}}>
          <div style={{color: '#9A9A9A'}}>POST /api/grants/resolve</div>
          <div>{'{ '}{k('items')}{': [{'}</div>
          <div>{'  '}{k('status')}{': "'}{gone ? 'revoked' : 'active'}{'"'}{gone ? '' : ','}</div>
          {!gone && (
            <>
              <div>{'  '}{k('values')}{': {'}</div>
              <div>{'    '}{k('phone')}{': "+49 151 2345 6789"'}</div>
              <div>{'  }'}</div>
            </>
          )}
          <div>{'}] }'}</div>
        </div>
      </Fade>
    </Scene>
  );
};

export const Close: React.FC = () => {
  const wide = useWide();
  return (
    <AbsoluteFill
      style={{
        background: INK,
        color: WHITE,
        fontFamily: FONT,
        padding: wide ? 110 : 64,
        justifyContent: 'center',
        gap: wide ? 50 : 44,
      }}
    >
      <Mark size={wide ? 150 : 170} at={2} color={WHITE} />
      <Fade at={20}>
        <div style={{fontSize: wide ? 136 : 94, fontWeight: 600, letterSpacing: '-0.045em', lineHeight: 1}}>
          Start with one link.
        </div>
      </Fade>
      <Fade at={40}>
        <div style={{fontSize: 46, color: '#B0B0B0', letterSpacing: '-0.015em'}}>revoked.link</div>
      </Fade>
    </AbsoluteFill>
  );
};
