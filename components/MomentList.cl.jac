"""Timestamped observations, newest concern first.

A moment is the difference between "your pacing is fast" and "you rush from
0:42 to 0:48". Each row is a place in the recording, not a general property.
"""

sv import from ..engine.model { Moment }
import from "..lib.format" { fmtTime }


"""Colour for a moment's severity."""
def dotFor(severity: str) -> str {
    if severity == "watch" { return "bg-band-watch"; }
    if severity == "good" { return "bg-band-strong"; }
    return "bg-band-steady";
}


def:pub MomentList(moments: list[Moment], compact: bool) -> JsxElement {
    return <section>
        {if len(moments) == 0 {
            <p className="text-[13px] text-ink-400 italic px-1">
                {"Nothing flagged here - the delivery holds steady throughout."}
            </p>
            skip;
        }}

        {if not compact {
            <div className="flex items-baseline justify-between px-1 mb-3">
                <span className="eyebrow">Moments</span>
                <span className="eyebrow">{String(len(moments))}</span>
            </div>
        }}

        <ul className="list-none p-0 m-0 flex flex-col gap-1.5">
            {for (i, m) in enumerate(moments) {
                <li
                    key={"mo" + String(i)}
                    className="flex items-start gap-3 rounded-xl glass-quiet px-3.5 py-2.5"
                >
                    <span
                        className={"mt-1.5 shrink-0 w-1.5 h-1.5 rounded-full " + dotFor(m.severity)}
                        aria-hidden="true"
                    ></span>
                    <span className="mono text-[11px] text-ink-400 shrink-0 mt-0.5">
                        {fmtTime(m.t)}
                    </span>
                    <span className="text-[13px] leading-snug text-ink-700">{m.note}</span>
                </li>
            }}
        </ul>
    </section>;
}
