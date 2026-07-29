"""Attention: a second-order read on how engaging this take would be live.

Deliberately separate from the eight measured dimensions above it - this is a
composite of variety (pacing, pitch, sentence form) plus the sound cues that
matter most for the current practice mode, not a single measurement.
"""

import from .ScoreCrest { bandText, bandFill }


def:pub bandOf(score: float) -> str {
    if score >= 80.0 { return "strong"; }
    if score >= 60.0 { return "steady"; }
    return "watch";
}


def:pub AttentionCard(score: float, headline: str, detail: str) -> JsxElement {
    band = bandOf(score);
    width = Math.max(Math.min(score, 100.0), 3.0);

    return <section className="glass-quiet rounded-3xl px-6 py-6 tc-rise">
        <div className="flex items-baseline justify-between gap-3">
            <span className="eyebrow">Attention</span>
            <span className={"mono text-2xl " + bandText(band)}>
                {String(Math.round(score))}
            </span>
        </div>

        <div className="mt-3 h-[3px] w-full rounded-full bg-sand-300/60 overflow-hidden">
            <div
                className={"h-full rounded-full " + bandFill(band)}
                style={{"width": String(width) + "%", "opacity": "0.85"}}
            ></div>
        </div>

        <h3 className="mt-4 display text-xl text-ink-900 leading-snug">{headline}</h3>
        <p className="mt-2 text-[14px] leading-relaxed text-ink-600">{detail}</p>
    </section>;
}
