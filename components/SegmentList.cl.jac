"""Every utterance in the take, as a tappable list.

The list is the index into the recording: timecode, verdict, score. Tapping a
row opens that utterance's full readout and cues playback of just that stretch.
"""

sv import from ..engine.model { SegmentReport }
import from .ScoreCrest { bandText, bandFill }
import from "..lib.format" { fmtRange }


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
                        onClick={lambda e: MouseEvent { onPick(seg.idx); }}
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
                                {seg.headline}
                            </span>
                            <span className={"mono text-[13px] shrink-0 " + bandText(seg.dimensions[0].band)}>
                                {String(Math.round(seg.score))}
                            </span>
                        </div>
                    </button>
                </li>
            }}
        </ul>
    </section>;
}
