import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';

/** A line naming what's on screen, in the top left. Put it in a Sequence: it fills the Sequence's length. */
export const Caption: React.FC<{text: string}> = ({text}) => {
	const frame = useCurrentFrame();
	const {fps, durationInFrames, height} = useVideoConfig();
	const t = frame / fps;
	const end = durationInFrames / fps;
	const p = interpolate(t, [0, 0.5, end - 0.4, end], [0, 1, 1, 0], {
		extrapolateLeft: 'clamp',
		extrapolateRight: 'clamp',
	});
	return (
		<AbsoluteFill style={{pointerEvents: 'none'}}>
			<div
				style={{
					position: 'absolute',
					left: height * 0.06,
					top: height * 0.055,
					padding: `${height * 0.014}px ${height * 0.026}px`,
					borderRadius: height * 0.05,
					background: 'rgba(24,24,28,0.62)',
					border: '1px solid rgba(255,255,255,0.14)',
					boxShadow: '0 16px 40px rgba(0,0,0,0.35)',
					backdropFilter: 'blur(30px) saturate(1.5)',
					fontFamily: 'system-ui',
					fontSize: height * 0.034,
					fontWeight: 600,
					letterSpacing: '-0.015em',
					color: 'white',
					opacity: p,
					filter: `blur(${(1 - p) * 12}px)`,
					transform: `translateX(${(1 - p) * -height * 0.012}px)`,
				}}
			>
				{text}
			</div>
		</AbsoluteFill>
	);
};
