import React from 'react';
import {AbsoluteFill} from 'remotion';
import {Arrow, Tag} from '../components/flow';
import {Caption, Person} from '../components/ui';
import {C} from '../theme';

const MIA = {x: 960, y: 830};
const OTHERS = [
  {kind: 'landlord' as const, x: 360, y: 540, need: 'rental documents'},
  {kind: 'employer' as const, x: 960, y: 450, need: 'tax ID and bank details'},
  {kind: 'advisor' as const, x: 1560, y: 540, need: 'tax records'},
];

export const Cast: React.FC = () => (
  <AbsoluteFill>
    <Caption
      kicker="Meet the people"
      title="One person. Three parties who need something."
      beats={[{at: 0, text: 'Mia is moving. A landlord, an employer and a tax advisor each need some of Mia’s data.'}]}
    />
    {OTHERS.map((o, i) => {
      const from = {x: o.x + (MIA.x - o.x) * 0.22, y: o.y + (o.kind === 'employer' ? 80 : 30)};
      const to = {x: MIA.x + (o.x - MIA.x) * 0.16, y: MIA.y - 80};
      return (
      <React.Fragment key={o.kind}>
        <Arrow
          id={`need-${i}`}
          from={from}
          to={to}
          bend={0}
          at={40 + i * 12}
          dur={26}
          color={C.border}
          width={3}
          head={false}
          live
        />
        <Tag x={(from.x + to.x) / 2} y={(from.y + to.y) / 2} at={56 + i * 12} color={C.onBrandTint} bg={C.brandTint}>
          {o.need}
        </Tag>
      </React.Fragment>
      );
    })}
    {OTHERS.map((o, i) => (
      <Person key={o.kind} kind={o.kind} x={o.x} y={o.y} at={14 + i * 8} size={104} label={o.kind === 'employer' ? 'right' : 'below'} />
    ))}
    <Person kind="mia" x={MIA.x} y={MIA.y} at={6} size={130} label="right" />
  </AbsoluteFill>
);
