"""Turning raw acoustics into scores, bands and plain-English phrasing.

Every dimension is scored the same way: a target band with soft shoulders. Full
marks inside the band, a smooth taper out to the failure bound, and a floor so
one bad number never reads as zero. Targets come from the speech-science
literature on delivery (articulation rate, pause ratio, pitch span in
semitones) rather than from taste.
"""

glob STRONG: float = 80.0;
glob STEADY: float = 60.0;


"""A target range with the outer bounds where the score bottoms out."""
obj Target {
    has lo_fail: float = 0.0,
        lo_ideal: float = 0.0,
        hi_ideal: float = 0.0,
        hi_fail: float = 0.0;
}


"""Constrain `v` to [lo, hi]."""
def clamp(v: float, lo: float, hi: float) -> float {
    if v < lo { return lo; }
    if v > hi { return hi; }
    return v;
}


"""Score `v` against a target band: ~100 inside, tapering to ~8 past the bounds."""
def band_score(v: float, t: Target) -> float {
    if v >= t.lo_ideal and v <= t.hi_ideal {
        centre = (t.lo_ideal + t.hi_ideal) / 2.0;
        half = max((t.hi_ideal - t.lo_ideal) / 2.0, 1e-6);
        return clamp(100.0 - 8.0 * abs(v - centre) / half, 90.0, 100.0);
    }
    if v < t.lo_ideal {
        span = max(t.lo_ideal - t.lo_fail, 1e-6);
        return clamp(30.0 + 60.0 * ((v - t.lo_fail) / span), 8.0, 90.0);
    }
    span = max(t.hi_fail - t.hi_ideal, 1e-6);
    return clamp(30.0 + 60.0 * ((t.hi_fail - v) / span), 8.0, 90.0);
}


"""Which side of the target a value fell on: -1 low, 0 inside, 1 high."""
def band_side(v: float, t: Target) -> int {
    if v < t.lo_ideal { return -1; }
    if v > t.hi_ideal { return 1; }
    return 0;
}


"""Map a 0-100 score to a band label."""
def band_of(score: float) -> str {
    if score >= STRONG { return "strong"; }
    if score >= STEADY { return "steady"; }
    return "watch";
}


"""Round to one decimal, keeping the result typed as float."""
def r1(v: float) -> float {
    return float(round(v, 1));
}


"""Round to two decimals, keeping the result typed as float."""
def r2(v: float) -> float {
    return float(round(v, 2));
}


"""Seconds as m:ss, the form used on every timestamp in the UI."""
def fmt_time(t: float) -> str {
    total = int(t);
    mins = total // 60;
    secs = total % 60;
    pad = "0" if secs < 10 else "";
    return str(mins) + ":" + pad + str(secs);
}


"""One decimal place, without floating-point noise."""
def fmt1(v: float) -> str {
    return str(round(v, 1));
}


"""Nearest whole number as a string."""
def fmt0(v: float) -> str {
    return str(int(round(v, 0)));
}


"""Percentage from a 0-1 fraction."""
def fmt_pct(v: float) -> str {
    return str(int(round(v * 100.0, 0))) + "%";
}


"""Weighted mean that ignores dimensions with no data."""
def blend(scores: list[float], weights: list[float]) -> float {
    total = 0.0;
    wsum = 0.0;
    for (s, w) in zip(scores, weights) {
        total += s * w;
        wsum += w;
    }
    if wsum <= 0.0 { return 0.0; }
    return total / wsum;
}
