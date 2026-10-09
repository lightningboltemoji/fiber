import React from 'react';
import {AbsoluteFill, useCurrentFrame, useVideoConfig} from 'remotion';

/**
 * Near black, with slow glows drifting behind the window. For a cut that
 * `loop`s, they drift whole turns, so the last frame leads into the first.
 */
export const Backdrop: React.FC<{hues?: [number, number, number]; loop?: boolean}> = ({
	hues = [215, 265, 25],
	loop = false,
}) => {
	const frame = useCurrentFrame();
	const {fps, width, height, durationInFrames} = useVideoConfig();
	const t = frame / fps;
	const length = durationInFrames / fps;
	/** Radians a second. */
	const speed = (rate: number) =>
		loop ? (2 * Math.PI * Math.max(1, Math.round((length * rate) / (2 * Math.PI)))) / length : rate;
	const glow = (hue: number, x: number, y: number, phase: number, alpha: number) => {
		const cx = width * (x + 0.06 * Math.sin(t * speed(0.21) + phase));
		const cy = height * (y + 0.05 * Math.cos(t * speed(0.17) + phase));
		return `radial-gradient(${width * 0.45}px ${height * 0.55}px at ${cx}px ${cy}px, hsla(${hue}, 70%, 45%, ${alpha}), transparent 70%)`;
	};
	return (
		<AbsoluteFill
			style={{
				background: [
					glow(hues[0], 0.25, 0.3, 0, 0.32),
					glow(hues[1], 0.78, 0.68, 2, 0.26),
					glow(hues[2], 0.55, 1.05, 4, 0.18),
					'radial-gradient(ellipse at 50% 45%, #15161b, #060607 75%)',
				].join(', '),
			}}
		/>
	);
};
