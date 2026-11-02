import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {TransitionSeries, linearTiming} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import {Check, FileText, X} from 'lucide-react';
import {prog} from '../theme';
import {QR_PATH, QR_SIZE} from './qr';
import {Card, Fade, FONT, Fonts, GREY, INK, LINE, LinkChip, Mark, MONO, Row, Scene, SOFT, Tag, useWide, WHITE} from './ui';

const FADE = 12;

const TitleCard: React.FC<{title: string; line: string}> = ({title, line}) => {
  const wide = useWide();
  return (
    <AbsoluteFill style={{background: INK, color: WHITE, fontFamily: FONT, padding: wide ? 110 : 64, justifyContent: 'center', gap: wide ? 44 : 40}}>
      <Mark size={wide ? 110 : 130} at={2} color={WHITE} />
      <Fade at={14}>
        <div style={{fontSize: wide ? 136 : 104, fontWeight: 600, letterSpacing: '-0.045em', lineHeight: 1}}>{title}</div>
      </Fade>
      <Fade at={28}>
        <div style={{fontSize: wide ? 52 : 50, lineHeight: 1.25, letterSpacing: '-0.02em', color: '#B0B0B0', maxWidth: 1500}}>{line}</div>
      </Fade>
    </AbsoluteFill>
  );
};

const CloseCard: React.FC<{title: string; url: string}> = ({title, url}) => {
  const wide = useWide();
  return (
    <AbsoluteFill style={{background: INK, color: WHITE, fontFamily: FONT, padding: wide ? 110 : 64, justifyContent: 'center', gap: wide ? 44 : 40}}>
      <Mark size={wide ? 110 : 130} at={2} color={WHITE} />
      <Fade at={14}>
        <div style={{fontSize: wide ? 112 : 92, fontWeight: 600, letterSpacing: '-0.04em', lineHeight: 1.02}}>{title}</div>
      </Fade>
      <Fade at={28}>
        <div style={{fontFamily: MONO, fontSize: wide ? 42 : 38, color: '#B0B0B0'}}>{url}</div>
      </Fade>
    </AbsoluteFill>
  );
};

/** A control that gets pressed at `at` and stays pressed. */
const Btn: React.FC<{label: string; at?: number; done?: string; ghost?: boolean}> = ({label, at = 1e6, done, ghost = false}) => {
  const f = useCurrentFrame();
  const press = prog(f, at - 8, 8) * (1 - prog(f, at, 8));
  const pressed = f >= at;
  const solid = !ghost || pressed;
  return (
    <div
      style={{
        flex: 1,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: 76,
        padding: '0 18px',
        fontSize: 36,
        fontWeight: 500,
        letterSpacing: '-0.015em',
        whiteSpace: 'nowrap',
        border: `2px solid ${INK}`,
        background: solid ? INK : WHITE,
        color: solid ? WHITE : INK,
        transform: `scale(${1 - press * 0.05})`,
      }}
    >
      {pressed && done ? done : label}
    </div>
  );
};

/** A tick box with a label. `on` turns it on, `off` turns it off again. */
const Tick: React.FC<{label: string; sub?: string; on?: number; off?: number; mono?: boolean}> = ({label, sub, on = 1e6, off = 1e6, mono = false}) => {
  const f = useCurrentFrame();
  const ticked = f >= on && f < off;
  return (
    <div style={{display: 'flex', gap: 20, alignItems: 'flex-start', padding: '16px 0', borderTop: `2px solid ${LINE}`}}>
      <span
        style={{
          flex: 'none',
          width: 44,
          height: 44,
          marginTop: 2,
          display: 'grid',
          placeItems: 'center',
          border: `2px solid ${INK}`,
          background: ticked ? INK : WHITE,
        }}
      >
        {ticked && <Check size={32} color={WHITE} strokeWidth={3} />}
      </span>
      <div style={{minWidth: 0}}>
        <div style={{fontFamily: mono ? MONO : FONT, fontSize: mono ? 34 : 38, fontWeight: mono ? 400 : 500, letterSpacing: mono ? 0 : '-0.015em', lineHeight: 1.2}}>{label}</div>
        {sub && <div style={{fontSize: 34, color: GREY, lineHeight: 1.25, marginTop: 4}}>{sub}</div>}
      </div>
    </div>
  );
};

const Line: React.FC<{left: React.ReactNode; right?: React.ReactNode; sub?: string; at?: number}> = ({left, right, sub, at = 0}) => (
  <Fade at={at} rise={6}>
    <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 16, minHeight: 88, padding: '10px 0', borderTop: `2px solid ${LINE}`}}>
      <div style={{minWidth: 0}}>
        <div style={{fontSize: 38, fontWeight: 500, letterSpacing: '-0.015em', lineHeight: 1.2}}>{left}</div>
        {sub && <div style={{fontSize: 34, color: GREY, lineHeight: 1.25}}>{sub}</div>}
      </div>
      {right}
    </div>
  </Fade>
);

const Code: React.FC<{at?: number; lines: string[]}> = ({at = 0, lines}) => {
  const wide = useWide();
  return (
    <Fade at={at} style={{width: wide ? 1040 : '100%'}}>
      <div style={{background: INK, color: WHITE, padding: '26px 30px', fontFamily: MONO, fontSize: wide ? 33 : 34, lineHeight: 1.45, whiteSpace: 'pre'}}>
        {lines.map((l, i) => (
          <div key={i}>{l}</div>
        ))}
      </div>
    </Fade>
  );
};

/** ---------------- Sign in ---------------- */

const AddButton: React.FC = () => {
  const f = useCurrentFrame();
  const at = 50;
  return (
    <Scene
      title="Add the button."
      beats={[
        {at: 10, text: 'Put it on your site. There’s nothing to register.'},
        {at: at + 16, text: 'It opens a QR code for a phone and a link for this device.'},
      ]}
    >
      <Card title="shop.example">
        <div style={{display: 'flex', paddingBottom: 18}}>
          <Btn label="Sign in with Revoked" at={at} />
        </div>
        <div style={{opacity: prog(f, at + 6, 14), display: 'flex', gap: 28, alignItems: 'center', borderTop: `2px solid ${LINE}`, padding: '20px 0 12px'}}>
          <svg width={230} height={230} viewBox={`0 0 ${QR_SIZE} ${QR_SIZE}`} shapeRendering="crispEdges" style={{flex: 'none'}}>
            <path d={QR_PATH} fill={INK} />
          </svg>
          <div style={{fontSize: 32, lineHeight: 1.3, color: GREY}}>
            Only continue if the app shows this code:
            <div style={{fontFamily: MONO, fontSize: 48, color: INK, marginTop: 10, letterSpacing: '0.04em'}}>0D2-99B</div>
          </div>
        </div>
      </Card>
    </Scene>
  );
};

const ApproveSignIn: React.FC = () => {
  const f = useCurrentFrame();
  const at = 142;
  return (
    <Scene
      title="They approve in the app."
      beats={[
        {at: 10, text: 'The app shows who is asking and what you would learn.'},
        {at: 76, text: 'They choose what to share. Nothing is shared until they confirm.'},
      ]}
    >
      <Card title="shop.example" right={f >= at + 6 ? <Tag>Signed in</Tag> : undefined}>
        <div style={{fontSize: 36, color: f >= at + 6 ? INK : GREY, padding: '20px 0 22px', borderTop: `2px solid ${LINE}`}}>
          {f >= at + 6 ? 'Welcome back.' : 'Waiting for you to approve…'}
        </div>
      </Card>
      <Card title="Sign in to shop.example" at={14}>
        <Tick label="That it is you" sub="Through an ID made just for shop.example." on={0} />
        <Tick label="Your entry “shipping_address”" sub="Home — Musterstraße 12, Berlin" on={92} />
        <div style={{display: 'flex', gap: 14, padding: '6px 0 12px'}}>
          <Btn label="Decline" ghost />
          <Btn label="Sign in" at={at} done="✓ Sign in" />
        </div>
      </Card>
    </Scene>
  );
};

const OwnId: React.FC = () => {
  return (
    <Scene
      title="A different ID at every service."
      beats={[
        {at: 10, text: 'One person, three services, three IDs.'},
        {at: 86, text: 'So services can’t match their users.'},
      ]}
    >
      <Card title="The same person">
        <Row k="shop" v="4kS0…" />
        <Fade at={26} rise={6}><Row k="forum" v="9xT2…" /></Fade>
        <Fade at={48} rise={6}><Row k="game" v="p7Qm…" /></Fade>
      </Card>
    </Scene>
  );
};

const ReadValue: React.FC = () => {
  const f = useCurrentFrame();
  const change = 56;
  const revoke = 130;
  return (
    <Scene
      title="Read the current value."
      beats={[
        {at: 10, text: 'You keep a link to the entry, not the address.'},
        {at: change + 4, text: 'They change the entry, and the next read shows it.'},
        {at: revoke + 4, text: 'They revoke it, and the next read returns no values.'},
      ]}
    >
      <Card title="Deliver to" right={<Tag>{f >= revoke ? 'Revoked' : 'Active'}</Tag>}>
        <Row k="address" v={f >= change ? 'Hauptstraße 3, Köln' : 'Musterstraße 12, Berlin'} flash={prog(f, change, 6) * (1 - prog(f, change + 14, 30))} covered={prog(f, revoke, 14)} />
      </Card>
      <Code
        at={18}
        lines={f >= revoke ? ['POST /api/grants/resolve', '{ "status": "revoked" }'] : ['POST /api/grants/resolve', '{ "status": "active",', '  "values": { … } }']}
      />
    </Scene>
  );
};

/** ---------------- Share ---------------- */

const PickRecords: React.FC = () => (
  <Scene
    title="Pick what to share."
    beats={[
      {at: 10, text: 'Single records, or whole sections.'},
      {at: 92, text: 'The rest of your vault stays out of it.'},
    ]}
  >
    <Card title="Your vault">
      <Tick mono label="server_address" sub="ssh.example.com" on={28} />
      <Tick mono label="server_password" sub="••••••••••" on={48} />
      <Tick mono label="home_address" sub="Musterstraße 12, Berlin" />
    </Card>
  </Scene>
);

const WhoGetsIn: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <Scene
      title="Decide who gets in."
      beats={[
        {at: 10, text: 'Use any of these, in any combination.'},
        {at: 118, text: 'Your link is ready to copy or send.'},
      ]}
    >
      <Card title="Share link">
        <Tick label="Password" on={24} />
        <Tick label="Expiration date" sub={f >= 44 ? '2026-12-31' : undefined} on={44} />
        <Tick label="Maximum views" sub={f >= 64 ? '5' : undefined} on={64} />
        <Tick label="Require a verified viewer" />
      </Card>
      <LinkChip at={104} />
    </Scene>
  );
};

const ChangeOnce: React.FC = () => {
  const f = useCurrentFrame();
  const home = 44;
  const away = 74;
  return (
    <Scene title="Change a password." beats={[{at: 10, text: 'Everyone with the link sees the new one. You never send it again.'}]}>
      <Card title="Your vault">
        <Row k="password" v={f >= home ? 'tr4il-m0ss-92' : 'k1te-r1ver-07'} flash={prog(f, home, 6) * (1 - prog(f, home + 16, 30))} />
      </Card>
      <LinkChip at={-30} />
      <Card title="Contractor sees">
        <Row k="password" v={f >= away ? 'tr4il-m0ss-92' : 'k1te-r1ver-07'} flash={prog(f, away, 6) * (1 - prog(f, away + 16, 30))} />
      </Card>
    </Scene>
  );
};

const Page: React.FC<{mark: string; tag: string; at: number}> = ({mark, tag, at}) => {
  const f = useCurrentFrame();
  const wide = useWide();
  return (
    <Fade at={at - 10} style={{flex: wide ? 'none' : 1, width: wide ? 520 : '100%', minHeight: 0}}>
      <div style={{position: 'relative', overflow: 'hidden', height: wide ? 500 : 340, border: `2px solid ${INK}`, padding: 30, background: WHITE}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 14, fontSize: 36, fontWeight: 600}}>
          <FileText size={44} strokeWidth={1.8} /> contract.pdf
        </div>
        {[92, 70, 84, 60, 78, 66].map((w, i) => (
          <div key={i} style={{height: 16, width: `${w}%`, background: LINE, marginTop: 26}} />
        ))}
        <div
          style={{
            position: 'absolute',
            inset: '-40% -40%',
            display: 'grid',
            placeItems: 'center',
            transform: 'rotate(-24deg)',
            opacity: prog(f, at, 12) * 0.82,
            fontSize: 30,
            fontWeight: 600,
            lineHeight: 2.1,
            textAlign: 'center',
            whiteSpace: 'pre',
            color: GREY,
          }}
        >
          {Array(14).fill(`${mark} · 2026-11-01 · ${tag}`).join('\n')}
        </div>
      </div>
    </Fade>
  );
};

const Watermark: React.FC = () => (
  <Scene
    title="Watermark your files."
    beats={[
      {at: 10, text: 'Every image and PDF the link serves carries your text and a tag.'},
      {at: 92, text: 'So a leaked copy tells you which link it came through.'},
    ]}
  >
    <Page mark="For Northwind" tag="#a3f9c1" at={30} />
    <Page mark="For Contoso" tag="#7be014" at={52} />
  </Scene>
);

const RevokeShare: React.FC = () => {
  const f = useCurrentFrame();
  const at = 52;
  return (
    <Scene
      title="Revoke it."
      beats={[
        {at: 10, text: 'You’re done, so you end the link.'},
        {at: at + 22, text: 'It stops working the next time someone opens it. Not at the next sync.'},
      ]}
    >
      <Card title="Contractor" right={<Tag>{f >= at ? 'Revoked' : 'Active'}</Tag>}>
        <div style={{display: 'flex', padding: '8px 0 12px'}}>
          <Btn label="Revoke" at={at} done="Revoked" ghost />
        </div>
      </Card>
      <Card title="Contractor sees">
        <Row k="address" v="ssh.example.com" covered={prog(f, at + 2, 12)} />
        <Row k="password" v="tr4il-m0ss-92" covered={prog(f, at + 8, 12)} />
        <Fade at={at + 22} rise={6}>
          <div style={{borderTop: `2px solid ${LINE}`, padding: '14px 0 6px', fontSize: 36, fontWeight: 500}}>This link has been revoked.</div>
        </Fade>
      </Card>
    </Scene>
  );
};

/** ---------------- Collect ---------------- */

const AskRequest: React.FC = () => (
  <Scene
    title="Ask for what you need."
    beats={[
      {at: 10, text: 'Pick a template. Its fields are what people fill in.'},
      {at: 94, text: 'You get the link, and a short message to send with it.'},
    ]}
  >
    <Card title="Employee onboarding">
      <Row k="tax_id" v="Text" />
      <Row k="iban" v="Text" />
      <Row k="address" v="Text" />
    </Card>
    <LinkChip at={82} text="/r/onboarding" />
  </Scene>
);

const WhoIsAsking: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <Scene
      title="The app checks who is asking."
      beats={[
        {at: 10, text: 'They see the result before they answer.'},
        {at: 86, text: 'If the claim contradicts the domain, it’s blocked.'},
      ]}
    >
      <Card title="Request" right={<span style={{opacity: prog(f, 28, 10)}}><Tag>DNS verified</Tag></span>}>
        <Line left="employer.example" sub="Employee onboarding" />
      </Card>
      <Card title="Request" at={78} right={<span style={{opacity: prog(f, 92, 10)}}><Tag>Spoofed</Tag></span>}>
        <Line left="employer.example" sub="Blocked. It’s a fake." />
      </Card>
    </Scene>
  );
};

const AnswerFromVault: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <Scene
      title="They answer from their vault."
      beats={[
        {at: 10, text: 'For each field, they use a record.'},
        {at: 110, text: 'The answer stays theirs. They can take it back any time.'},
      ]}
    >
      <Card title="Use a record">
        <Row k="tax_id" v={f >= 34 ? '12 345 678 901' : '…'} />
        <Row k="iban" v={f >= 54 ? 'DE89 •••• 4821' : '…'} />
        <Row k="address" v={f >= 74 ? 'Musterstraße 12' : '…'} />
      </Card>
      <Card title="In their workspace" at={100}>
        <Line left="Employer" sub="tax_id, iban, address" right={<Tag>Active</Tag>} />
      </Card>
    </Scene>
  );
};

const Sheet: React.FC<{change: number; revoke: number}> = ({change, revoke}) => {
  const f = useCurrentFrame();
  const wide = useWide();
  const head: React.CSSProperties = {fontFamily: MONO, fontSize: 30, color: GREY, padding: '10px 0'};
  const rows = [
    {who: 'Ada', tax: '12 345 678 901', iban: f >= change ? 'DE12 •••• 7730' : 'DE89 •••• 4821', flash: prog(f, change, 6) * (1 - prog(f, change + 14, 30)), covered: 0, at: 16},
    {who: 'Ben', tax: '98 765 432 109', iban: 'DE44 •••• 1902', flash: 0, covered: prog(f, revoke, 14), at: 34},
    {who: 'Cem', tax: '45 678 123 450', iban: 'DE71 •••• 6655', flash: 0, covered: 0, at: 52},
  ];
  const cols = wide ? '180px 400px 400px 1fr' : '110px 1fr 300px';
  const size = wide ? 38 : 36;
  const Bar: React.FC<{v: string; c: number}> = ({v, c}) => (
    <span style={{position: 'relative', whiteSpace: 'nowrap'}}>
      {v}
      <span style={{position: 'absolute', left: -4, right: -4, top: 2, bottom: 2, background: INK, transform: `scaleX(${c})`, transformOrigin: 'left'}} />
    </span>
  );
  return (
    <div style={{width: wide ? 1300 : '100%', border: `2px solid ${INK}`, padding: wide ? '14px 30px' : '12px 22px'}}>
      <div style={{display: 'grid', gridTemplateColumns: cols, ...head}}>
        <span>name</span>
        <span>tax_id</span>
        <span>iban</span>
        {wide && <span />}
      </div>
      {rows.map((r) => (
        <Fade key={r.who} at={r.at} rise={6}>
          <div style={{display: 'grid', gridTemplateColumns: cols, alignItems: 'center', minHeight: 80, borderTop: `2px solid ${LINE}`, fontSize: size, fontWeight: 500, letterSpacing: '-0.015em', background: `rgba(10,10,10,${0.09 * r.flash})`}}>
            <span>{r.who}</span>
            <span><Bar v={r.tax} c={r.covered} /></span>
            <span><Bar v={r.iban} c={r.covered} /></span>
            {wide && <span style={{justifySelf: 'end'}}>{r.covered > 0 ? <Tag>Revoked</Tag> : null}</span>}
          </div>
        </Fade>
      ))}
    </div>
  );
};

const ReadAnswers: React.FC = () => (
  <Scene
    title="Read the answers."
    beats={[
      {at: 10, text: 'One row per person, one column per field.'},
      {at: 74, text: 'Someone changes a record, and you see the new value.'},
      {at: 150, text: 'Someone revokes their answer, and the value is gone.'},
    ]}
  >
    <Sheet change={84} revoke={160} />
  </Scene>
);

const Callback: React.FC = () => (
  <Scene
    title="Send them to your own system."
    beats={[{at: 10, text: 'A callback URL sends every answer as it arrives.'}]}
  >
    <Code
      at={22}
      lines={[
        'POST https://your-app.example/hook',
        '{',
        '  "slug": "onboarding",',
        '  "responseId": "9k2m…",',
        '  "data": { "tax_id": "12 345…" }',
        '}',
      ]}
    />
  </Scene>
);

/** ---------------- Prove ---------------- */

const ChainStep: React.FC<{title: string; sub: string; at: number}> = ({title, sub, at}) => {
  const f = useCurrentFrame();
  const on = prog(f, at, 10);
  const wide = useWide();
  return (
    <Fade at={at - 6} rise={6} style={{flex: 1, width: wide ? undefined : '100%', minWidth: 0}}>
      <div style={{border: `2px solid ${INK}`, padding: '24px 26px', background: on > 0.5 ? INK : WHITE, color: on > 0.5 ? WHITE : INK}}>
        <div style={{fontSize: 42, fontWeight: 600, letterSpacing: '-0.02em'}}>{title}</div>
        <div style={{fontFamily: MONO, fontSize: 30, opacity: 0.8, marginTop: 6}}>{sub}</div>
      </div>
    </Fade>
  );
};

const Chain: React.FC = () => (
  <Scene
    title="Tied to your domain."
    beats={[
      {at: 10, text: 'Your domain vouches for your server.'},
      {at: 62, text: 'Your server vouches for your identity.'},
      {at: 114, text: 'Your identity signs what you send.'},
    ]}
  >
    <ChainStep title="Domain" sub="_revoked.example.com" at={18} />
    <ChainStep title="Server" sub="example.com" at={44} />
    <ChainStep title="Identity" sub="Ada · 4f2a…" at={78} />
    <ChainStep title="Share" sub="/s/k7Qx…" at={124} />
  </Scene>
);

const Results: React.FC = () => (
  <Scene
    title="The app checks who sent it."
    beats={[{at: 10, text: 'You always see the result together with the reason.'}]}
  >
    <Card title="What the app does">
      <Line left={<Tag>DNS verified</Tag>} sub="Everything agrees. It lets you continue." at={18} />
      <Line left={<Tag>Not verified</Tag>} sub="Not proven, not forged. It asks you first." at={44} />
      <Line left={<Tag>Spoofed</Tag>} sub="The claim contradicts the domain. It blocks it." at={70} />
    </Card>
  </Scene>
);

const AcceptAttestation: React.FC = () => {
  const f = useCurrentFrame();
  const at = 96;
  return (
    <Scene
      title="Someone else confirms it."
      beats={[
        {at: 10, text: 'An attestation is something someone else confirms about you.'},
        {at: at + 14, text: 'You keep it, and you decide what to show.'},
      ]}
    >
      <Card title="Age check" right={f >= at ? <Tag>Verified</Tag> : undefined}>
        <div style={{fontFamily: MONO, fontSize: 32, color: GREY, padding: '0 0 12px'}}>verify.example</div>
        <Row k="age_over_18" v="Yes" />
        <Row k="birth_date" v="1991-03-14" />
        <div style={{display: 'flex', padding: '8px 0 12px'}}>
          <Btn label="Accept" at={at} done="Held" />
        </div>
      </Card>
    </Scene>
  );
};

const ShowDetails: React.FC = () => {
  const f = useCurrentFrame();
  const send = 100;
  return (
    <Scene
      title="Show only what they need."
      beats={[
        {at: 10, text: 'A service asks to see it. You tick the details.'},
        {at: send + 12, text: 'The service sees only what you ticked, and can check it.'},
      ]}
    >
      <Card title="shop.example asks">
        <Tick mono label="age_over_18" on={0} />
        <Tick mono label="birth_date" on={0} off={44} />
        <Tick mono label="address" on={0} off={66} />
      </Card>
      <Card title="shop.example sees" at={send - 6} right={<span style={{opacity: prog(f, send + 6, 10)}}><Tag>Verified</Tag></span>}>
        <Row k="age_over_18" v="Yes" />
        <Row k="birth_date" v="1991-03-14" covered={1} />
        <Row k="address" v="Musterstraße 12" covered={1} />
      </Card>
    </Scene>
  );
};

/** ---------------- Connect ---------------- */

const ToolAsks: React.FC = () => (
  <Scene
    title="A tool asks to connect."
    beats={[
      {at: 10, text: 'Any tool can pick its own name. Check the address.'},
      {at: 92, text: 'The tool and the app show the same code. Continue only if both match.'},
    ]}
  >
    <Card title="Guestbook">
      <Line left="Connect with Revoked" sub="tool.example" />
      <Fade at={84} rise={6}>
        <div style={{fontFamily: MONO, fontSize: 48, letterSpacing: '0.04em', padding: '16px 0 14px', borderTop: `2px solid ${LINE}`}}>83C-047</div>
      </Fade>
    </Card>
    <Card title="Guestbook wants to connect" at={26}>
      <Row k="address" v="tool.example" />
      <Row k="name" v="Guestbook" />
      <Fade at={92} rise={6}>
        <div style={{fontFamily: MONO, fontSize: 48, letterSpacing: '0.04em', padding: '16px 0 14px', borderTop: `2px solid ${LINE}`}}>83C-047</div>
      </Fade>
    </Card>
  </Scene>
);

const Never: React.FC<{label: string}> = ({label}) => (
  <div style={{display: 'flex', gap: 20, alignItems: 'center', padding: '14px 0', borderTop: `2px solid ${LINE}`, fontSize: 36, fontWeight: 500, letterSpacing: '-0.015em', lineHeight: 1.2}}>
    <X size={40} strokeWidth={2.5} style={{flex: 'none'}} /> {label}
  </div>
);

const ToolPermissions: React.FC = () => {
  const at = 136;
  return (
    <Scene
      title="You decide what it can do."
      beats={[
        {at: 10, text: 'Each of these is your choice, per tool.'},
        {at: 76, text: 'Some things it can never do.'},
        {at: at + 6, text: 'Nothing is shared until you approve it.'},
      ]}
    >
      <Card title="You decide">
        <Tick label="Revoke links it proposed" sub="It can’t create links or see what they contain." on={34} />
        <Tick label="Receive the links it proposed" />
      </Card>
      <Card title="Guestbook can never" at={70}>
        <Never label="Read your vault, your other links or your account" />
        <div style={{display: 'flex', padding: '10px 0 12px'}}>
          <Btn label="Connect" at={at} done="✓ Connected" />
        </div>
      </Card>
    </Scene>
  );
};

const ToolSees: React.FC = () => (
  <Scene
    title="It sees what became of its links."
    beats={[
      {at: 10, text: 'Their status and how often they were opened.'},
      {at: 84, text: 'It never sees what they contain.'},
    ]}
  >
    <Card title="Guestbook sees">
      <Line left="Wi-Fi for guests" sub="Opened 12 times" right={<Tag>Active</Tag>} at={14} />
      <Line left="Door code" sub="Opened 3 times" right={<Tag>Paused</Tag>} at={34} />
      <Fade at={78} rise={6}>
        <Row k="values" v="nothing to see here" covered={1} />
      </Fade>
    </Card>
  </Scene>
);

const StayInCharge: React.FC = () => {
  const f = useCurrentFrame();
  const at = 96;
  return (
    <Scene
      title="Disconnect any time."
      beats={[
        {at: 10, text: 'A connection lasts 90 days from the last time you confirmed it.'},
        {at: at + 8, text: 'Disconnect, and the tool is cut off at once. The links keep working.'},
      ]}
    >
      <Card title="Connected tools">
        <Line left="Guestbook" sub="tool.example" right={<Tag>{f >= at ? 'Disconnected' : 'Connected'}</Tag>} />
        <div style={{display: 'flex', padding: '8px 0 12px'}}>
          <Btn label="Disconnect" at={at} done="Disconnected" ghost />
        </div>
      </Card>
      <Card title="Its links">
        <Line left="Wi-Fi for guests" right={<Tag>Active</Tag>} />
        <Line left="Door code" right={<Tag>Active</Tag>} />
      </Card>
    </Scene>
  );
};

/** ---------------- The films ---------------- */

type FilmScene = {id: string; frames: number; C: React.FC};

const title = (t: string, line: string): FilmScene => ({id: 'title', frames: 84, C: () => <TitleCard title={t} line={line} />});
const close = (t: string, url: string): FilmScene => ({id: 'close', frames: 84, C: () => <CloseCard title={t} url={url} />});

export const FEATURE_FILMS: Record<string, FilmScene[]> = {
  SignIn: [
    title('Sign in with Revoked', 'People sign in with their Revoked account. You keep no passwords.'),
    {id: 'button', frames: 150, C: AddButton},
    {id: 'approve', frames: 210, C: ApproveSignIn},
    {id: 'id', frames: 165, C: OwnId},
    {id: 'read', frames: 210, C: ReadValue},
    close('Add it to your service.', 'docs.revoked.link/api/sign-in'),
  ],
  Share: [
    title('Share', 'A share is a link to records in your vault.'),
    {id: 'pick', frames: 165, C: PickRecords},
    {id: 'who', frames: 180, C: WhoGetsIn},
    {id: 'change', frames: 150, C: ChangeOnce},
    {id: 'watermark', frames: 165, C: Watermark},
    {id: 'revoke', frames: 180, C: RevokeShare},
    close('Share your first record.', 'docs.revoked.link/guide/sharing'),
  ],
  Collect: [
    title('Collect', 'A request asks other people for information.'),
    {id: 'ask', frames: 165, C: AskRequest},
    {id: 'check', frames: 165, C: WhoIsAsking},
    {id: 'answer', frames: 180, C: AnswerFromVault},
    {id: 'read', frames: 240, C: ReadAnswers},
    {id: 'callback', frames: 120, C: Callback},
    close('Ask for what you need.', 'docs.revoked.link/guide/requests'),
  ],
  Prove: [
    title('Prove', 'Check who sent it, and what others confirm.'),
    {id: 'chain', frames: 180, C: Chain},
    {id: 'results', frames: 150, C: Results},
    {id: 'attestation', frames: 180, C: AcceptAttestation},
    {id: 'show', frames: 195, C: ShowDetails},
    close('Check who sent something.', 'docs.revoked.link/guide/identities'),
  ],
  Connect: [
    title('Connect', 'Let a tool see what became of the links it proposed.'),
    {id: 'asks', frames: 180, C: ToolAsks},
    {id: 'permissions', frames: 195, C: ToolPermissions},
    {id: 'sees', frames: 150, C: ToolSees},
    {id: 'charge', frames: 180, C: StayInCharge},
    close('Connect a tool.', 'docs.revoked.link/guide/tools'),
  ],
};

export const filmFrames = (name: string) =>
  FEATURE_FILMS[name].reduce((a, s) => a + s.frames, 0) - FADE * (FEATURE_FILMS[name].length - 1);

export const Film: React.FC<{name: string}> = ({name}) => (
  <AbsoluteFill style={{background: SOFT}}>
    <Fonts />
    <TransitionSeries>
      {FEATURE_FILMS[name].flatMap(({id, frames, C}, i) => [
        <TransitionSeries.Sequence key={id} durationInFrames={frames} name={id}>
          <C />
        </TransitionSeries.Sequence>,
        ...(i < FEATURE_FILMS[name].length - 1
          ? [<TransitionSeries.Transition key={`${id}-t`} presentation={fade()} timing={linearTiming({durationInFrames: FADE})} />]
          : []),
      ])}
    </TransitionSeries>
  </AbsoluteFill>
);
