"""The record control: a glowing orb that answers to your voice.

While recording, the outer ring scales with live input level, so the button is
also the first proof that the app is listening to prosody rather than words.
"""

import from "..lib.format" { fmtTime }


def:pub RecordButton(
    recording: bool,
    elapsed: float,
    level: float,
    busy: bool,
    onStart: Callable[[], None],
    onStop: Callable[[], None]
) -> JsxElement {
    def press(e: MouseEvent) {
        if busy { return; }
        if recording { onStop(); } else { onStart(); }
    }

    ringScale = 1.0 + level * 0.42;
    caption = "Record";
    if recording { caption = "Stop"; }
    elif busy { caption = "Working"; }

    clock = "0:00";
    if recording or elapsed > 0.0 { clock = fmtTime(elapsed); }

    return <div className="flex flex-col items-center gap-4">
        <div className="relative grid place-items-center w-[188px] h-[188px]">
            <span
                aria-hidden="true"
                className="absolute inset-2 rounded-full blur-2xl opacity-70"
                style={{"background": "radial-gradient(circle, var(--brass-lt) 0%, var(--brass) 55%, transparent 75%)"}}
            ></span>

            {if recording {
                <span
                    aria-hidden="true"
                    className="absolute inset-6 rounded-full border border-brass/45"
                    style={{
                        "transform": "scale(" + String(Math.round(ringScale * 1000.0) / 1000.0) + ")",
                        "transition": "transform 90ms linear"
                    }}
                ></span>
                <span
                    aria-hidden="true"
                    className="absolute inset-6 rounded-full border border-brass/30 tc-pulse"
                ></span>
            }}

            <button
                type="button"
                onClick={press}
                disabled={busy}
                aria-pressed={recording}
                aria-label={"Stop recording" if recording else "Start recording"}
                className="glow-orb relative z-10 w-[152px] h-[152px] rounded-full grid place-items-center cursor-pointer"
            >
                <span className="flex flex-col items-center gap-2">
                    {if recording {
                        <span className="w-5 h-5 rounded-[5px] bg-clay" aria-hidden="true"></span>
                    } else {
                        <span className="w-4 h-4 rounded-full bg-ink-900" aria-hidden="true"></span>
                    }}
                    <span className="mono text-[10px] uppercase tracking-[0.24em] text-ink-900">
                        {caption}
                    </span>
                </span>
            </button>
        </div>

        <span className="mono text-sm text-ink-400 tabular-nums">
            {clock}
        </span>
    </div>;
}
