"""The overall verdict: one number, one read, one paragraph.

Deliberately typographic rather than a dial or gauge. The number is the loudest
thing on the results screen and everything else is quiet around it.
"""

sv import from ..engine.model { DimensionReport }
import from ".ui.badge" { Badge }


"""Tailwind text colour class for a band."""
def:pub bandText(band: str) -> str {
    if band == "strong" { return "band-strong"; }
    if band == "watch" { return "band-watch"; }
    return "band-steady";
}


"""Tailwind background class for a band."""
def:pub bandFill(band: str) -> str {
    if band == "strong" { return "bg-band-strong"; }
    if band == "watch" { return "bg-band-watch"; }
    return "bg-band-steady";
}


"""Plain-language name for a band, used in chips."""
def:pub bandLabel(band: str) -> str {
    if band == "strong" { return "Strong"; }
    if band == "watch" { return "Needs work"; }
    return "Steady";
}


def:pub ScoreCrest(
    overall: float,
    tone: DimensionReport,
    summary: str,
    label: str,
    duration: float,
    coachedBy: str
) -> JsxElement {
    band = tone.band;
    mins = Math.floor(duration / 60.0);
    secs = String(Math.floor(duration % 60.0)).padStart(2, "0");
    coachLabel = "AI coach" if coachedBy == "llm" else "rule coach";
    stamp = String(mins) + ":" + secs + "  ·  " + coachLabel;

    return <section className="glass rounded-3xl px-6 py-7 tc-rise">
        <div className="flex items-center justify-between gap-3">
            <span className="eyebrow">{label}</span>
            <span className="mono text-[11px] text-ink-400">{stamp}</span>
        </div>

        <div className="mt-5 flex items-end gap-4">
            <span className={"display text-[5.5rem] leading-[0.82] " + bandText(band)}>
                {String(Math.round(overall))}
            </span>
            <div className="pb-2 flex items-center gap-3">
                <span className="mono text-sm text-ink-400">/100</span>
                <Badge
                    variant="outline"
                    className={"glass-quiet rounded-full px-3 py-1 mono text-[10px] uppercase tracking-[0.18em] border-0 " + bandText(band)}
                >
                    {bandLabel(band)}
                </Badge>
            </div>
        </div>

        <div className="hairline my-5"></div>

        <h2 className="display text-2xl text-ink-900 leading-snug">{tone.headline}</h2>
        <p className="mt-2 text-[15px] leading-relaxed text-ink-600">{summary}</p>
    </section>;
}
