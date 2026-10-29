import React from 'react';
import {Pause, Pencil, Ban} from 'lucide-react';
import {C, MONO} from '../theme';
import {Button, Card, Pill, type Tone} from './ui';

/** One of Mia's links as Mia's app lists it, with its own controls. */
export const LinkCard: React.FC<{
  x: number;
  y: number;
  w: number;
  at: number;
  title: React.ReactNode;
  sub: React.ReactNode;
  status: Tone;
  statusText: string;
  pressed?: number;
  update?: boolean;
  outline?: string;
  badge?: React.ReactNode;
}> = ({x, y, w, at, title, sub, status, statusText, pressed = 0, update = false, outline, badge}) => (
  <Card x={x} y={y} w={w} h={176} at={at} outline={outline}>
    <div style={{padding: '18px 22px 0'}}>
      <div style={{display: 'flex', alignItems: 'center', gap: 12}}>
        <span style={{fontSize: 26, fontWeight: 730, letterSpacing: '-0.02em', flex: 1}}>{title}</span>
        <Pill tone={status} dot size={18}>
          {statusText}
        </Pill>
      </div>
      <div style={{display: 'flex', alignItems: 'center', gap: 10, marginTop: 6, fontFamily: MONO, fontSize: 19, color: C.muted}}>
        {sub}
        {badge}
      </div>
      <div style={{display: 'flex', gap: 12, marginTop: 20}}>
        {update ? (
          <Button tone="quiet" icon={Pencil} size={20}>
            Update
          </Button>
        ) : (
          <Button tone="quiet" icon={Pause} size={20}>
            Pause
          </Button>
        )}
        <Button tone="danger" icon={Ban} size={20} pressed={pressed}>
          Revoke
        </Button>
      </div>
    </div>
  </Card>
);
