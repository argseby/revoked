import React from 'react';
import {AbsoluteFill} from 'remotion';
import {TransitionSeries, linearTiming} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import {Ask, Close, Code, Copies, Fact, Open, Share, SignIn, TakeBack, Update} from './scenes';
import {Fonts, WHITE} from './ui';

const FADE = 12;

export const SHORT_SCENES: {id: string; frames: number; C: React.FC}[] = [
  {id: 'open', frames: 120, C: Open},
  {id: 'copies', frames: 210, C: Copies},
  {id: 'share', frames: 225, C: Share},
  {id: 'update', frames: 165, C: Update},
  {id: 'revoke', frames: 210, C: TakeBack},
  {id: 'ask', frames: 285, C: Ask},
  {id: 'fact', frames: 165, C: Fact},
  {id: 'sign-in', frames: 180, C: SignIn},
  {id: 'code', frames: 165, C: Code},
  {id: 'close', frames: 105, C: Close},
];

export const SHORT_TOTAL = SHORT_SCENES.reduce((a, s) => a + s.frames, 0) - FADE * (SHORT_SCENES.length - 1);

export const Short: React.FC = () => (
  <AbsoluteFill style={{background: WHITE}}>
    <Fonts />
    <TransitionSeries>
      {SHORT_SCENES.flatMap(({id, frames, C}, i) => [
        <TransitionSeries.Sequence key={id} durationInFrames={frames} name={id}>
          <C />
        </TransitionSeries.Sequence>,
        ...(i < SHORT_SCENES.length - 1
          ? [<TransitionSeries.Transition key={`${id}-t`} presentation={fade()} timing={linearTiming({durationInFrames: FADE})} />]
          : []),
      ])}
    </TransitionSeries>
  </AbsoluteFill>
);
