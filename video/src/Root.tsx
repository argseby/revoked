import React from 'react';
import {AbsoluteFill, Composition, staticFile} from 'remotion';
import {TransitionSeries, linearTiming} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import {loadFont} from '@remotion/fonts';
import {Backdrop} from './components/chips';
import {FPS, HEIGHT, WIDTH} from './theme';
import {Intro} from './scenes/Intro';
import {Problem} from './scenes/Problem';
import {Cast} from './scenes/Cast';
import {VaultScene} from './scenes/VaultScene';
import {Share} from './scenes/Share';
import {Live} from './scenes/Live';
import {Revoke} from './scenes/Revoke';
import {Request} from './scenes/Request';
import {Attestation} from './scenes/Attestation';
import {Whole} from './scenes/Whole';
import {Outro} from './scenes/Outro';

loadFont({family: 'Inter', url: staticFile('InterVariable.ttf'), weight: '100 900'});
loadFont({family: 'Noto Sans Mono', url: staticFile('NotoSansMono-Regular.ttf')});

const FADE = 15;

export const SCENES: {id: string; frames: number; C: React.FC}[] = [
  {id: 'intro', frames: 150, C: Intro},
  {id: 'problem', frames: 300, C: Problem},
  {id: 'cast', frames: 210, C: Cast},
  {id: 'vault', frames: 390, C: VaultScene},
  {id: 'share', frames: 480, C: Share},
  {id: 'live', frames: 345, C: Live},
  {id: 'revoke', frames: 450, C: Revoke},
  {id: 'request', frames: 720, C: Request},
  {id: 'attestation', frames: 810, C: Attestation},
  {id: 'whole', frames: 450, C: Whole},
  {id: 'outro', frames: 180, C: Outro},
];

export const TOTAL = SCENES.reduce((a, s) => a + s.frames, 0) - FADE * (SCENES.length - 1);

const Explainer: React.FC = () => (
  <AbsoluteFill>
    <Backdrop />
    <TransitionSeries>
      {SCENES.flatMap(({id, frames, C}, i) => [
        <TransitionSeries.Sequence key={id} durationInFrames={frames} name={id}>
          <C />
        </TransitionSeries.Sequence>,
        ...(i < SCENES.length - 1
          ? [<TransitionSeries.Transition key={`${id}-t`} presentation={fade()} timing={linearTiming({durationInFrames: FADE})} />]
          : []),
      ])}
    </TransitionSeries>
  </AbsoluteFill>
);

export const Root: React.FC = () => (
  <>
    <Composition id="Explainer" component={Explainer} durationInFrames={TOTAL} fps={FPS} width={WIDTH} height={HEIGHT} />
    {SCENES.map(({id, frames, C}) => (
      <Composition
        key={id}
        id={`scene-${id}`}
        component={() => (
          <AbsoluteFill>
            <Backdrop />
            <C />
          </AbsoluteFill>
        )}
        durationInFrames={frames}
        fps={FPS}
        width={WIDTH}
        height={HEIGHT}
      />
    ))}
  </>
);
