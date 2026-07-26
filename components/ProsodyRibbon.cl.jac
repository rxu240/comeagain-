"""The prosody ribbon: the recording drawn as the two things being judged.

Upper lane is the pitch track in semitones against the speaker's own median,
so the dashed rule is "your home note" and every excursion is readable against
it. Lower lane is the loudness envelope. Pauses are literal gaps in both lanes
- silence is drawn as silence. Brass ticks mark stressed syllables.

Tapping a band selects that utterance; the rest of the screen follows.
"""

sv import from ..engine.model { SegmentReport }

glob VIEW_W: float = 1000.0;
glob PITCH_TOP: float = 20.0;
glob PITCH_BOT: float = 116.0;
glob LEVEL_TOP: float = 140.0;
glob LEVEL_BOT: float = 208.0;
glob ST_RANGE: float = 11.0;


"""Round to one decimal for compact SVG path data."""
def n1(v: float) -> str {
    return String(Math.round(v * 10.0) / 10.0);
}


"""Map a sample index to an x coordinate."""
def xAt(i: int, total: int) -> float {
    if total <= 1 { return 0.0; }
    return (float(i) / float(total - 1)) * VIEW_W;
}


"""Map semitones-from-median to a y coordinate in the pitch lane."""
def yPitch(st: float) -> float {
    clamped = st;
    if clamped > ST_RANGE { clamped = ST_RANGE; }
    if clamped < 0.0 - ST_RANGE { clamped = 0.0 - ST_RANGE; }
    mid = (PITCH_TOP + PITCH_BOT) / 2.0;
    half = (PITCH_BOT - PITCH_TOP) / 2.0;
    return mid - (clamped / ST_RANGE) * half;
}


"""Build one polyline per continuous voiced run, so gaps stay gaps."""
def pitchPaths(contour: list[float], voiced: list[int]) -> list[str] {
    out: list[str] = [];
    total = len(contour);
    current = "";
    run = 0;
    for i in range(total) {
        if voiced[i] == 1 {
            cmd = "M " if run == 0 else " L ";
            current = current + cmd + n1(xAt(i, total)) + " " + n1(yPitch(contour[i]));
            run = run + 1;
        } else {
            if run > 2 { out.push(current); }
            current = "";
            run = 0;
        }
    }
    if run > 2 { out.push(current); }
    return out;
}


"""Closed area path for the loudness envelope."""
def levelPath(envelope: list[float]) -> str {
    total = len(envelope);
    if total < 2 { return ""; }
    d = "M 0 " + n1(LEVEL_BOT);
    for i in range(total) {
        h = envelope[i] * (LEVEL_BOT - LEVEL_TOP);
        d = d + " L " + n1(xAt(i, total)) + " " + n1(LEVEL_BOT - h);
    }
    return d + " L " + n1(VIEW_W) + " " + n1(LEVEL_BOT) + " Z";
}


def:pub ProsodyRibbon(
    contour: list[float],
    envelope: list[float],
    voiced: list[int],
    beats: list[float],
    duration: float,
    segments: list[SegmentReport],
    activeIdx: int,
    onPick: Callable[[int], None]
) -> JsxElement {
    span = duration if duration > 0.1 else 1.0;
    paths = pitchPaths(contour, voiced);
    area = levelPath(envelope);

    return <figure className="glass rounded-3xl overflow-hidden m-0">
        <figcaption className="flex items-baseline justify-between px-5 pt-4 pb-2">
            <span className="eyebrow">Pitch &amp; level</span>
            <span className="eyebrow">{String(len(segments)) + " utterances"}</span>
        </figcaption>

        <svg
            viewBox="0 0 1000 224"
            preserveAspectRatio="none"
            role="img"
            aria-label="Pitch and loudness across the recording"
            className="block w-full h-[168px] sm:h-[196px] touch-manipulation"
        >
            <defs>
                <linearGradient id="tcLevel" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#B9A88B" stopOpacity="0.72"/>
                    <stop offset="100%" stopColor="#B9A88B" stopOpacity="0.18"/>
                </linearGradient>
            </defs>

            <line
                x1="0" y1={String(yPitch(0.0))} x2="1000" y2={String(yPitch(0.0))}
                stroke="#8B8172" strokeOpacity="0.38" strokeWidth="1" strokeDasharray="3 7"
            />

            {for (i, seg) in enumerate(segments) {
                <rect
                    key={"wash" + String(i)}
                    x={n1((seg.start / span) * VIEW_W)}
                    y="8"
                    width={n1(Math.max(((seg.end - seg.start) / span) * VIEW_W, 2.0))}
                    height="208"
                    fill="#A67C34"
                    fillOpacity={0.13 if i == activeIdx else 0.0}
                />
            }}

            <path d={area} fill="url(#tcLevel)"/>

            {for (i, d) in enumerate(paths) {
                <path
                    key={"p" + String(i)}
                    d={d}
                    fill="none"
                    stroke="#A67C34"
                    strokeWidth="2.25"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                />
            }}

            {for (i, t) in enumerate(beats) {
                <circle
                    key={"b" + String(i)}
                    cx={n1((t / span) * VIEW_W)}
                    cy={n1(PITCH_BOT + 12.0)}
                    r="2.4"
                    fill="#A67C34"
                    fillOpacity="0.65"
                />
            }}

            {for (i, seg) in enumerate(segments) {
                <line
                    key={"edge" + String(i)}
                    x1={n1((seg.start / span) * VIEW_W)} y1="8"
                    x2={n1((seg.start / span) * VIEW_W)} y2="216"
                    stroke="#8B8172" strokeOpacity="0.28" strokeWidth="1"
                />
            }}

            {for (i, seg) in enumerate(segments) {
                <rect
                    key={"hit" + String(i)}
                    x={n1((seg.start / span) * VIEW_W)}
                    y="0"
                    width={n1(Math.max(((seg.end - seg.start) / span) * VIEW_W, 2.0))}
                    height="224"
                    fill="transparent"
                    className="cursor-pointer"
                    onClick={lambda e: MouseEvent { onPick(seg.idx); }}
                />
            }}
        </svg>

        <div className="flex items-center justify-between px-5 pb-4 pt-1">
            <span className="mono text-[11px] text-ink-400">0:00</span>
            <span className="mono text-[11px] text-ink-400">
                {"tap a band to inspect"}
            </span>
            <span className="mono text-[11px] text-ink-400">
                {String(Math.floor(duration / 60.0)) + ":" + String(Math.floor(duration % 60.0)).padStart(2, "0")}
            </span>
        </div>
    </figure>;
}
