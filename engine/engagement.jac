"""Attention: how engaging this take would be to an audience, live.

Not one of the eight measured dimensions - a second-order read that combines
how varied the delivery sounds (a run of segments at almost the same speed or
pitch is the single biggest reason a listener's mind wanders) with how varied
the sentences themselves are. Mode only shifts which sound cues count for
more: a VC pitch reads engagement as gravitas, a first date reads the same
range as animation.
"""

import from engine.model { DimensionReport, SegmentReport }
import from engine.scoring { blend, clamp, r1 }


"""Longest run of consecutive values that each move less than `tol` from the
one before it - a monotone stretch, not a single flat pair."""
def longest_flat_run(values: list[float], tol: float) -> int {
    if len(values) < 2 { return 0; }
    best = 1;
    run = 1;
    for i in range(1, len(values)) {
        if abs(values[i] - values[i - 1]) <= tol { run += 1; }
        else { run = 1; }
        if run > best { best = run; }
    }
    return best;
}


"""0-100 points to shave for a run of `run` same-ish segments in a row.

Two in a row is normal speech - three or more is where real listeners start
describing a delivery as "the same the whole way through".
"""
def flatness_penalty(run: int) -> float {
    if run <= 2 { return 0.0; }
    return clamp(float(run - 2) * 12.0, 0.0, 45.0);
}


"""Share of consecutive segment pairs whose sentence form differs - a wall of
identical statement-statement-statement gives a listener nothing to react to."""
def kind_variety(segments: list[SegmentReport]) -> float {
    if len(segments) < 2 { return 1.0; }
    changes = 0;
    for i in range(1, len(segments)) {
        if segments[i].kind != segments[i - 1].kind { changes += 1; }
    }
    return float(changes) / float(len(segments) - 1);
}


"""Pull one dimension's score out of the report list, or a neutral default."""
def score_of(dims: list[DimensionReport], key: str) -> float {
    for d in dims {
        if d.key == key { return d.score; }
    }
    return 50.0;
}


"""Composite engagement score, headline and detail for a whole take."""
def attention_score(
    dims: list[DimensionReport], segments: list[SegmentReport], mode: str
) -> tuple[float, str, str] {
    rates: list[float] = [];
    pitches: list[float] = [];
    for s in segments {
        rates.append(s.rate);
        pitches.append(s.pitchSt);
    }

    pace_run = longest_flat_run(rates, 0.35);
    pitch_run = longest_flat_run(pitches, 1.2);
    penalty = max(flatness_penalty(pace_run), flatness_penalty(pitch_run));

    variety = kind_variety(segments);

    weights = [1.4, 1.2, 1.0, 1.0, 0.8] if mode == "vc" else [1.2, 0.9, 1.1, 1.3, 1.0];
    sound = blend(
        [
            score_of(dims, "intonation"), score_of(dims, "stress"),
            score_of(dims, "pacing"), score_of(dims, "pitch"),
            score_of(dims, "volume")
        ],
        weights
    );

    content = 55.0 + 45.0 * variety;
    score = clamp(blend([sound, content], [1.6, 1.0]) - penalty, 5.0, 100.0);

    headline = "";
    detail = "";
    if penalty >= 20.0 and pace_run >= pitch_run {
        headline = "Pacing holds steady too long";
        detail = str(pace_run) + " lines in a row move at almost the same speed. Even a small shift in rate is what keeps an audience tracking rather than tuning out.";
    } elif penalty >= 20.0 {
        headline = "Pitch holds steady too long";
        detail = str(pitch_run) + " lines in a row sit at almost the same pitch. Real engagement needs the melody to keep moving, not just the words.";
    } elif score >= 78.0 {
        headline = "Engaging throughout";
        detail = "Pacing and pitch keep moving and the sentence forms vary, which is what keeps a listener with you the whole way through.";
    } elif variety < 0.3 {
        headline = "Steady, but samey";
        detail = "Most lines share the same shape one after another. Mixing in a question, a shorter beat, or a longer pause gives a listener something to re-engage with.";
    } else {
        headline = "Holds attention reasonably well";
        detail = "Nothing here is actively losing the room, but there is room for more contrast from one line to the next.";
    }

    return (r1(score), headline, detail);
}
