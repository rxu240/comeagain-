"""Cutting a take into utterances, and the data behind the prosody ribbon.

Segment boundaries are pauses: a run of speech, extended across any gap too
short to be a real pause, is one utterance. That is what makes per-segment
feedback line up with what a speaker actually experiences as "a line".
"""

import numpy as np;
import from engine.dsp { HOP_S }
import from engine.dimensions { TakeContext }
import from engine.scoring { r2 }

glob MERGE_GAP: int = 28;
glob MIN_SEGMENT: int = 30;
glob MAX_SEGMENT: int = 1400;
glob RIBBON_POINTS: int = 480;


"""Pitch, loudness and voicing resampled onto a fixed grid for the ribbon."""
obj Ribbon {
    has contour: list[float] = [],
        envelope: list[float] = [],
        voiced: list[int] = [],
        beats: list[float] = [];
}


"""Split the take into utterances: speech runs merged across short gaps."""
def segment_bounds(ctx: TakeContext) -> list[tuple[int, int]] {
    speech_runs: list[tuple[int, int]] = [];
    cursor = 0;
    for (s, e) in ctx.pauses {
        if s > cursor { speech_runs.append((cursor, s)); }
        cursor = e;
    }
    if cursor < ctx.total_frames { speech_runs.append((cursor, ctx.total_frames)); }

    merged: list[tuple[int, int]] = [];
    for (s, e) in speech_runs {
        if len(merged) > 0 and s - merged[-1][1] < MERGE_GAP {
            merged[-1] = (merged[-1][0], e);
            continue;
        }
        merged.append((s, e));
    }

    out: list[tuple[int, int]] = [];
    for (s, e) in merged {
        if (e - s) < MIN_SEGMENT { continue; }
        start = s;
        while (e - start) > MAX_SEGMENT {
            out.append((start, start + MAX_SEGMENT));
            start = start + MAX_SEGMENT;
        }
        out.append((start, e));
    }

    if len(out) == 0 and ctx.total_frames > 0 {
        out.append((0, ctx.total_frames));
    }
    return out;
}


"""Downsample pitch and loudness onto a fixed grid for the prosody ribbon."""
def ribbon(ctx: TakeContext) -> Ribbon {
    n = ctx.total_frames;
    if n == 0 { return Ribbon(); }

    buckets = min(RIBBON_POINTS, max(n, 1));
    fd = ctx.fd;
    floor = fd.speech_floor - 6.0;
    ceiling = max(float(np.percentile(fd.db, 98.0)), floor + 1.0);
    step = float(n) / float(buckets);

    out = Ribbon();
    for i in range(buckets) {
        lo = int(float(i) * step);
        hi = max(int(float(i + 1) * step), lo + 1);
        hi = min(hi, n);

        level = (float(np.max(fd.db[lo:hi])) - floor) / (ceiling - floor);
        out.envelope.append(r2(max(0.0, min(1.0, level))));

        vals = ctx.f0_st[lo:hi][ctx.voiced_speech[lo:hi]];
        if len(vals) > 0 {
            out.contour.append(r2(max(-14.0, min(14.0, float(np.median(vals))))));
            out.voiced.append(1);
        } else {
            out.contour.append(0.0);
            out.voiced.append(0);
        }
    }

    # Stressed syllables, so the ribbon can mark where the weight actually fell.
    for i in range(len(ctx.nuclei)) {
        if ctx.prom[i] > 0.55 {
            out.beats.append(r2(float(ctx.nuclei[i]) * HOP_S));
        }
    }
    return out;
}
