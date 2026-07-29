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
    DimensionReport, MetricPoint, Moment, DIMENSION_NAMES, DIMENSION_BLURBS,
    Transcript, Utterance
}
import from engine.asr { best_utterance }
import from engine.stress { emphasis_range, placement }
import from engine.scoring {
    Target, band_score, band_side, band_of, clamp,
    fmt_time, fmt1, fmt0, fmt_pct, blend, r1, r2
}


# How far back from the last voiced frame the terminal contour is measured.
# 45 frames on the 10 ms grid is 450 ms - about the final stressed syllable plus
# whatever follows it, which is where English puts its boundary tone.
glob TERMINAL_FRAMES: int = 45;

# Autocorrelation pitch tracking fails on fricatives and on the low-energy decay
# at the end of a phrase, and it fails *confidently*: the final "s" of
# "sign-ups?" came back as a run of 250-380 Hz frames from a speaker whose median
# is 85 Hz, which drove that phrase's terminal reading to the +15 st clamp. Two
# gates catch it. Nothing more than an octave from the speaker's own median is a
# plausible pitch for that speaker, and nothing 25 dB below the phrase's own peak
# is still the phrase.
glob MAX_F0_DEVIATION: float = 12.0;
glob RELIABLE_DB_DROP: float = 25.0;


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
        total_frames: int = 0,
        transcript: Transcript = Transcript(),
        bounds: list[tuple[int, int]] = [];
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
        trail: float = 0.0,
        text: str = "",
        kind: str = "",
        expects: str = "";
}

"""A dimension verdict plus any timestamped moments it produced."""
obj DimResult {
    has report: DimensionReport = DimensionReport(),
        moments: list[Moment] = [];
}


# --- Context ---------------------------------------------------------------

"""Compute the shared per-take context: masks, nuclei, prominence, pauses.

`tr` is optional so the DSP smoke tests can build a context without loading a
recogniser; every dimension still scores without it, only the ones that need
words go quiet.
"""
def build_context(fd: FrameData, tr: Transcript = Transcript()) -> TakeContext {
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
        total_frames=fd.n_frames, transcript=tr
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

    # The sentence this window mostly covers, if there is a transcript. It is
    # what tells `dim_intonation` whether this ending should fall or rise.
    text = "";
    kind = "";
    expects = "";
    if ctx.transcript.available {
        found = best_utterance(
            ctx.transcript, float(lo) * HOP_S, float(hi) * HOP_S
        );
        if len(found) > 0 {
            text = found[0].text;
            kind = found[0].kind;
            expects = found[0].expects;
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
        trail=trail,
        text=text, kind=kind, expects=expects
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


"""Frames in a window whose pitch estimate can be trusted.

Voiced, non-zero, within an octave of the speaker's median, and not more than
`RELIABLE_DB_DROP` below the loudest speech in this window. Everything that
reads pitch goes through here - a 370 Hz octave error corrupts a pitch span and
a melody figure just as badly as it corrupts a terminal contour.
"""
def reliable(w: Window) -> np.ndarray {
    ok = np.logical_and(w.voiced, np.not_equal(w.f0_st, 0.0));
    ok = np.logical_and(ok, np.less_equal(np.abs(w.f0_st), MAX_F0_DEVIATION));

    sp = w.db[w.speech];
    if len(sp) > 0 {
        floor = float(np.max(sp)) - RELIABLE_DB_DROP;
        ok = np.logical_and(ok, np.greater_equal(w.db, floor));
    }
    return ok;
}


"""Trustworthy voiced semitone values inside a window, as a plain array."""
def voiced_st(w: Window) -> np.ndarray {
    return w.f0_st[reliable(w)];
}


# --- Dimensions ------------------------------------------------------------

"""Median voiced pitch in this window, in semitones off the speaker's own
reference. Zero when there is not enough voiced audio to trust a median -
callers treat that as "no reading" rather than "dead centre"."""
def window_pitch_median_st(w: Window) -> float {
    st = voiced_st(w);
    if len(st) < 8 { return 0.0; }
    return float(np.median(st));
}


"""Syllables per second while actually speaking, in this window."""
def window_rate(w: Window) -> float {
    phon = max(w.phonation, 0.2);
    return float(len(w.nuclei)) / phon;
}


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


"""The terminal contour a sentence of this form should land on.

Bands are in semitones of F0 change across the final 400 ms of voiced speech.
English declaratives fall roughly 2-6 st; yes/no question rises are comparable
in size and opposite in direction. A `fragment` - a phrase left open, with no
terminal punctuation - is legitimately allowed to hang, so it is judged on a
wide band that neither rewards nor punishes direction.
"""
def terminal_target(expects: str) -> Target {
    if expects == "rise" {
        return Target(lo_fail=-6.0, lo_ideal=1.0, hi_ideal=6.0, hi_fail=13.0);
    }
    if expects == "level" {
        return Target(lo_fail=-12.0, lo_ideal=-4.0, hi_ideal=4.0, hi_fail=12.0);
    }
    return Target(lo_fail=-13.0, lo_ideal=-6.0, hi_ideal=-1.0, hi_fail=6.0);
}


"""A one-word description of which way a terminal actually went."""
def shape_of(slope: float) -> str {
    if slope > 0.75 { return "rising"; }
    if slope < -0.75 { return "falling"; }
    return "level";
}


"""Intonation for one utterance: does its melody resolve the way its grammar asks?

This is the dimension that cannot be done on acoustics alone. A rise is correct
on "Did you see the revenue line?" and wrong on "This is the part that matters
most." - the audio is identical in both cases, only the words differ. With a
transcript the sentence's form picks the target; without one, the declarative
prior is used and the wording says so.
"""
def segment_intonation(w: Window, variability: float) -> DimResult {
    slope = terminal_slope(w);
    expects = w.expects if w.expects != "" else "fall";
    assumed = w.expects == "";

    terminal = band_score(slope, terminal_target(expects));
    # Melodic movement is scored separately rather than bolted on as a bonus,
    # so the two halves stay on the same 0-100 scale as every other dimension.
    melody = band_score(
        variability, Target(lo_fail=0.2, lo_ideal=1.5, hi_ideal=6.0, hi_fail=12.0)
    );
    score = blend([terminal, melody], [2.0, 1.0]);

    shape = shape_of(slope);
    moments: list[Moment] = [];
    wanted = "rise" if expects == "rise" else ("fall" if expects == "fall" else "stay open");

    if expects == "fall" and slope > 1.5 {
        if w.kind == "wh" {
            headline = "Wh-question ending on a rise";
            detail = "This line rises " + fmt1(slope) + " st at the end. A question opening with \"" + first_word(w.text) + "\" is already marked as a question by its grammar, so English lets it fall like a statement; taking it up as well reads as tentative.";
        } else {
            headline = "Statement ending on a rise";
            detail = "This line rises " + fmt1(slope) + " st at the end. A statement that goes up reads as asking for approval rather than stating a position.";
        }
        if assumed {
            detail += " (Scored as a statement - no transcript was available to confirm.)";
        }
        moments.append(Moment(
            t=r2(float(w.hi) * HOP_S - 0.4), tEnd=r2(float(w.hi) * HOP_S),
            dimension="intonation", severity="watch",
            note="Ends on a rise - land this one falling."
        ));
    } elif expects == "rise" and slope < -0.75 {
        headline = "Question landing like a statement";
        detail = "This is a yes/no question, but the ending falls " + fmt1(abs(slope)) + " st. A falling yes/no question sounds like an instruction, and listeners often miss that they were asked something.";
        moments.append(Moment(
            t=r2(float(w.hi) * HOP_S - 0.4), tEnd=r2(float(w.hi) * HOP_S),
            dimension="intonation", severity="watch",
            note="Question falls at the end - take this one up."
        ));
    } elif expects == "rise" {
        headline = "Question lifts at the end";
        detail = "The ending rises " + fmt1(slope) + " st, which is what marks this as a question rather than a statement.";
    } elif abs(slope) < 0.5 and variability < 1.2 {
        headline = "Melody staying flat";
        detail = "The ending neither rises nor falls and the melody moves only " + fmt1(variability) + " st. Flat terminals make consecutive sentences blur together.";
    } else {
        headline = "Lands the way it should";
        detail = "The ending " + ("falls " if slope < 0.0 else "moves ") + fmt1(abs(slope)) + " st, which is what makes this " + kind_phrase(w.kind) + " sound resolved.";
    }

    metrics = [
        MetricPoint(label="Terminal", value=fmt1(slope) + " st"),
        MetricPoint(label="Wanted", value=wanted),
        MetricPoint(label="Shape", value=shape)
    ];
    return DimResult(
        report=make_report("intonation", score, headline, detail, metrics),
        moments=moments
    );
}


"""The first word of a sentence, lowercased and stripped of punctuation."""
def first_word(text: str) -> str {
    t = text.strip().lstrip("\"'([- ");
    if len(t) == 0 { return "what"; }
    return t.split(" ")[0].strip(",.?!;:\"')").lower();
}


"""How to refer to a sentence of this form in prose."""
def kind_phrase(kind: str) -> str {
    if kind == "yesno" { return "question"; }
    if kind == "wh" { return "question"; }
    if kind == "exclamation" { return "line"; }
    if kind == "fragment" { return "phrase"; }
    return "statement";
}


"""Intonation over a whole take: how often endings resolve as their form asks.

Measuring the take's own last 400 ms would let a single phrase ending decide
the score for the entire recording. Every sentence is checked instead, and the
number reported is the share that landed correctly.
"""
def take_intonation(ctx: TakeContext, w: Window, variability: float) -> DimResult {
    melody = band_score(
        variability, Target(lo_fail=0.2, lo_ideal=1.5, hi_ideal=6.0, hi_fail=12.0)
    );

    if not ctx.transcript.available or len(ctx.transcript.utterances) == 0 {
        slope = terminal_slope(w);
        score = blend([band_score(slope, terminal_target("fall")), melody], [1.0, 1.0]);
        return DimResult(report=make_report(
            "intonation", score, "Melody measured, endings not checked",
            "Without a transcript the endings cannot be told apart from questions, so only the overall melodic movement of " + fmt1(variability) + " st is scored here.",
            [
                MetricPoint(label="Melody", value=fmt1(variability) + " st"),
                MetricPoint(label="Endings", value="not checked"),
                MetricPoint(label="Shape", value=shape_of(slope))
            ]
        ));
    }

    matched = 0;
    counted = 0;
    uptalk = 0;
    flat_q = 0;
    total_slope = 0.0;
    total_terminal = 0.0;

    # Iterate the same pause-bounded windows the per-segment pass scores, not
    # the transcript's own spans. Whisper's word times are coarse by a hundred
    # milliseconds or so, which is enough to put the "terminal" window on the
    # pre-final syllable instead of the boundary tone - and that made the take
    # report 0 of 5 endings correct while the segments it is summarising each
    # scored over 90.
    spans = ctx.bounds if len(ctx.bounds) > 0 else runs_of(ctx.speech);
    for (lo, hi) in spans {
        if hi - lo < 10 { continue; }
        uw = window_of(ctx, lo, hi, 0.0);
        slope = terminal_slope(uw);
        if slope == 0.0 { continue; }
        expects = uw.expects if uw.expects != "" else "fall";

        counted += 1;
        total_slope += slope;
        total_terminal += band_score(slope, terminal_target(expects));
        if band_side(slope, terminal_target(expects)) == 0 { matched += 1; }
        if expects == "fall" and slope > 1.5 { uptalk += 1; }
        if expects == "rise" and slope < -0.75 { flat_q += 1; }
    }

    if counted == 0 {
        return DimResult(report=make_report(
            "intonation", 50.0, "Not enough voiced audio",
            "No sentence here had enough voiced speech at its ending to trace a contour.", []
        ));
    }

    # The take's ending score is the mean of the per-phrase ending scores, which
    # is what makes the take number and the segment numbers reconcile. Scoring
    # the take on the *share* of endings that landed strictly in band instead
    # put a take at 74 while the segments it summarised read 91, 95 and 93 - the
    # same "where does this number come from" problem the scale rework fixed.
    endings = total_terminal / float(counted);
    score = blend([endings, melody], [2.0, 1.0]);

    # One rising statement is a slip; several is the habit worth naming.
    pattern = max(2, counted // 4);

    headline = "Endings resolve as they should";
    detail = str(matched) + " of " + str(counted) + " sentences land the way their form asks, with the melody moving " + fmt1(variability) + " st overall.";

    if uptalk >= pattern and uptalk >= flat_q {
        headline = "Uptalk on statements";
        detail = str(uptalk) + " of " + str(counted) + " sentences are statements that rise at the end. Rising terminals on statements read as asking for approval rather than stating a position.";
    } elif flat_q >= pattern {
        headline = "Questions landing flat";
        detail = str(flat_q) + " of " + str(counted) + " questions fall at the end instead of rising, which makes them sound like instructions.";
    } elif matched * 2 < counted {
        # Missing the band without being the wrong direction means overshooting
        # it - dropping away harder than a phrase ending needs to.
        headline = "Endings overshoot";
        detail = "Only " + str(matched) + " of " + str(counted) + " endings land in the range a phrase ending needs; the rest travel further, averaging " + fmt1(total_slope / float(counted)) + " st. Very steep endings make a line sound dropped rather than finished.";
    } elif variability < 1.2 {
        headline = "Endings fine, melody narrow";
        detail = "Endings resolve correctly (" + str(matched) + " of " + str(counted) + "), but the melody only moves " + fmt1(variability) + " st, so consecutive sentences blur together.";
    } elif uptalk + flat_q > 0 {
        detail += " " + str(uptalk + flat_q) + " went the wrong way - the per-line list below marks which.";
    }

    metrics = [
        MetricPoint(label="Endings right", value=str(matched) + "/" + str(counted)),
        MetricPoint(label="Melody", value=fmt1(variability) + " st"),
        MetricPoint(label="Mean terminal", value=fmt1(total_slope / float(counted)) + " st")
    ];
    return DimResult(report=make_report("intonation", score, headline, detail, metrics));
}


"""Intonation: phrase melody and whether each phrase resolves as its form asks."""
def dim_intonation(ctx: TakeContext, w: Window, whole: bool) -> DimResult {
    st = voiced_st(w);
    if len(st) < 8 {
        return DimResult(report=make_report(
            "intonation", 50.0, "Not enough voiced audio",
            "Too little voiced speech here to trace a melody.", []
        ));
    }

    variability = float(np.std(st));
    if whole { return take_intonation(ctx, w, variability); }
    return segment_intonation(w, variability);
}


"""Semitones of F0 change across the end of a phrase.

Measured as the difference between the median of the last third and the median
of the first third of the voiced frames in the closing window - not as a fitted
slope. A least-squares slope over "whatever frames happen to be voiced" is
unusable here: when only a few scattered frames survive in the final 400 ms the
fit spans a few tens of milliseconds, and extrapolating that rate produced
terminal readings of 8, 12, even 20 semitones, where a real declarative fall is
two to six. Medians over two halves are bounded by the actual pitch the speaker
used, and they shrug off the octave errors that pitch trackers make on the
creaky, low-energy frames at the end of an utterance.

Anchored on the last voiced frame rather than the window edge: a phrase that
trails off into silence still has an ending, it just lands earlier.
"""
def terminal_slope(w: Window) -> float {
    n = int(len(w.f0_st));
    if n < 10 { return 0.0; }

    ok = reliable(w);
    last = -1;
    for i in range(n - 1, -1, -1) {
        if bool(ok[i]) { last = i; break; }
    }
    if last < 4 { return 0.0; }

    idx: list[int] = [];
    for i in range(max(0, last - TERMINAL_FRAMES), last + 1) {
        if bool(ok[i]) { idx.append(i); }
    }
    # Needs enough points to take two medians, and enough elapsed time that the
    # difference describes a contour rather than two adjacent frames.
    if len(idx) < 6 { return 0.0; }
    if float(idx[len(idx) - 1] - idx[0]) * HOP_S < 0.12 { return 0.0; }

    third = max(len(idx) // 3, 2);
    head: list[float] = [];
    tail: list[float] = [];
    for k in range(third) { head.append(float(w.f0_st[idx[k]])); }
    for k in range(len(idx) - third, len(idx)) { tail.append(float(w.f0_st[idx[k]])); }

    delta = float(np.median(np.array(tail))) - float(np.median(np.array(head)));
    return clamp(delta, -15.0, 15.0);
}


"""Pacing target band for the practice context.

VC mode narrows the ideal band toward a deliberate, unhurried middle - the
register that reads as confidence rather than a pitch rehearsed at speed.
Girlfriend mode pulls the ceiling down further: "pacing that isn't too fast"
matters more than hitting a brisk floor in a casual conversation.
"""
def pacing_target(mode: str) -> Target {
    if mode == "girlfriend" {
        return Target(lo_fail=1.0, lo_ideal=2.6, hi_ideal=4.2, hi_fail=6.5);
    }
    if mode == "vc" {
        return Target(lo_fail=1.2, lo_ideal=3.2, hi_ideal=4.8, hi_fail=8.0);
    }
    return Target(lo_fail=1.2, lo_ideal=3.4, hi_ideal=5.2, hi_fail=8.5);
}


"""Pacing: syllables per second while actually speaking."""
def dim_pacing(_ctx: TakeContext, w: Window, whole: bool, mode: str) -> DimResult {
    rate = window_rate(w);
    wpm = rate * 60.0 / 1.5;

    target = pacing_target(mode);
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


"""Whether this window contains a syllable prominent enough to call a key
point - a nucleus that stands out from its neighbours in loudness and pitch,
not just the loudest one in an otherwise flat line."""
def is_key_point(w: Window) -> bool {
    if len(w.prom) == 0 { return False; }
    return max(w.prom) >= 1.3;
}


"""Pausing for one utterance, judged on the gap it lands into.

In VC mode, a pause should only cost points for running too long - the app
should never dock a founder for launching straight into the next line - and a
pause that follows a genuine key point is allowed to run considerably longer
before it reads as hesitation rather than emphasis. Other modes keep the
original band, where landing with no room at all still costs something.
"""
def segment_pausing(w: Window, inner: list[tuple[int, int]], moments: list[Moment], mode: str) -> DimResult {
    key = is_key_point(w);
    if mode == "vc" {
        target = Target(lo_fail=0.0, lo_ideal=0.15, hi_ideal=1.9, hi_fail=3.4) if key else Target(lo_fail=0.0, lo_ideal=0.0, hi_ideal=1.1, hi_fail=2.6);
    } else {
        target = Target(lo_fail=0.0, lo_ideal=0.18, hi_ideal=1.0, hi_fail=2.6);
    }
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
        if mode == "vc" and key {
            headline = "Good pause after a strong line";
            detail = fmt1(w.trail) + "s of silence follows a line you leaned into - that is exactly where a longer pause earns its keep.";
        } else {
            headline = "Long gap after this line";
            detail = fmt1(w.trail) + "s of silence follows. Past about a second a listener reads the gap as hesitation rather than emphasis.";
            moments.append(Moment(
                t=at, tEnd=r2(at + w.trail), dimension="pausing", severity="watch",
                note=fmt1(w.trail) + "s gap - long enough that attention drifts."
            ));
        }
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
def dim_pausing(_ctx: TakeContext, w: Window, whole: bool, mode: str) -> DimResult {
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
        return segment_pausing(w, kept, moments, mode);
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


"""Emphasis contrast for a window, averaged per phrase when scoring a whole take.

Stress is a *within-phrase* phenomenon: leaning on one syllable means leaning on
it relative to its neighbours. Measured across an entire take the same statistic
picks up something different - a loud opening line against a quiet closing one -
which is a volume-consistency issue, not stress. Take-level therefore averages
the per-phrase contrast, so the take number and the segment numbers are the same
measurement at two scales instead of two different measurements.
"""
def window_emphasis(ctx: TakeContext, w: Window, whole: bool) -> tuple[float, float] {
    if not whole {
        idx = np.array(w.nuclei);
        return emphasis_range(ctx.fd.db[idx], ctx.f0_st[idx]);
    }

    db_sum = 0.0;
    st_sum = 0.0;
    counted = 0;
    for (s, e) in runs_of(ctx.speech) {
        local: list[int] = [];
        for p in ctx.nuclei {
            if p >= s and p < e { local.append(p); }
        }
        if len(local) < 4 { continue; }
        idx = np.array(local);
        pair = emphasis_range(ctx.fd.db[idx], ctx.f0_st[idx]);
        db_sum += pair[0];
        st_sum += pair[1];
        counted += 1;
    }

    if counted == 0 {
        idx = np.array(w.nuclei);
        return emphasis_range(ctx.fd.db[idx], ctx.f0_st[idx]);
    }
    return (db_sum / float(counted), st_sum / float(counted));
}


"""Stress: how much weight lands on a syllable, and whether it is the right one.

Scored on two things that are not self-referential: the absolute dB gap between
the syllables leaned on and the rest, and - when there is a transcript - whether
those accents landed on content words rather than on "the" and "of". See
`engine/stress.jac` for why the previous z-score version measured nothing.
"""
def dim_stress(ctx: TakeContext, w: Window, whole: bool) -> DimResult {
    if len(w.nuclei) < 4 {
        return DimResult(report=make_report(
            "stress", 50.0, "Not enough syllables",
            "This stretch is too short to read a stress pattern.", []
        ));
    }

    gaps = window_emphasis(ctx, w, whole);
    db_gap = gaps[0];
    st_gap = gaps[1];

    # Accented syllables in engaged English speech sit roughly 4-12 dB above
    # unaccented ones. Under about 3 dB a listener stops hearing shape at all.
    range_target = Target(lo_fail=0.5, lo_ideal=4.0, hi_ideal=12.0, hi_fail=22.0);
    range_score = band_score(db_gap, range_target);
    side = band_side(db_gap, range_target);

    place = placement(
        w.nuclei, w.prom, ctx.transcript,
        float(w.lo) * HOP_S, float(w.hi) * HOP_S
    );

    score = range_score;
    hit_rate = 0.0;
    if place.considered >= 3 {
        hit_rate = float(place.content) / float(place.considered);
        # Some accent on a function word is normal; a majority of it is a habit.
        place_score = clamp(20.0 + 80.0 * hit_rate, 8.0, 100.0);
        score = blend([range_score, place_score], [1.6, 1.0]);
    }

    headline = "Emphasis is landing";
    detail = "The syllables you lean on sit " + fmt1(db_gap) + " dB and " + fmt1(st_gap) + " st above the ones you do not, which is enough contrast to shape meaning.";

    if side < 0 {
        headline = "Emphasis is too even";
        detail = "Your leaned-on syllables are only " + fmt1(db_gap) + " dB above the rest. When every syllable weighs the same, the listener has to work out the point unaided.";
    } elif side > 0 {
        headline = "Emphasis swinging hard";
        detail = "There is a " + fmt1(db_gap) + " dB gap between your heaviest and lightest syllables. That much contrast makes the unstressed words hard to catch.";
    } elif place.function > place.content and len(place.leaned) > 0 {
        headline = "Weight on the wrong words";
        detail = "Most of your emphasis is landing on function words - " + ", ".join(["\"" + t + "\"" for t in place.leaned[0:3]]) + ". Those normally stay unaccented in English; the weight belongs on the words carrying the meaning.";
    }

    placed = "no transcript";
    if ctx.transcript.available {
        placed = "too few accents";
    }
    if place.considered >= 3 {
        placed = str(place.content) + "/" + str(place.considered) + " on content";
    }

    metrics = [
        MetricPoint(label="Emphasis", value=fmt1(db_gap) + " dB"),
        MetricPoint(label="Pitch accent", value=fmt1(st_gap) + " st"),
        MetricPoint(label="Landing", value=placed)
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


"""Tone: the colour a listener reads off everything above.

Deliberately *not* an independent measurement, and no longer presented as one.
Its score is a weighted mean of the seven measured dimensions, and its metrics
name the two that moved it, so a reader can always trace the number back to
something they can hear. Making tone a real measurement - voice quality, the
jitter and spectral-tilt cues behind "warm" and "tense" - is still open work.
"""
def dim_tone(_ctx: TakeContext, _w: Window, others: list[DimensionReport], mode: str) -> DimResult {
    by_key: dict[str, float] = {};
    for r in others { by_key[r.key] = r.score; }

    # VC mode leans on the cues that read as confidence - stress and
    # articulation carry more weight, alongside intonation. Girlfriend mode
    # leans on warmth and ease - volume and pitch matter more than how hard
    # the accents land.
    weights = [1.5, 1.1, 1.0, 1.3, 1.0, 1.2, 0.7] if mode == "vc" else [1.3, 1.3, 1.2, 0.8, 1.2, 1.0, 0.7];
    score = blend(
        [
            by_key.get("intonation", 50.0), by_key.get("volume", 50.0),
            by_key.get("pacing", 50.0), by_key.get("stress", 50.0),
            by_key.get("pitch", 50.0), by_key.get("articulation", 50.0),
            by_key.get("pausing", 50.0)
        ],
        weights
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
        MetricPoint(label="Derived from", value=str(len(others)) + " dimensions"),
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


"""Run every dimension over one window and fold the results together.

`mode` is the practice context - "vc" or "girlfriend" - and only shifts the
dimensions where the two contexts genuinely want different things: pacing,
pausing, and how tone weighs the other seven.
"""
def score_window(ctx: TakeContext, w: Window, whole: bool, mode: str = "vc") -> WindowScore {
    results = [
        dim_pitch(ctx, w, whole),
        dim_intonation(ctx, w, whole),
        dim_pacing(ctx, w, whole, mode),
        dim_pausing(ctx, w, whole, mode),
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

    tone = dim_tone(ctx, w, reports, mode);
    moments += tone.moments;

    return WindowScore(
        dimensions=[tone.report] + reports,
        moments=moments,
        overall=r1(tone.report.score)
    );
}
