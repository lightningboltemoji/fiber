import React from 'react';
import {AbsoluteFill, Img, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';

/**
 * Words over the picture, focusing in and out of a blur. Put it in a
 * Sequence: it fills the Sequence's length.
 */
export const Title: React.FC<{
	text: string;
	sub?: string;
	icon?: string;
	align?: 'center' | 'top' | 'bottom';
	size?: number;
}> = ({text, sub, icon, align = 'center', size = 1}) => {
	const frame = useCurrentFrame();
	const {fps, durationInFrames, height} = useVideoConfig();
	const t = frame / fps;
	const end = durationInFrames / fps;
	const presence = (delay: number) =>
		interpolate(t, [delay, delay + 0.7, end - 0.45, end], [0, 1, 1, 0], {
			extrapolateLeft: 'clamp',
			extrapolateRight: 'clamp',
		});
	const layer = (delay: number): React.CSSProperties => {
		const p = presence(delay);
		return {
			opacity: p,
			filter: `blur(${(1 - p) * 18}px)`,
			transform: `translateY(${(1 - p) * height * 0.015}px) scale(${0.97 + p * 0.03})`,
		};
	};
	return (
		<AbsoluteFill
			style={{
				alignItems: 'center',
				justifyContent: align === 'center' ? 'center' : align === 'top' ? 'flex-start' : 'flex-end',
				padding: height * 0.1,
				gap: height * 0.025,
				color: 'white',
				fontFamily: 'system-ui',
				textAlign: 'center',
			}}
		>
			{icon ? <Img src={icon} style={{width: height * 0.2 * size, ...layer(0)}} /> : null}
			<div style={{fontSize: height * 0.085 * size, fontWeight: 650, letterSpacing: '-0.035em', ...layer(icon ? 0.12 : 0)}}>
				{text}
			</div>
			{sub ? (
				<div
					style={{
						fontSize: height * 0.032 * size,
						fontWeight: 450,
						color: 'rgba(255,255,255,0.62)',
						letterSpacing: '-0.01em',
						...layer(0.25),
					}}
				>
					{sub}
				</div>
			) : null}
		</AbsoluteFill>
	);
};
