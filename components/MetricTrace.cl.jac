"""Every mechanics dimension, plotted across the take as it plays.

Seven lines, one per dimension below tone (tone is a mean of these seven, so
plotting it alongside them would just retrace their average). Each line holds
its segment's score flat across that segment's span and breaks over a pause,
the same "gaps are drawn as gaps" rule ProsodyRibbon uses - there is no
per-second reading to interpolate, only a per-utterance one, and a smoothed
curve would imply a resolution the data doesn't have.

The brass playhead is the same clock LiveTranscript follows, so the two panels
read as one instrument: word lighting up above, its line moving below.
"""

sv import from ..engine.model { SegmentReport, DimensionReport }

glob VIEW_W: float = 1000.0;
glob PLOT_TOP: float = 12.0;
glob PLOT_BOT: float = 172.0;

glob MECH_KEYS: list[str] = [
    "pitch", "pacing", "pausing", "volume", "intonation", "stress", "articulation"
];

"""Fixed categorical order, validated for CVD separation against the sand
surface (`node validate_palette.js` - PASS on lightness, chroma, CVD ΔE >= 9,
normal-vision ΔE >= 19; WARN on raw contrast for four slots, mitigated by the
text-labelled legend below rather than color alone)."""
glob MECH_COLORS: dict[str, str] = {
    "pitch": "#2a78d6",
    "pacing": "#eb6834",
    "pausing": "#1baf7a",
    "volume": "#eda100",
    "intonation": "#e87ba4",
    "stress": "#008300",
    "articulation": "#4a3aa7"
};

glob MECH_LABELS: dict[str, str] = {
    "pitch": "Pitch",
    "pacing": "Pacing",
    "pausing": "Pausing",
    "volume": "Volume",
    "intonation": "Intonation",
    "stress": "Stress",
    "articulation": "Articulation"
};


"""Round to one decimal for compact SVG path data."""
def n1(v: float) -> str {
    return String(Math.round(v * 10.0) / 10.0);
}


"""Map seconds to an x coordinate."""
def xAt(t: float, span: float) -> float {
    return (t / span) * VIEW_W;
}


"""Map a 0-100 score to a y coordinate, clamped to the plot band."""
def yScore(score: float) -> float {
    clamped = score;
    if clamped > 100.0 { clamped = 100.0; }
    if clamped < 0.0 { clamped = 0.0; }
    return PLOT_BOT - (clamped / 100.0) * (PLOT_BOT - PLOT_TOP);
}


"""This dimension's score within one segment's readout, or -1 if absent."""
def scoreOf(dims: list[DimensionReport], key: str) -> float {
    for d in dims {
        if d.key == key { return d.score; }
    }
    return -1.0;
}


"""One dimension's path: a flat run per segment, broken across the pauses."""
def tracePath(segments: list[SegmentReport], key: str, span: float) -> str {
    out = "";
    for seg in segments {
        s = scoreOf(seg.dimensions, key);
        if s < 0.0 { continue; }
        y = n1(yScore(s));
        out = out + "M " + n1(xAt(seg.start, span)) + " " + y
                  + " L " + n1(xAt(seg.end, span)) + " " + y + " ";
    }
    return out;
}


def:pub MetricTrace(
    segments: list[SegmentReport],
    duration: float,
    activeIdx: int,
    time: float,
    onPick: Callable[[int], None]
) -> JsxElement {
    span = duration if duration > 0.1 else 1.0;
    showPlayhead = time >= 0.0;
    playX = n1(xAt(time, span));

    return <figure className="glass rounded-3xl overflow-hidden m-0">
        <figcaption className="flex items-baseline justify-between px-5 pt-4 pb-2">
            <span className="eyebrow">Metrics over time</span>
            <span className="eyebrow">{String(len(segments)) + " utterances"}</span>
        </figcaption>

        <svg
            viewBox="0 0 1000 184"
            preserveAspectRatio="none"
            role="img"
            aria-label="Delivery metric scores across the recording"
            className="block w-full h-[168px] sm:h-[196px] touch-manipulation"
        >
            <line
                x1="0" y1={String(yScore(50.0))} x2="1000" y2={String(yScore(50.0))}
                stroke="#8B8172" strokeOpacity="0.28" strokeWidth="1" strokeDasharray="3 7"
            />

            {for (i, seg) in enumerate(segments) {
                <rect
                    key={"mwash" + String(i)}
                    x={n1((seg.start / span) * VIEW_W)}
                    y="4"
                    width={n1(Math.max(((seg.end - seg.start) / span) * VIEW_W, 2.0))}
                    height="176"
                    fill="#A67C34"
                    fillOpacity={0.10 if i == activeIdx else 0.0}
                />
            }}

            {for (i, mk) in enumerate(MECH_KEYS) {
                <path
                    key={"trace" + String(i)}
                    d={tracePath(segments, mk, span)}
                    fill="none"
                    stroke={MECH_COLORS[mk]}
                    strokeWidth="2"
                    strokeLinecap="round"
                />
            }}

            {if showPlayhead {
                <line
                    x1={playX} y1="4" x2={playX} y2="180"
                    stroke="#A67C34" strokeWidth="1.5" strokeOpacity="0.85"
                />
            }}

            {for (i, seg) in enumerate(segments) {
                <rect
                    key={"mhit" + String(i)}
                    x={n1((seg.start / span) * VIEW_W)}
                    y="0"
                    width={n1(Math.max(((seg.end - seg.start) / span) * VIEW_W, 2.0))}
                    height="184"
                    fill="transparent"
                    className="cursor-pointer"
                    onClick={lambda (e: MouseEvent) { onPick(seg.idx); }}
                />
            }}
        </svg>

        <div className="flex items-center justify-between px-5 pt-1">
            <span className="mono text-[11px] text-ink-400">100</span>
            <span className="mono text-[11px] text-ink-400">{"tap a band to inspect"}</span>
            <span className="mono text-[11px] text-ink-400">0</span>
        </div>

        <ul className="list-none p-0 m-0 mt-3 px-5 pb-4 flex flex-wrap gap-x-4 gap-y-2">
            {for (i, mk) in enumerate(MECH_KEYS) {
                <li key={"leg" + String(i)} className="flex items-center gap-1.5">
                    <span
                        className="w-2 h-2 rounded-full shrink-0"
                        style={{"backgroundColor": MECH_COLORS[mk]}}
                        aria-hidden="true"
                    ></span>
                    <span className="mono text-[10px] uppercase tracking-[0.14em] text-ink-600">
                        {MECH_LABELS[mk]}
                    </span>
                </li>
            }}
        </ul>
    </figure>;
}
