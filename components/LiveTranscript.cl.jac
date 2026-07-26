"""The transcript as a live caption panel.

Sits directly under the pitch ribbon and the play controls, so during replay
the words run along with the voice line: what has been said holds ink, the
word under the playhead lights in brass, what is coming stays faint. Idle, it
reads as a plain transcript.

Takes whose utterances carry no per-word timing fall back to lighting one
utterance at a time; takes with no per-utterance text at all fall back to the
flat transcript string.
"""

sv import from ..engine.model { SegmentReport }


"""Whether any utterance carries its own text or word timings."""
def hasSpans(segments: list[SegmentReport]) -> bool {
    for s in segments {
        if s.text != "" or len(s.words) > 0 { return True; }
    }
    return False;
}


"""True while the playhead is inside this span."""
def isNow(start: float, end: float, t: float) -> bool {
    return t >= start and t < end;
}


"""Ink for one span of the transcript, given the playhead."""
def spanCls(start: float, end: float, t: float) -> str {
    base = "transition-colors duration-150 ";
    if t < 0.0 or t >= end { return base + "text-ink-700"; }
    if t >= start { return base + "text-brass font-medium"; }
    return base + "text-ink-400";
}


def:pub LiveTranscript(
    segments: list[SegmentReport],
    transcript: str,
    source: str,
    time: float
) -> JsxElement {
    synced = hasSpans(segments);

    return <section className="glass-quiet rounded-3xl px-6 py-5">
        <div className="flex items-baseline justify-between">
            <span className="eyebrow">Transcript</span>
            <span className="mono text-[10px] uppercase tracking-[0.18em] text-ink-400">
                {source}
            </span>
        </div>

        <div id="tc-live-box" className="relative mt-4 max-h-44 overflow-y-auto">
            {if synced {
                <p className="m-0 text-[14px] leading-relaxed">
                    {for (i, seg) in enumerate(segments) {
                        <span key={"u" + String(i)}>
                            {if len(seg.words) > 0 {
                                for (j, w) in enumerate(seg.words) {
                                    <span
                                        key={"w" + String(i) + "-" + String(j)}
                                        id={"tc-live-now" if isNow(w.start, w.end, time) else ""}
                                        className={spanCls(w.start, w.end, time)}
                                    >
                                        {w.text + " "}
                                    </span>
                                }
                            }}
                            {if len(seg.words) == 0 and seg.text != "" {
                                <span
                                    id={"tc-live-now" if isNow(seg.start, seg.end, time) else ""}
                                    className={spanCls(seg.start, seg.end, time)}
                                >
                                    {seg.text + " "}
                                </span>
                            }}
                        </span>
                    }}
                </p>
            }}
            {if not synced {
                <p className="m-0 text-[14px] leading-relaxed text-ink-700">
                    {transcript}
                </p>
            }}
        </div>
    </section>;
}
