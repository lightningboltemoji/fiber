import React from 'react';
import {AbsoluteFill, Sequence, useVideoConfig} from 'remotion';
import {Backdrop} from '../Backdrop';
import {icon} from '../brand';
import type {Cut, CutProps} from '../cut';
import {Keys} from '../Keys';
import {Take} from '../Take';
import {Title} from '../Title';

// Checks the studio end to end on the smoke tape's take.

const intro = 1.4;

const SmokeCut: React.FC<CutProps> = ({timelines}) => {
	const {fps} = useVideoConfig();
	const take = timelines.smoke;
	return (
		<AbsoluteFill>
			<Backdrop />
			<Sequence durationInFrames={Math.round(2 * fps)}>
				<Title text="Fiber" icon={icon} />
			</Sequence>
			<Sequence from={Math.round(intro * fps)}>
				<Take
					timeline={take}
					shots={[
						{at: 0, fill: 0.35, tilt: [24, -18, 4], offset: [0, 260]},
						{at: 0, duration: 1.3, ease: 'smooth', drift: 0.006},
						{at: {marker: 'omnibar', offset: -0.1}, frame: 'omnibar', fill: 0.8, duration: 0.5, ease: 'crash'},
						{at: {line: 12}, duration: 0.7, ease: 'whip', tilt: [6, -10, 0], fill: 0.72, drift: 0.01},
					]}
				/>
				<Keys timeline={take} />
			</Sequence>
		</AbsoluteFill>
	);
};

export const smoke: Cut = {
	id: 'smoke',
	tapes: ['smoke'],
	width: 1920,
	height: 1080,
	fps: 60,
	duration: (timelines) => intro + timelines.smoke.duration,
	component: SmokeCut,
};
