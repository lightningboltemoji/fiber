import {staticFile} from 'remotion';

// The director's timeline.json (demo/director/Sources/director/Timeline.swift).
// Times are seconds from the take's first frame; places are window points.

export type Rect = {x: number; y: number; width: number; height: number};

export type Timeline = {
	tape: string;
	video: string;
	mask: string;
	scale: number;
	window: Rect;
	fps: number;
	duration: number;
	markers: {name: string; time: number; rect: Rect}[];
	steps: {line: number; command: string; start: number; end: number}[];
	pointer: {time: number; x: number; y: number; pressed: boolean}[];
	keys: {time: number; keys: string}[];
};

export const loadTimeline = async (tape: string): Promise<Timeline> => {
	const response = await fetch(staticFile(`${tape}/timeline.json`));
	if (!response.ok) {
		throw new Error(`No take for ${tape}: record it with \`make demo-take TAPE=${tape}\``);
	}
	return response.json();
};

export const takeFile = (timeline: Timeline, file: string) =>
	staticFile(`${timeline.tape}/${file}`);

/**
 * A moment in a take: seconds, a marker's time, or a step's start (or end),
 * by the tape's line number, each with an optional offset in seconds.
 */
export type At =
	| number
	| string
	| {marker: string; offset?: number}
	| {line: number; edge?: 'start' | 'end'; offset?: number};

export const marker = (timeline: Timeline, name: string) => {
	const found = timeline.markers.find((m) => m.name === name);
	if (!found) {
		throw new Error(
			`The ${timeline.tape} take has no marker "${name}" (has: ${timeline.markers.map((m) => m.name).join(', ')})`,
		);
	}
	return found;
};

export const resolveAt = (timeline: Timeline, at: At): number => {
	if (typeof at === 'number') {
		return at;
	}
	if (typeof at === 'string') {
		return marker(timeline, at).time;
	}
	if ('marker' in at) {
		return marker(timeline, at.marker).time + (at.offset ?? 0);
	}
	const step = timeline.steps.find((s) => s.line === at.line);
	if (!step) {
		throw new Error(`The ${timeline.tape} take has no step on line ${at.line}`);
	}
	return (at.edge === 'end' ? step.end : step.start) + (at.offset ?? 0);
};
