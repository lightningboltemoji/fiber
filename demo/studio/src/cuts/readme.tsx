import React from 'react';
import {AbsoluteFill, Sequence, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import {Backdrop} from '../Backdrop';
import {icon} from '../brand';
import type {Shot} from '../camera';
import {Caption} from '../Caption';
import type {Cut, CutProps} from '../cut';
import {Keys} from '../Keys';
import {Take} from '../Take';
import {type Timeline, resolveAt, type At} from '../timeline';
import {Title} from '../Title';

// The README's video, cut from demo/tapes/readme.tape's take.

/** Seconds of title before the take starts. */
const intro = 1.5;
/** Seconds of end card after the take. */
const outro = 2.2;

const shots: Shot[] = [
	// The window rises into place on a new tab.
	{at: 0, fill: 0.3, tilt: [30, -22, 6], offset: [0, 520]},
	{at: 0, duration: 1.6, ease: 'smooth', drift: 0.004},
	// Into the omnibar as it's typed in.
	{at: {marker: 'omnibar', offset: -0.2}, frame: ['omnibar', 'suggestions'], fill: 0.82, duration: 0.55, ease: 'crash', drift: 0.012},
	// Out to the page that opens.
	{at: {marker: 'wayfarer', offset: -0.3}, fill: 0.78, tilt: [10, -14, 1], duration: 1.1, ease: 'smooth', drift: 0.008},
	{at: {marker: 'wayfarer', offset: 1.4}, fill: 0.84, duration: 1.6, ease: 'gentle', drift: 0.006},
	// The site asks where you are.
	{at: {marker: 'prompt-title', offset: -0.1}, frame: ['prompt-title', 'prompt-buttons', 'prompt-never'], fill: 0.62, duration: 0.5, ease: 'crash', drift: 0.02},
	{at: {marker: 'prompt-never', offset: 2.55}, fill: 0.8, tilt: [0, 12, 0], duration: 0.8, ease: 'whip'},
	// ⌘S: the tabs and pins.
	{at: {marker: 'overlay', offset: -0.25}, frame: ['overlay', 'pins'], fill: 0.72, tilt: [12, -10, 0], duration: 0.6, ease: 'crash', drift: 0.012},
	// The pin opens.
	{at: {marker: 'hum', offset: -0.2}, fill: 0.78, tilt: [6, 16, -2], duration: 1.1, ease: 'smooth', drift: 0.01},
	// ⌘P finds the page that mentions it.
	{at: {marker: 'palette', offset: -0.15}, frame: ['palette', 'found'], fill: 0.8, duration: 0.5, ease: 'crash', drift: 0.015},
	{at: {marker: 'meridian', offset: -0.1}, fill: 0.82, duration: 0.9, ease: 'whip', drift: 0.006},
	// And away, below the end card.
	{at: {marker: 'end', offset: -2.4}, fill: 0.42, tilt: [26, -12, 4], offset: [0, -520], duration: 2.8, ease: 'gentle'},
];

const captions: {text: string; from: At; to: At}[] = [
	{text: 'Type a few letters. Find what you were reading.', from: {marker: 'omnibar', offset: 0.2}, to: {marker: 'wayfarer', offset: 0.2}},
	{text: 'Sites ask in a bubble, not a dialog.', from: 'prompt-title', to: {marker: 'prompt-never', offset: 2.4}},
	{text: '⌘S: every tab, and your pins.', from: 'overlay', to: {marker: 'hum', offset: -0.3}},
	{text: '⌘P finds pages by what’s on them.', from: 'palette', to: {marker: 'meridian', offset: 1}},
];

const ReadmeCut: React.FC<CutProps> = ({timelines}) => {
	const {fps} = useVideoConfig();
	const frame = useCurrentFrame();
	const take = timelines.readme;
	const frames = (seconds: number) => Math.round(seconds * fps);
	const span = (timeline: Timeline, from: At, to: At) => ({
		from: frames(intro + resolveAt(timeline, from)),
		durationInFrames: frames(resolveAt(timeline, to) - resolveAt(timeline, from)),
	});
	return (
		<AbsoluteFill>
			<Backdrop />
			<Sequence durationInFrames={frames(intro + 0.6)}>
				<Title text="Fiber" icon={icon} />
			</Sequence>
			<Sequence from={frames(intro)} durationInFrames={frames(take.duration)}>
				<AbsoluteFill
					style={{
						opacity: interpolate(frame / fps - intro, [take.duration - 1.2, take.duration], [1, 0], {
							extrapolateLeft: 'clamp',
							extrapolateRight: 'clamp',
						}),
					}}
				>
					<Take timeline={take} shots={shots} />
				</AbsoluteFill>
				<Keys timeline={take} />
			</Sequence>
			{captions.map((caption) => (
				<Sequence key={caption.text} {...span(take, caption.from, caption.to)}>
					<Caption text={caption.text} />
				</Sequence>
			))}
			<Sequence from={frames(intro + take.duration - 0.9)}>
				<Title text="Fiber" sub="A browser for macOS, built on Chromium." icon={icon} size={0.8} />
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
	duration: (timelines) => intro + timelines.readme.duration + outro,
	component: ReadmeCut,
};
