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
	// Out to the results, then a little way in toward the one that gets
	// clicked, which stays where it is.
	{at: {marker: 'kestrel', offset: -0.2}, fill: 0.8, duration: 0.9, ease: 'smooth', drift: 0.006},
	{at: {marker: 'result', offset: -0.1}, frame: 'result', fill: 0.24, offset: [238, 125], duration: 0.8, ease: 'smooth', drift: 0.01},
	// Out to the café map as it loads, which asks where he is in a bubble.
	{at: {marker: 'wayfarer', offset: -0.1}, fill: 0.8, duration: 0.6, ease: 'smooth', drift: 0.006},
	{at: {marker: 'prompt', offset: -0.05}, frame: ['prompt-title', 'prompt-buttons'], fill: 0.55, duration: 0.5, ease: 'crash', drift: 0.02},
	// Once allowed, the list and the map together: the nearest café rises to
	// the top as the map finds him round the corner from it.
	{at: 'allowed', fill: 0.86, duration: 1, ease: 'smooth', drift: 0.006},
	// ⌘S: the tabs and pins.
	{at: {marker: 'overlay', offset: -0.25}, frame: ['overlay', 'pins'], fill: 0.64, duration: 0.6, ease: 'crash', drift: 0.012},
	// Across to Inês’s email as the mail pin opens, and there for the reply.
	// The window's as close as on the tabs, so it's a pan.
	{at: {marker: 'mail', offset: -0.2}, frame: ['subject', 'draft'], fill: 0.78, duration: 0.8, ease: 'smooth', drift: 0.006},
	// Across to ⌘P once its keys have shown over the reply, as close again,
	// then out to the page it finds and in on the address.
	{at: {marker: 'palette', offset: 0.1}, frame: ['palette', 'found'], fill: 0.63, duration: 0.7, ease: 'smooth', drift: 0.006},
	{at: {marker: 'casa', offset: -0.15}, fill: 0.8, duration: 0.7, ease: 'whip'},
	{at: {marker: 'address', offset: -0.1}, frame: 'address', fill: 0.5, duration: 0.9, ease: 'smooth', drift: 0.015},
	// ⌘S again, for the mail pin.
	{at: {marker: 'overlay-again', offset: -0.25}, frame: ['overlay-again', 'pins-again'], fill: 0.64, duration: 0.6, ease: 'crash', drift: 0.012},
	// Back to the reply, framed as before, for the paste and the send.
	{at: {marker: 'back', offset: -0.15}, frame: ['subject', 'draft'], fill: 0.78, duration: 0.8, ease: 'smooth', drift: 0.006},
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
				<Keys timeline={take} shots={shots} from={start} />
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
