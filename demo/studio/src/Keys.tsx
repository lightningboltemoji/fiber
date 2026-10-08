import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import {type At, type Timeline, resolveAt} from './timeline';

const symbols: Record<string, string> = {
	cmd: '⌘',
	shift: '⇧',
	option: '⌥',
	opt: '⌥',
	ctrl: '⌃',
	control: '⌃',
	return: 'return',
	enter: 'return',
	escape: 'esc',
	esc: 'esc',
	tab: 'tab',
	delete: 'delete',
	space: 'space',
	up: '↑',
	down: '↓',
	left: '←',
	right: '→',
};

/** The shortcuts pressed in the take, as keycaps along the bottom of the picture. */
export const Keys: React.FC<{timeline: Timeline; from?: At; hold?: number}> = ({timeline, from = 0, hold = 1.1}) => {
	const frame = useCurrentFrame();
	const {fps, height} = useVideoConfig();
	const t = resolveAt(timeline, from) + frame / fps;
	const shown = timeline.keys.filter((k) => k.time <= t && t < k.time + hold).at(-1);
	if (!shown) {
		return null;
	}
	const age = t - shown.time;
	const opacity = interpolate(age, [0, 0.1, hold - 0.25, hold], [0, 1, 1, 0], {
		extrapolateLeft: 'clamp',
		extrapolateRight: 'clamp',
	});
	const scale = interpolate(age, [0, 0.14], [0.92, 1], {extrapolateRight: 'clamp'});
	const caps = shown.keys.split('+').map((part) => symbols[part] ?? part.toUpperCase());
	const size = height / 24;
	return (
		<AbsoluteFill style={{justifyContent: 'flex-end', alignItems: 'center', paddingBottom: height * 0.07}}>
			<div style={{display: 'flex', gap: size * 0.3, opacity, transform: `scale(${scale})`}}>
				{caps.map((cap, i) => (
					<div
						key={i}
						style={{
							minWidth: size * 1.7,
							height: size * 1.7,
							padding: `0 ${size * 0.45}px`,
							borderRadius: size * 0.42,
							display: 'flex',
							alignItems: 'center',
							justifyContent: 'center',
							fontFamily: 'system-ui',
							fontWeight: 500,
							fontSize: cap.length > 1 ? size * 0.62 : size * 0.85,
							color: 'rgba(255,255,255,0.96)',
							background: 'linear-gradient(180deg, rgba(58,58,64,0.72), rgba(28,28,32,0.78))',
							border: '1px solid rgba(255,255,255,0.16)',
							boxShadow: '0 12px 34px rgba(0,0,0,0.4), inset 0 1px 0 rgba(255,255,255,0.18)',
							backdropFilter: 'blur(24px) saturate(1.4)',
						}}
					>
						{cap}
					</div>
				))}
			</div>
		</AbsoluteFill>
	);
};
