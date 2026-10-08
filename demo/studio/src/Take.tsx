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
	return (
		<AbsoluteFill style={{isolation: 'isolate'}}>
			{states.map((state, i) => (
				<Window
					key={i}
					timeline={timeline}
					state={state}
					trimBefore={Math.round(start * fps)}
					style={samples > 1 ? {opacity: 1 / samples, mixBlendMode: 'plus-lighter'} : undefined}
				/>
			))}
		</AbsoluteFill>
	);
};

const Window: React.FC<{
	timeline: Timeline;
	state: CameraState;
	trimBefore: number;
	style?: React.CSSProperties;
}> = ({timeline, state, trimBefore, style}) => {
	const {width, height} = useVideoConfig();
	const mask = `url(${takeFile(timeline, timeline.mask)})`;
	const shape: React.CSSProperties = {
		position: 'absolute',
		inset: 0,
		maskImage: mask,
		maskSize: '100% 100%',
		WebkitMaskImage: mask,
		WebkitMaskSize: '100% 100%',
	};
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
			{/* Filters go on a wrapper: CSS masks after filtering, which would clip the shadows to the window. */}
			<div style={{position: 'absolute', inset: 0, opacity: 0.55, filter: 'blur(36px)', transform: 'translateY(28px)'}}>
				<div style={{...shape, background: 'black'}} />
			</div>
			<div style={{position: 'absolute', inset: 0, opacity: 0.35, filter: 'blur(6px)', transform: 'translateY(3px)'}}>
				<div style={{...shape, background: 'black'}} />
			</div>
			{/* The hairline rim macOS draws around windows, which keeps a dark one apart from the dark backdrop. */}
			<div style={{position: 'absolute', inset: 0, filter: 'drop-shadow(0 0 0.8px rgba(255,255,255,0.5))'}}>
				<div style={{...shape, background: 'black'}} />
			</div>
			<OffthreadVideo
				src={takeFile(timeline, timeline.video)}
				trimBefore={trimBefore}
				muted
				style={{...shape, width: '100%', height: '100%'}}
			/>
		</div>
	);
};
