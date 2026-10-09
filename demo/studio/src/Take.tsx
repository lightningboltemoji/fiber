import React, {useMemo} from 'react';
import {AbsoluteFill, OffthreadVideo, getRemotionEnvironment, useCurrentFrame, useVideoConfig} from 'remotion';
import {type CameraState, type Shot, cameraAt, cameraTransform, resolveShots, travel} from './camera';
import {type At, type Timeline, resolveAt, takeFile} from './timeline';

/**
 * The take's window, where the camera sees it, from take time `from` on.
 * Fast moves are blurred as a real shutter would: the window is drawn at
 * several instants across `shutter` of a frame and averaged.
 */
export const Take: React.FC<{timeline: Timeline; shots: Shot[]; from?: At; shutter?: number}> = ({
	timeline,
	shots,
	from = 0,
	shutter = 0.5,
}) => {
	const frame = useCurrentFrame();
	const {fps, width, height} = useVideoConfig();
	const start = resolveAt(timeline, from);
	const resolved = useMemo(
		() => resolveShots(timeline, shots, {width, height}),
		[timeline, shots, width, height],
	);
	const t = start + frame / fps;
	const open = shutter / fps;
	const blurred = getRemotionEnvironment().isRendering;
	const samples = blurred
		? Math.min(24, Math.max(1, Math.ceil(travel(cameraAt(resolved, t - open / 2), cameraAt(resolved, t + open / 2), timeline.window) / 1.5)))
		: 1;
	const states =
		samples === 1
			? [cameraAt(resolved, t)]
			: Array.from({length: samples}, (_, i) => cameraAt(resolved, t - open / 2 + (open * (i + 0.5)) / samples));
	const trimBefore = Math.round(start * fps);
	return (
		<AbsoluteFill>
			{/* Soft already, so drawn once, where the camera is mid-shutter. */}
			<Shadow timeline={timeline} state={cameraAt(resolved, t)} />
			<AbsoluteFill style={{isolation: 'isolate'}}>
				{states.map((state, i) => (
					<Window
						key={i}
						timeline={timeline}
						state={state}
						trimBefore={trimBefore}
						style={samples > 1 ? {opacity: 1 / samples, mixBlendMode: 'plus-lighter'} : undefined}
					/>
				))}
			</AbsoluteFill>
		</AbsoluteFill>
	);
};

/** A window-sized box where the camera sees it. */
const Placed: React.FC<{
	timeline: Timeline;
	state: CameraState;
	style?: React.CSSProperties;
	children: React.ReactNode;
}> = ({timeline, state, style, children}) => {
	const {width, height} = useVideoConfig();
	return (
		<div
			style={{
				position: 'absolute',
				left: 0,
				top: 0,
				width: timeline.window.width,
				height: timeline.window.height,
				transformOrigin: '0 0',
				transform: cameraTransform(state, {width, height}),
				...style,
			}}
		>
			{children}
		</div>
	);
};

/** Fills the window's shape, from the take's mask. */
const windowShape = (timeline: Timeline): React.CSSProperties => {
	const mask = `url(${takeFile(timeline, timeline.mask)})`;
	return {
		position: 'absolute',
		inset: 0,
		maskImage: mask,
		maskSize: '100% 100%',
		WebkitMaskImage: mask,
		WebkitMaskSize: '100% 100%',
	};
};

const Shadow: React.FC<{timeline: Timeline; state: CameraState}> = ({timeline, state}) => (
	<Placed timeline={timeline} state={state}>
		{/* Filters go on a wrapper: CSS masks after filtering, which would clip the shadows to the window. */}
		<div style={{position: 'absolute', inset: 0, opacity: 0.55, filter: 'blur(36px)', transform: 'translateY(28px)'}}>
			<div style={{...windowShape(timeline), background: 'black'}} />
		</div>
		<div style={{position: 'absolute', inset: 0, opacity: 0.35, filter: 'blur(6px)', transform: 'translateY(3px)'}}>
			<div style={{...windowShape(timeline), background: 'black'}} />
		</div>
	</Placed>
);

const Window: React.FC<{
	timeline: Timeline;
	state: CameraState;
	trimBefore: number;
	style?: React.CSSProperties;
}> = ({timeline, state, trimBefore, style}) => (
	<Placed timeline={timeline} state={state} style={style}>
		{/* The hairline rim macOS draws around windows, which keeps a dark one apart from the dark backdrop. */}
		<div style={{position: 'absolute', inset: 0, filter: 'drop-shadow(0 0 0.8px rgba(255,255,255,0.5))'}}>
			<div style={{...windowShape(timeline), background: 'black'}} />
		</div>
		<OffthreadVideo
			src={takeFile(timeline, timeline.video)}
			trimBefore={trimBefore}
			muted
			style={{...windowShape(timeline), width: '100%', height: '100%'}}
		/>
	</Placed>
);
