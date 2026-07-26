"""One delivery dimension: score, finding, and the numbers behind it.

Collapsed the card is a verdict; expanded it shows why. Eight of these on a
phone screen is a lot of prose, so the reasoning is opt-in.
"""

sv import from ..engine.model { DimensionReport }
import from .ScoreCrest { bandText, bandFill }


def:pub DimensionCard(dim: DimensionReport, rank: int) -> JsxElement {
    has open: bool = False;

    def toggle(e: MouseEvent) {
        open = not open;
    }

    width = Math.max(Math.min(dim.score, 100.0), 3.0);

    return <article
        className="glass-quiet rounded-2xl overflow-hidden tc-rise"
        style={{"animationDelay": String(40 * rank) + "ms"}}
    >
        <button
            type="button"
            onClick={toggle}
            aria-expanded={open}
            className="w-full text-left px-5 py-4 cursor-pointer bg-transparent border-0"
        >
            <div className="flex items-baseline justify-between gap-3">
                <h3 className="display text-lg text-ink-900">{dim.name}</h3>
                <span className={"mono text-sm " + bandText(dim.band)}>
                    {String(Math.round(dim.score))}
                </span>
            </div>

            <div className="mt-2.5 h-[3px] w-full rounded-full bg-sand-300/60 overflow-hidden">
                <div
                    className={"h-full rounded-full " + bandFill(dim.band)}
                    style={{"width": String(width) + "%", "opacity": "0.85"}}
                ></div>
            </div>

            <p className="mt-3 text-[14px] leading-snug text-ink-700">{dim.headline}</p>

            <div className="mt-3 flex flex-wrap gap-x-5 gap-y-1">
                {for (i, m) in enumerate(dim.metrics) {
                    <span key={"m" + String(i)} className="mono text-[11px] text-ink-400">
                        {m.label + " " + m.value}
                    </span>
                }}
            </div>
        </button>

        {if open {
            <div className="px-5 pb-5 -mt-1">
                <div className="hairline mb-3"></div>
                <p className="text-[14px] leading-relaxed text-ink-600">{dim.detail}</p>
                <p className="mt-2 text-[12px] leading-relaxed text-ink-400 italic">{dim.blurb}</p>
            </div>
        }}
    </article>;
}
