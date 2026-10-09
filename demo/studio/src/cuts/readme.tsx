import React from 'react';
import {AbsoluteFill, Sequence, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import {Backdrop} from '../Backdrop';
import type {Shot} from '../camera';
import type {Cut, CutProps} from '../cut';
import {Keys} from '../Keys';
import {Take} from '../Take';
import {type At, resolveAt} from '../timeline';

// The README's video, cut from demo/tapes/readme.tape's take. It loops, so it
// starts and ends on the bare backdrop. A shot only starts once the one
// before it has finished moving.

/** Where in the take the cut starts: just as the omnibar's typed in. */
const start: At = {marker: 'omnibar', offset: -0.4};
/** Seconds the window takes to fade in, and out at the take's end. */
const fadeIn = 0.4;
const fadeOut = 1.1;
/** Seconds of bare backdrop after the take, before the loop. */
const blank = 0.4;

const shots: Shot[] = [
	// In on the omnibar as it's typed in.
	{at: start, frame: ['omnibar', 'suggestions'], fill: 0.8, drift: 0.012},
	// Out to the results, then in on the one that gets clicked.
	{at: {marker: 'kestrel', offset: -0.2}, fill: 0.8, duration: 0.9, ease: 'smooth', drift: 0.006},
	{at: {marker: 'result', offset: -0.1}, frame: 'result', fill: 0.42, tilt: [2, -4, 0], duration: 0.8, ease: 'smooth', drift: 0.01},
	// The café map, which asks where he is in a bubble.
	{at: {marker: 'wayfarer', offset: -0.15}, fill: 0.8, duration: 1, ease: 'smooth', drift: 0.006},
	{at: {marker: 'prompt', offset: -0.05}, frame: ['prompt-title', 'prompt-buttons'], fill: 0.55, duration: 0.5, ease: 'crash', drift: 0.02},
	// Once allowed, the list and the map together: the nearest café rises to
	// the top as the map finds him round the corner from it.
	{at: 'allowed', fill: 0.86, duration: 1, ease: 'smooth', drift: 0.006},
	// ⌘S: the tabs and pins.
	{at: {marker: 'overlay', offset: -0.25}, frame: ['overlay', 'pins'], fill: 0.64, tilt: [10, -8, 0], duration: 0.6, ease: 'crash', drift: 0.012},
	// The mail pin, and Inês’s email.
	{at: {marker: 'mail', offset: -0.2}, fill: 0.8, duration: 0.9, ease: 'smooth'},
	{at: {marker: 'message', offset: 0.1}, frame: ['message', 'draft'], fill: 0.6, duration: 1, ease: 'smooth', drift: 0.01},
	{at: {marker: 'draft', offset: 0.1}, frame: 'draft', fill: 0.62, duration: 0.8, ease: 'smooth', drift: 0.01},
	// Out to the window for ⌘P, then in on the address it finds, once the
	// results have settled.
	{at: {marker: 'palette', offset: -1.15}, fill: 0.8, duration: 0.8, ease: 'smooth'},
	{at: {marker: 'found', offset: -0.4}, frame: ['palette', 'found'], fill: 0.75, duration: 0.7, ease: 'smooth', drift: 0.015},
	{at: {marker: 'casa', offset: -0.15}, fill: 0.8, duration: 0.7, ease: 'whip'},
	{at: {marker: 'address', offset: -0.1}, frame: 'address', fill: 0.5, duration: 0.9, ease: 'smooth', drift: 0.015},
	// Over to the window's edge as the picker opens.
	{at: {marker: 'picker', offset: -1}, frame: 'picker', fill: 0.7, tilt: [0, -12, 0], duration: 0.8, ease: 'smooth'},
	// Back in the reply for the paste, and the reply as it's sent.
	{at: {marker: 'back', offset: -0.15}, frame: 'draft', fill: 0.62, tilt: [0, 6, 0], duration: 0.8, ease: 'smooth', drift: 0.01},
	{at: {marker: 'sent', offset: -0.3}, frame: ['message', 'sent'], fill: 0.62, duration: 1, ease: 'smooth', drift: 0.006},
	// And away as the window fades.
	{at: {marker: 'end', offset: -1.4}, fill: 0.66, duration: 2, ease: 'gentle'},
];

const ReadmeCut: React.FC<CutProps> = ({timelines}) => {
	const {fps} = useVideoConfig();
	const frame = useCurrentFrame();
	const take = timelines.readme;
	const from = resolveAt(take, start);
	const t = from + frame / fps;
	return (
		<AbsoluteFill>
			<Backdrop loop />
			<Sequence durationInFrames={Math.round((take.duration - from) * fps)}>
				<AbsoluteFill
					style={{
						opacity: interpolate(t, [from, from + fadeIn, take.duration - fadeOut, take.duration], [0, 1, 1, 0], {
							extrapolateLeft: 'clamp',
							extrapolateRight: 'clamp',
						}),
					}}
				>
					<Take timeline={take} shots={shots} from={start} />
				</AbsoluteFill>
				<Keys timeline={take} from={start} />
			</Sequence>
		</AbsoluteFill>
	);
};

export const readme: Cut = {
	id: 'readme',
	tapes: ['readme'],
	width: 1920,
	height: 1080,
	fps: 60,
	duration: (timelines) => timelines.readme.duration - resolveAt(timelines.readme, start) + blank,
	component: ReadmeCut,
};
