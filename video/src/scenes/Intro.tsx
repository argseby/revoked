import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {Mark} from '../components/chips';
import {C, FONT, mix, prog} from '../theme';

export const Intro: React.FC<{tagline?: React.ReactNode; sub?: React.ReactNode}> = ({
  tagline = 'Share a reference to your data — not a copy.',
  sub,
}) => {
  const f = useCurrentFrame();
  const slide = prog(f, 26, 28);
  const word = prog(f, 34, 24);
  const tag = prog(f, 56, 24);
  const subP = prog(f, 72, 24);
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', fontFamily: FONT}}>
      <div style={{display: 'flex', alignItems: 'center', gap: mix(0, 36, slide)}}>
        <Mark size={220} at={4} />
        <div
          style={{
            width: mix(0, 560, slide),
            overflow: 'hidden',
            fontSize: 150,
            fontWeight: 780,
            letterSpacing: '-0.05em',
            color: C.ink,
            opacity: word,
            transform: `translateX(${(1 - word) * -30}px)`,
            whiteSpace: 'nowrap',
          }}
        >
          revoked
        </div>
      </div>
      <div
        style={{
          marginTop: 30,
          fontSize: 44,
          fontWeight: 560,
          letterSpacing: '-0.02em',
          color: C.muted,
          opacity: tag,
          transform: `translateY(${(1 - tag) * 16}px)`,
        }}
      >
        {tagline}
      </div>
      {sub && (
        <div
          style={{
            marginTop: 26,
            fontSize: 28,
            color: C.brand,
            fontWeight: 650,
            opacity: subP,
          }}
        >
          {sub}
        </div>
      )}
    </AbsoluteFill>
  );
};
