"""Every utterance in the take, as a tappable list.

The list is the index into the recording: timecode, what was said, verdict,
score. Tapping a row opens that utterance's full readout and cues playback of
just that stretch.

Showing the line's own words is what makes the list scannable - "Statement
ending on a rise" is advice, but seeing it against *"This is the part that
matters most."* is the thing a speaker can act on. Takes analysed before
transcription existed carry no text, so the headline alone is the fallback.
"""

sv import from ..engine.model { SegmentReport, DimensionReport }
import from .ScoreCrest { bandText, bandFill }
import from "..lib.format" { fmtRange }


"""What the speaker actually said, or the verdict when there is no transcript."""
def rowLabel(seg: SegmentReport) -> str {
    if seg.text != "" { return seg.text; }
    return seg.headline;
}


"""The one thing to fix on this line, shown under the words.

Deliberately *not* `seg.headline` - that is the tone verdict, and tone is a
weighted mean of everything else, so it lands on "warm and grounded" for almost
every line and renders as the same sentence down the whole list. The weakest
dimension is the part that differs per utterance and the part worth acting on.
"""
def rowSub(seg: SegmentReport) -> str {
    if seg.text == "" { return ""; }

    worst: DimensionReport | None = None;
    for d in seg.dimensions {
        if d.key == "tone" { continue; }
        if worst == None or d.score < worst.score { worst = d; }
    }
    if worst == None { return seg.headline; }
    return worst.name + " " + String(Math.round(worst.score)) + " · " + worst.headline;
}


def:pub SegmentList(
    segments: list[SegmentReport],
    activeIdx: int,
    onPick: Callable[[int], None]
) -> JsxElement {
    return <section>
        <div className="flex items-baseline justify-between px-1 mb-3">
            <span className="eyebrow">By utterance</span>
            <span className="eyebrow">{String(len(segments))}</span>
        </div>

        <ul className="list-none p-0 m-0 flex flex-col gap-2">
            {for (i, seg) in enumerate(segments) {
                <li key={"s" + String(i)}>
                    <button
                        type="button"
                        onClick={lambda (e: MouseEvent) { onPick(seg.idx); }}
                        aria-current={seg.idx == activeIdx}
                        className={
                            "w-full text-left rounded-2xl px-4 py-3 cursor-pointer transition-colors "
                            + ("glass" if seg.idx == activeIdx else "glass-quiet")
                        }
                    >
                        <div className="flex items-center gap-3">
                            <span
                                className={"shrink-0 w-1.5 h-1.5 rounded-full " + bandFill(seg.dimensions[0].band)}
                                aria-hidden="true"
                            ></span>
                            <span className="mono text-[11px] text-ink-400 shrink-0">
                                {fmtRange(seg.start, seg.end)}
                            </span>
                            <span className="flex-1 text-[14px] text-ink-700 truncate">
                                {rowLabel(seg)}
                            </span>
                            <span className={"mono text-[13px] shrink-0 " + bandText(seg.dimensions[0].band)}>
                                {String(Math.round(seg.score))}
                            </span>
                        </div>
                        <div className={"pl-[1.4rem] mt-0.5" if seg.text != "" else "hidden"}>
                            <span className="text-[12px] text-ink-400 truncate">
                                {rowSub(seg)}
                            </span>
                        </div>
                    </button>
                </li>
            }}
        </ul>
    </section>;
}
