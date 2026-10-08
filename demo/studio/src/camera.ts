import {Easing, spring} from 'remotion';
import {type At, type Rect, type Timeline, marker, resolveAt} from './timeline';

/**
 * A camera move, keyed to the take: at `at`, the camera starts moving to
 * frame `frame` (the window, a marker's rect, markers' rects together, or a
 * rect in window points) so it fills `fill` of the picture, tilted by `tilt`
 * degrees (x, y, z).
 */
export type Shot = {
	at: At;
	frame?: 'window' | string | string[] | Rect;
	fill?: number;
	/** Shifts what's framed, in window points. */
	offset?: [number, number];
	tilt?: [number, number, number?];
	/** Seconds the move takes. */
	duration?: number;
	ease?: Ease;
	/** A slow push in once the move settles: how much closer each second. */
	drift?: number;
};

export type Ease = 'smooth' | 'gentle' | 'crash' | 'whip' | 'spring' | 'linear';

/** What the camera sees: window point (x, y) at the picture's center, `scale` pixels to a point. */
export type CameraState = {x: number; y: number; scale: number; rx: number; ry: number; rz: number};

type ResolvedShot = {start: number; duration: number; target: CameraState; ease: Ease; drift: number};

const easings: Record<Exclude<Ease, 'spring'>, (t: number) => number> = {
	smooth: Easing.bezier(0.45, 0, 0.2, 1),
	gentle: Easing.bezier(0.37, 0, 0.63, 1),
	crash: Easing.bezier(0.8, 0, 0.1, 1),
	whip: Easing.bezier(0.9, 0, 0.1, 1),
	linear: (t) => t,
};

const ease = (kind: Ease, t: number, duration: number) => {
	if (kind === 'spring') {
		return spring({
			frame: t * duration * 60,
			fps: 60,
			config: {damping: 16, mass: 0.9, stiffness: 120},
			durationInFrames: duration * 60,
		});
	}
	return easings[kind](t);
};

export const resolveShots = (
	timeline: Timeline,
	shots: Shot[],
	picture: {width: number; height: number},
): ResolvedShot[] =>
	shots
		.map((shot) => {
			const rect =
				shot.frame === undefined || shot.frame === 'window'
					? timeline.window
					: typeof shot.frame === 'string'
						? marker(timeline, shot.frame).rect
						: Array.isArray(shot.frame)
							? union(shot.frame.map((name) => marker(timeline, name).rect))
							: shot.frame;
			const fill = shot.fill ?? (shot.frame === undefined || shot.frame === 'window' ? 0.82 : 0.7);
			const scale = Math.min(
				(picture.width * fill) / Math.max(rect.width, 1),
				(picture.height * fill) / Math.max(rect.height, 1),
			);
			return {
				start: resolveAt(timeline, shot.at),
				duration: shot.duration ?? 0.9,
				ease: shot.ease ?? 'smooth',
				drift: shot.drift ?? 0,
				target: {
					x: rect.x + rect.width / 2 + (shot.offset?.[0] ?? 0),
					y: rect.y + rect.height / 2 + (shot.offset?.[1] ?? 0),
					scale,
					rx: shot.tilt?.[0] ?? 0,
					ry: shot.tilt?.[1] ?? 0,
					rz: shot.tilt?.[2] ?? 0,
				},
			};
		})
		.sort((a, b) => a.start - b.start);

const union = (rects: Rect[]): Rect => {
	const x = Math.min(...rects.map((r) => r.x));
	const y = Math.min(...rects.map((r) => r.y));
	return {
		x,
		y,
		width: Math.max(...rects.map((r) => r.x + r.width)) - x,
		height: Math.max(...rects.map((r) => r.y + r.height)) - y,
	};
};

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/**
 * Between two views, zooms about the one point that stays put on screen, so
 * a crash zoom heads straight for what it frames instead of swinging past it.
 */
const between = (from: CameraState, to: CameraState, t: number): CameraState => {
	const scale = Math.exp(lerp(Math.log(from.scale), Math.log(to.scale), t));
	const tilt = {rx: lerp(from.rx, to.rx, t), ry: lerp(from.ry, to.ry, t), rz: lerp(from.rz, to.rz, t)};
	if (Math.abs(to.scale / from.scale - 1) < 0.05) {
		return {x: lerp(from.x, to.x, t), y: lerp(from.y, to.y, t), scale, ...tilt};
	}
	const fixed = (a: number, b: number) => (to.scale * b - from.scale * a) / (to.scale - from.scale);
	const fx = fixed(from.x, to.x);
	const fy = fixed(from.y, to.y);
	const k = from.scale / scale;
	return {x: fx - k * (fx - from.x), y: fy - k * (fy - from.y), scale, ...tilt};
};

const drifted = (state: CameraState, drift: number, seconds: number): CameraState =>
	drift === 0 ? state : {...state, scale: state.scale * Math.pow(1 + drift, Math.max(0, seconds))};

/** Where the camera is at take time `t`. The first shot is where it starts. */
export const cameraAt = (shots: ResolvedShot[], t: number): CameraState => {
	let settled = shots[0].target;
	let settledAt = shots[0].start;
	let drift = shots[0].drift;
	for (const shot of shots.slice(1)) {
		if (t < shot.start) {
			break;
		}
		const from = drifted(settled, drift, shot.start - settledAt);
		const progress = (t - shot.start) / shot.duration;
		if (progress < 1) {
			return between(from, shot.target, ease(shot.ease, progress, shot.duration));
		}
		settled = shot.target;
		settledAt = shot.start + shot.duration;
		drift = shot.drift;
	}
	return drifted(settled, drift, t - settledAt);
};

/** The CSS transform that puts a window-sized element where `state` sees it. */
export const cameraTransform = (state: CameraState, picture: {width: number; height: number}) =>
	[
		`translate(${picture.width / 2}px, ${picture.height / 2}px)`,
		`perspective(${picture.width * 1.6}px)`,
		`rotateX(${state.rx}deg) rotateY(${state.ry}deg) rotateZ(${state.rz}deg)`,
		`scale(${state.scale})`,
		`translate(${-state.x}px, ${-state.y}px)`,
	].join(' ');

/** How far, in pixels, the window's corners move between two states (ignoring tilt). */
export const travel = (a: CameraState, b: CameraState, window: Rect) => {
	const corners = [
		[0, 0],
		[window.width, 0],
		[0, window.height],
		[window.width, window.height],
	];
	return Math.max(
		...corners.map(([x, y]) =>
			Math.hypot((x - a.x) * a.scale - (x - b.x) * b.scale, (y - a.y) * a.scale - (y - b.y) * b.scale),
		),
	);
};
