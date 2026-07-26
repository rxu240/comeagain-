"""The eight delivery dimensions.

Each dimension is a pure function over a frame window plus a `DeliveryPass`
walker that carries it across the segment graph. Adding a ninth dimension is a
function and a four-line walker - no pipeline to edit, which is the whole point
of scoring on a graph instead of in a loop.

Windows are frame ranges on the 10 ms grid from `dsp`, so a "segment" and "the
whole take" run through identical code; only the phrasing differs.
"""

import numpy as np;
import math;
import from engine.dsp {
    HOP_S, FrameData, speech_mask, runs_of, syllable_nuclei, hz_to_semitones
}
import from engine.model {
    Take, Segment, Reading, Covers, Scores, Rates,
    DimensionReport, MetricPoint, Moment, DIMENSION_NAMES, DIMENSION_BLURBS
}
import from engine.scoring {
    Target, band_score, band_side, band_of, clamp,
    fmt_time, fmt1, fmt0, fmt_pct, blend, r1, r2
}


"""Everything derived once per take and shared by every pass."""
obj TakeContext {
    has fd: FrameData,
        speech: np.ndarray,
        voiced_speech: np.ndarray,
        f0_st: np.ndarray,
        nuclei: list[int] = [],
        prom: list[float] = [],
        pauses: list[tuple[int, int]] = [],
        f0_ref: float = 120.0,
        total_frames: int = 0;
}

"""A frame range with the slices every dimension reads."""
obj Window {
    has db: np.ndarray,
        f0_st: np.ndarray,
        voiced: np.ndarray,
        speech: np.ndarray,
        hf: np.ndarray,
        flux: np.ndarray,
        lo: int = 0,
        hi: int = 0,
        nuclei: list[int] = [],
        prom: list[float] = [],
        dur: float = 0.0,
        phonation: float = 0.0,
        trail: float = 0.0;
}

"""A dimension verdict plus any timestamped moments it produced."""
obj DimResult {
    has report: DimensionReport = DimensionReport(),
        moments: list[Moment] = [];
}


# --- Context ---------------------------------------------------------------

"""Compute the shared per-take context: masks, nuclei, prominence, pauses."""
def build_context(fd: FrameData) -> TakeContext {
    speech = speech_mask(fd);
    voiced_speech = np.logical_and(fd.voiced, speech);
    nuclei = syllable_nuclei(fd, voiced_speech);

    voiced_f0 = fd.f0[np.greater(fd.f0, 0.0)];
    f0_ref = float(np.median(voiced_f0)) if len(voiced_f0) > 0 else 120.0;
    if f0_ref <= 0.0 { f0_ref = 120.0; }
    f0_st = np.where(np.greater(fd.f0, 0.0), hz_to_semitones(fd.f0, f0_ref), 0.0);

    prom = nucleus_prominence(fd, f0_st, nuclei);
    pauses = runs_of(np.logical_not(speech));

    return TakeContext(
        fd=fd, speech=speech, voiced_speech=voiced_speech, f0_st=f0_st,
        nuclei=nuclei, prom=prom, pauses=pauses, f0_ref=f0_ref,
        total_frames=fd.n_frames
    );
}


"""Prominence z-score per syllable nucleus: loudness, pitch and peak width."""
def nucleus_prominence(fd: FrameData, f0_st: np.ndarray, nuclei: list[int]) -> list[float] {
    if len(nuclei) == 0 { return []; }
    idx = np.array(nuclei);
    db_at = fd.db[idx];
    f0_at = f0_st[idx];

    db_mean = float(np.mean(db_at));
    db_sd = max(float(np.std(db_at)), 0.5);
    f0_mean = float(np.mean(f0_at));
    f0_sd = max(float(np.std(f0_at)), 0.5);

    out: list[float] = [];
    for i in range(len(nuclei)) {
        z_db = (float(db_at[i]) - db_mean) / db_sd;
        z_f0 = (float(f0_at[i]) - f0_mean) / f0_sd;
        out.append(0.6 * z_db + 0.4 * z_f0);
    }
    return out;
}


"""Slice the context down to one frame range.

`trail` is the silence in seconds that follows this window inside the take:
zero for the whole take, the gap to the next utterance for a segment.
"""
def window_of(ctx: TakeContext, lo: int, hi: int, trail: float) -> Window {
    fd = ctx.fd;
    hi = min(hi, fd.n_frames);
    lo = max(0, min(lo, hi));

    nuc: list[int] = [];
    pr: list[float] = [];
    for i in range(len(ctx.nuclei)) {
        p = ctx.nuclei[i];
        if p >= lo and p < hi {
            nuc.append(p);
            pr.append(ctx.prom[i]);
        }
    }

    sp = ctx.speech[lo:hi];
    return Window(
        db=fd.db[lo:hi],
        f0_st=ctx.f0_st[lo:hi],
        voiced=ctx.voiced_speech[lo:hi],
        speech=sp,
        hf=fd.hf_ratio[lo:hi],
        flux=fd.flux[lo:hi],
        lo=lo, hi=hi, nuclei=nuc, prom=pr,
        dur=float(hi - lo) * HOP_S,
        phonation=float(int(np.count_nonzero(sp))) * HOP_S,
        trail=trail
    );
}


"""Assemble a DimensionReport without repeating the boilerplate eight times."""
def make_report(
    key: str, score: float, headline: str, detail: str, metrics: list[MetricPoint]
) -> DimensionReport {
    return DimensionReport(
        key=key,
        name=DIMENSION_NAMES[key],
        blurb=DIMENSION_BLURBS[key],
        score=r1(score),
        band=band_of(score),
        headline=headline,
        detail=detail,
        metrics=metrics
    );
}


"""Voiced semitone values inside a window, as a plain array."""
def voiced_st(w: Window) -> np.ndarray {
    return w.f0_st[np.logical_and(w.voiced, np.not_equal(w.f0_st, 0.0))];
}


# --- Dimensions ------------------------------------------------------------

"""Pitch: where the voice sits and how far it travels, in semitones."""
def dim_pitch(ctx: TakeContext, w: Window, _whole: bool) -> DimResult {
    st = voiced_st(w);
    if len(st) < 8 {
        return DimResult(report=make_report(
            "pitch", 50.0, "Not enough voiced audio",
            "There was too little voiced speech here to read pitch reliably.", []
        ));
    }

    lo_p = float(np.percentile(st, 10.0));
    hi_p = float(np.percentile(st, 90.0));
    span = hi_p - lo_p;
    centre_hz = ctx.f0_ref * math.pow(2.0, float(np.median(st)) / 12.0);

    target = Target(lo_fail=0.5, lo_ideal=4.0, hi_ideal=12.0, hi_fail=22.0);
    score = band_score(span, target);
    side = band_side(span, target);

    headline = "Pitch travels well";
    detail = "Your pitch spans " + fmt1(span) + " semitones, which is the range listeners hear as engaged without being theatrical.";
    if side < 0 {
        headline = "Narrow pitch range";
        detail = "Your pitch only moves " + fmt1(span) + " semitones. Under about four, a listener starts hearing the delivery as flat no matter how good the words are.";
    } elif side > 0 {
        headline = "Very wide pitch swings";
        detail = "Your pitch swings " + fmt1(span) + " semitones. That much movement can read as performed rather than sincere.";
    }

    metrics = [
        MetricPoint(label="Centre", value=fmt0(centre_hz) + " Hz"),
        MetricPoint(label="Span", value=fmt1(span) + " st"),
        MetricPoint(label="Variation", value=fmt1(float(np.std(st))) + " st")
    ];
    return DimResult(report=make_report("pitch", score, headline, detail, metrics));
}


"""Intonation: phrase melody and how each phrase resolves."""
def dim_intonation(_ctx: TakeContext, w: Window, whole: bool) -> DimResult {
    st = voiced_st(w);
    if len(st) < 8 {
        return DimResult(report=make_report(
            "intonation", 50.0, "Not enough voiced audio",
            "Too little voiced speech here to trace a melody.", []
        ));
    }

    slope = terminal_slope(w);
    variability = float(np.std(st));

    rise_target = Target(lo_fail=-14.0, lo_ideal=-8.0, hi_ideal=-0.5, hi_fail=8.0);
    score = band_score(slope, rise_target);
    var_bonus = clamp((variability - 1.0) * 8.0, -12.0, 8.0);
    score = clamp(score + var_bonus, 8.0, 100.0);

    headline = "Phrases resolve downward";
    detail = "Your phrase endings fall by " + fmt1(abs(slope)) + " semitones, which is what makes a statement sound settled.";
    moments: list[Moment] = [];

    if slope > 1.5 {
        headline = "Statements ending on a rise";
        detail = "Phrase endings rise " + fmt1(slope) + " semitones. Rising terminals on statements (uptalk) read as asking for approval rather than stating a position.";
        if not whole {
            moments.append(Moment(
                t=r2(float(w.hi) * HOP_S - 0.4),
                tEnd=r2(float(w.hi) * HOP_S),
                dimension="intonation", severity="watch",
                note="Ends on a rise - land this one flat or falling."
            ));
        }
    } elif abs(slope) < 0.5 and variability < 1.2 {
        headline = "Melody staying flat";
        detail = "Phrase endings neither rise nor fall and the melody moves only " + fmt1(variability) + " semitones. Flat terminals make consecutive sentences blur together.";
    }

    metrics = [
        MetricPoint(label="Terminal", value=fmt1(slope) + " st"),
        MetricPoint(label="Melody", value=fmt1(variability) + " st"),
        MetricPoint(label="Shape", value="rising" if slope > 0.75 else ("falling" if slope < -0.75 else "level"))
    ];
    return DimResult(
        report=make_report("intonation", score, headline, detail, metrics),
        moments=moments
    );
}


"""Semitones-per-second slope over the last 400 ms of voiced speech.

Anchored on the last voiced frame rather than the window edge: a window that
trails off into silence still has a phrase ending, it just lands earlier.
"""
def terminal_slope(w: Window) -> float {
    n = int(len(w.f0_st));
    if n < 10 { return 0.0; }

    last = -1;
    for i in range(n - 1, -1, -1) {
        if bool(w.voiced[i]) and float(w.f0_st[i]) != 0.0 { last = i; break; }
    }
    if last < 4 { return 0.0; }

    tail_lo = max(0, last - 40);
    xs: list[float] = [];
    ys: list[float] = [];
    for i in range(tail_lo, last + 1) {
        if bool(w.voiced[i]) and float(w.f0_st[i]) != 0.0 {
            xs.append(float(i) * HOP_S);
            ys.append(float(w.f0_st[i]));
        }
    }
    if len(xs) < 4 { return 0.0; }
    coef = np.polyfit(np.array(xs), np.array(ys), 1);
    return clamp(float(coef[0]) * 0.4, -20.0, 20.0);
}


"""Pacing: syllables per second while actually speaking."""
def dim_pacing(_ctx: TakeContext, w: Window, whole: bool) -> DimResult {
    phon = max(w.phonation, 0.2);
    rate = float(len(w.nuclei)) / phon;
    wpm = rate * 60.0 / 1.5;

    target = Target(lo_fail=1.2, lo_ideal=3.4, hi_ideal=5.2, hi_fail=8.5);
    score = band_score(rate, target);
    side = band_side(rate, target);

    headline = "Pace sits in the comfortable band";
    detail = "You are running " + fmt1(rate) + " syllables per second, roughly " + fmt0(wpm) + " words per minute - fast enough to hold attention, slow enough to follow.";
    moments: list[Moment] = [];

    if side < 0 {
        headline = "Slower than conversational";
        detail = "At " + fmt1(rate) + " syllables per second (about " + fmt0(wpm) + " wpm) the delivery drags. Listeners start filling the gaps with their own thoughts.";
    } elif side > 0 {
        headline = "Running fast";
        detail = "At " + fmt1(rate) + " syllables per second (about " + fmt0(wpm) + " wpm) you are outpacing comfortable listening. Consonants are usually the first thing to go.";
        if not whole {
            moments.append(Moment(
                t=r2(float(w.lo) * HOP_S),
                tEnd=r2(float(w.hi) * HOP_S),
                dimension="pacing", severity="watch",
                note="Rushed stretch - " + fmt1(rate) + " syll/sec."
            ));
        }
    }

    metrics = [
        MetricPoint(label="Rate", value=fmt1(rate) + " syll/s"),
        MetricPoint(label="Approx.", value=fmt0(wpm) + " wpm"),
        MetricPoint(label="Syllables", value=str(len(w.nuclei)))
    ];
    return DimResult(
        report=make_report("pacing", score, headline, detail, metrics),
        moments=moments
    );
}


"""Pausing for one utterance, judged on the gap it lands into."""
def segment_pausing(w: Window, inner: list[tuple[int, int]], moments: list[Moment]) -> DimResult {
    target = Target(lo_fail=0.0, lo_ideal=0.18, hi_ideal=1.0, hi_fail=2.6);
    score = band_score(w.trail, target);
    side = band_side(w.trail, target);
    at = r2(float(w.hi) * HOP_S);

    headline = "Lands with room";
    detail = "You leave " + fmt1(w.trail) + "s after this line - enough for it to register before the next one starts.";

    if side < 0 {
        headline = "No landing room";
        detail = "Only " + fmt1(w.trail) + "s of silence follows this line. Running straight into the next sentence denies this one its moment.";
        moments.append(Moment(
            t=at, tEnd=r2(at + w.trail), dimension="pausing", severity="note",
            note="Runs straight into the next line."
        ));
    } elif side > 0 {
        headline = "Long gap after this line";
        detail = fmt1(w.trail) + "s of silence follows. Past about a second a listener reads the gap as hesitation rather than emphasis.";
        moments.append(Moment(
            t=at, tEnd=r2(at + w.trail), dimension="pausing", severity="watch",
            note=fmt1(w.trail) + "s gap - long enough that attention drifts."
        ));
    }

    metrics = [
        MetricPoint(label="Gap after", value=fmt1(w.trail) + "s"),
        MetricPoint(label="Within", value=str(len(inner))),
        MetricPoint(label="Speaking", value=fmt1(w.phonation) + "s")
    ];
    return DimResult(
        report=make_report("pausing", score, headline, detail, metrics),
        moments=moments
    );
}


"""Pausing: how much silence there is and whether it lands well.

Take-level and segment-level ask different questions. Over a whole take the
number that matters is the share of time spent in silence. A segment, though,
is *bounded* by pauses by construction, so scoring its internal silence would
mark every utterance down; what matters there is the gap it lands into.
"""
def dim_pausing(_ctx: TakeContext, w: Window, whole: bool) -> DimResult {
    inner = runs_of(np.logical_not(w.speech));
    kept: list[tuple[int, int]] = [];
    for (s, e) in inner {
        # Ignore the silence that tops and tails a window - it is not a pause.
        if s == 0 or e >= int(len(w.speech)) { continue; }
        if (e - s) >= 18 { kept.append((s, e)); }
    }

    pause_frames = 0;
    longest = 0;
    for (s, e) in kept {
        pause_frames += (e - s);
        if (e - s) > longest { longest = e - s; }
    }

    dur = max(w.dur, 0.2);
    ratio = float(pause_frames) * HOP_S / dur;
    mean_pause = (float(pause_frames) * HOP_S / float(len(kept))) if len(kept) > 0 else 0.0;
    moments: list[Moment] = [];

    if not whole {
        return segment_pausing(w, kept, moments);
    }

    target = Target(lo_fail=0.0, lo_ideal=0.08, hi_ideal=0.30, hi_fail=0.60);
    score = band_score(ratio, target);
    side = band_side(ratio, target);

    headline = "Pauses are doing their job";
    detail = "Silence accounts for " + fmt_pct(ratio) + " of this take across " + str(len(kept)) + " pauses averaging " + fmt1(mean_pause) + "s, which gives ideas room to land.";

    if side < 0 {
        headline = "Almost no room to breathe";
        detail = "Only " + fmt_pct(ratio) + " of this take is silence. Without pauses, listeners get no boundary between one idea and the next.";
    } elif side > 0 {
        headline = "Silence is dominating";
        detail = "Silence accounts for " + fmt_pct(ratio) + " of this take. Long gaps read as hesitation rather than emphasis.";
    }

    for (s, e) in kept {
        secs = float(e - s) * HOP_S;
        if secs >= 1.1 {
            moments.append(Moment(
                t=r2(float(w.lo + s) * HOP_S),
                tEnd=r2(float(w.lo + e) * HOP_S),
                dimension="pausing",
                severity="watch" if secs >= 1.8 else "note",
                note=fmt1(secs) + "s gap - long enough that attention drifts."
            ));
        }
    }

    metrics = [
        MetricPoint(label="Silence", value=fmt_pct(ratio)),
        MetricPoint(label="Pauses", value=str(len(kept))),
        MetricPoint(label="Longest", value=fmt1(float(longest) * HOP_S) + "s")
    ];
    return DimResult(
        report=make_report("pausing", score, headline, detail, metrics),
        moments=moments
    );
}


"""Volume: level, dynamic range, and whether lines hold to the end."""
def dim_volume(_ctx: TakeContext, w: Window, whole: bool) -> DimResult {
    sp = w.db[w.speech];
    if len(sp) < 5 {
        return DimResult(report=make_report(
            "volume", 50.0, "Not enough speech",
            "Too little speech in this window to measure level.", []
        ));
    }

    mean_db = float(np.mean(sp));
    p10 = float(np.percentile(sp, 10.0));
    p90 = float(np.percentile(sp, 90.0));
    rng = p90 - p10;

    target = Target(lo_fail=1.0, lo_ideal=6.0, hi_ideal=18.0, hi_fail=32.0);
    score = band_score(rng, target);
    side = band_side(rng, target);

    headline = "Level is well controlled";
    detail = "Your loudness moves across " + fmt1(rng) + " dB - enough shading to mark what matters without the listener reaching for the volume.";
    moments: list[Moment] = [];

    if side < 0 {
        headline = "Level barely moves";
        detail = "Loudness varies only " + fmt1(rng) + " dB. A near-constant level gives the listener no cue about which words carry the weight.";
    } elif side > 0 {
        headline = "Level swings hard";
        detail = "Loudness swings " + fmt1(rng) + " dB. The quiet parts risk being lost in any room with background noise.";
    }

    # Trailing off: the tail of a phrase dropping well under its own body.
    n = int(len(w.db));
    if n > 40 and not whole {
        cut = int(float(n) * 0.75);
        body = w.db[0:cut][w.speech[0:cut]];
        tail = w.db[cut:n][w.speech[cut:n]];
        if len(body) > 3 and len(tail) > 3 {
            drop = float(np.mean(body)) - float(np.mean(tail));
            if drop > 7.0 {
                score = clamp(score - 14.0, 8.0, 100.0);
                headline = "Trailing off at the end";
                detail = "This line drops " + fmt1(drop) + " dB by its final quarter. The last few words are where the point usually lives.";
                moments.append(Moment(
                    t=r2(float(w.lo + cut) * HOP_S),
                    tEnd=r2(float(w.hi) * HOP_S),
                    dimension="volume", severity="watch",
                    note="Drops " + fmt1(drop) + " dB - carry the line to the end."
                ));
            }
        }
    }

    metrics = [
        MetricPoint(label="Level", value=fmt1(mean_db) + " dB"),
        MetricPoint(label="Range", value=fmt1(rng) + " dB"),
        MetricPoint(label="Floor", value=fmt1(p10) + " dB")
    ];
    return DimResult(
        report=make_report("volume", score, headline, detail, metrics),
        moments=moments
    );
}


"""Stress: which syllables carry weight, and how regular the beat is."""
def dim_stress(_ctx: TakeContext, w: Window, _whole: bool) -> DimResult {
    if len(w.nuclei) < 4 {
        return DimResult(report=make_report(
            "stress", 50.0, "Not enough syllables",
            "This stretch is too short to read a stress pattern.", []
        ));
    }

    stressed: list[int] = [];
    for i in range(len(w.nuclei)) {
        if w.prom[i] > 0.55 { stressed.append(w.nuclei[i]); }
    }
    ratio = float(len(stressed)) / float(len(w.nuclei));

    target = Target(lo_fail=0.0, lo_ideal=0.16, hi_ideal=0.42, hi_fail=0.75);
    score = band_score(ratio, target);
    side = band_side(ratio, target);

    regularity = 0.0;
    if len(stressed) >= 3 {
        gaps = np.diff(np.array(stressed).astype(np.float32));
        mean_gap = float(np.mean(gaps));
        if mean_gap > 0.0 {
            cv = float(np.std(gaps)) / mean_gap;
            regularity = clamp(1.0 - cv, 0.0, 1.0);
        }
    }

    headline = "Emphasis is landing";
    detail = fmt_pct(ratio) + " of your syllables carry real emphasis, which is enough to shape meaning without hammering every word.";
    if side < 0 {
        headline = "Emphasis is too even";
        detail = "Only " + fmt_pct(ratio) + " of syllables stand out. When every syllable weighs the same, the listener has to work out the point unaided.";
    } elif side > 0 {
        headline = "Too many words stressed";
        detail = fmt_pct(ratio) + " of syllables are emphasised. Stressing everything is the same as stressing nothing.";
    }

    metrics = [
        MetricPoint(label="Stressed", value=fmt_pct(ratio)),
        MetricPoint(label="Beats", value=str(len(stressed))),
        MetricPoint(label="Regularity", value=fmt_pct(regularity))
    ];
    return DimResult(report=make_report("stress", score, headline, detail, metrics));
}


"""Articulation: consonant crispness via high-frequency energy."""
def dim_articulation(_ctx: TakeContext, w: Window, whole: bool) -> DimResult {
    sp_hf = w.hf[w.speech];
    sp_flux = w.flux[w.speech];
    if len(sp_hf) < 5 {
        return DimResult(report=make_report(
            "articulation", 50.0, "Not enough speech",
            "Too little speech in this window to judge articulation.", []
        ));
    }

    hf = float(np.mean(sp_hf));
    flux = float(np.mean(sp_flux));

    target = Target(lo_fail=0.02, lo_ideal=0.18, hi_ideal=0.48, hi_fail=0.80);
    score = band_score(hf, target);
    side = band_side(hf, target);

    headline = "Consonants are landing clean";
    detail = "High-frequency energy sits at " + fmt_pct(hf) + " of the speech band, the signature of consonants that actually reach the listener.";
    moments: list[Moment] = [];

    if side < 0 {
        headline = "Consonants softening";
        detail = "Only " + fmt_pct(hf) + " of your energy is in the consonant band. Word endings are the first casualty, and listeners start guessing.";
        if not whole {
            moments.append(Moment(
                t=r2(float(w.lo) * HOP_S),
                tEnd=r2(float(w.hi) * HOP_S),
                dimension="articulation", severity="watch",
                note="Softened consonants through this line."
            ));
        }
    } elif side > 0 {
        headline = "Very sharp edges";
        detail = "High-frequency energy is at " + fmt_pct(hf) + ". Sibilance this strong can get fatiguing over a long talk.";
    }

    metrics = [
        MetricPoint(label="Clarity", value=fmt_pct(hf)),
        MetricPoint(label="Movement", value=fmt1(flux * 1000.0)),
        MetricPoint(label="Voiced", value=fmt_pct(float(int(np.count_nonzero(w.voiced))) / max(float(len(w.voiced)), 1.0)))
    ];
    return DimResult(
        report=make_report("articulation", score, headline, detail, metrics),
        moments=moments
    );
}


"""Tone: the composite colour a listener reads off everything above."""
def dim_tone(_ctx: TakeContext, _w: Window, others: list[DimensionReport]) -> DimResult {
    by_key: dict[str, float] = {};
    for r in others { by_key[r.key] = r.score; }

    score = blend(
        [
            by_key.get("intonation", 50.0), by_key.get("volume", 50.0),
            by_key.get("pacing", 50.0), by_key.get("stress", 50.0),
            by_key.get("pitch", 50.0), by_key.get("articulation", 50.0),
            by_key.get("pausing", 50.0)
        ],
        [1.4, 1.2, 1.1, 1.0, 0.9, 0.9, 0.8]
    );

    warm = by_key.get("pitch", 50.0) >= 65.0 and by_key.get("volume", 50.0) >= 60.0;
    settled = by_key.get("intonation", 50.0) >= 65.0 and by_key.get("pausing", 50.0) >= 60.0;
    rushed = by_key.get("pacing", 50.0) < 55.0 and by_key.get("pausing", 50.0) < 60.0;
    flat = by_key.get("pitch", 50.0) < 55.0 and by_key.get("stress", 50.0) < 60.0;
    muffled = by_key.get("articulation", 50.0) < 55.0;

    headline = "Measured and clear";
    detail = "Nothing in the delivery is fighting the message.";
    if rushed and flat {
        headline = "Rushed and flat";
        detail = "Speed is up and the melody is narrow at the same time. Together those read as nerves, even when the content is confident.";
    } elif rushed {
        headline = "Urgent";
        detail = "Pace and short pauses give this real momentum. Useful for a close, expensive over a whole talk.";
    } elif flat {
        headline = "Level and under-coloured";
        detail = "Steady, but the narrow pitch and even stress leave a listener without much to hold on to.";
    } elif muffled {
        headline = "Warm but indistinct";
        detail = "The shape of the delivery is good; the consonants are what is holding it back.";
    } elif warm and settled {
        headline = "Warm and grounded";
        detail = "Open pitch, controlled level and phrases that resolve - this is the register people describe as authoritative.";
    } elif settled {
        headline = "Composed";
        detail = "Phrases resolve and pauses are doing real work. The delivery sounds deliberate.";
    }

    metrics = [
        MetricPoint(label="Read", value=headline.lower()),
        MetricPoint(label="Strongest", value=strongest(others)),
        MetricPoint(label="Weakest", value=weakest(others))
    ];
    return DimResult(report=make_report("tone", score, headline, detail, metrics));
}


"""Name of the highest-scoring dimension."""
def strongest(reports: list[DimensionReport]) -> str {
    best = "";
    top = -1.0;
    for r in reports {
        if r.score > top { top = r.score; best = r.name; }
    }
    return best if best != "" else "-";
}


"""Name of the lowest-scoring dimension."""
def weakest(reports: list[DimensionReport]) -> str {
    worst = "";
    low = 999.0;
    for r in reports {
        if r.score < low { low = r.score; worst = r.name; }
    }
    return worst if worst != "" else "-";
}


"""All eight dimensions over one window, ordered with tone first."""
obj WindowScore {
    has dimensions: list[DimensionReport] = [],
        moments: list[Moment] = [],
        overall: float = 0.0;
}


"""Run every dimension over one window and fold the results together."""
def score_window(ctx: TakeContext, w: Window, whole: bool) -> WindowScore {
    results = [
        dim_pitch(ctx, w, whole),
        dim_intonation(ctx, w, whole),
        dim_pacing(ctx, w, whole),
        dim_pausing(ctx, w, whole),
        dim_volume(ctx, w, whole),
        dim_stress(ctx, w, whole),
        dim_articulation(ctx, w, whole)
    ];

    reports: list[DimensionReport] = [];
    moments: list[Moment] = [];
    for r in results {
        reports.append(r.report);
        moments += r.moments;
    }

    tone = dim_tone(ctx, w, reports);
    moments += tone.moments;

    return WindowScore(
        dimensions=[tone.report] + reports,
        moments=moments,
        overall=r1(tone.report.score)
    );
}
