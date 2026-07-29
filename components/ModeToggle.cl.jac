"""The VC / Girlfriend practice-mode switch: one small pill, split in half.

Sits top-centre because it is the one choice that reframes everything below
it - the pacing band, the pausing rule, the generated prompt. A slider rather
than a dropdown because there are only ever two states and the sliding thumb
makes the current one impossible to miss.
"""

def:pub ModeToggle(mode: str, onChange: Callable[[str], None]) -> JsxElement {
    isVc = mode == "vc";

    def pick(next: str) {
        if next != mode { onChange(next); }
    }

    return <div
        role="radiogroup"
        aria-label="Practice mode"
        className="relative inline-flex items-center rounded-full glass-quiet p-[3px] h-8 w-[132px] shrink-0"
    >
        <span
            aria-hidden="true"
            className={"absolute top-[3px] bottom-[3px] w-[63px] rounded-full transition-transform duration-200 ease-out bg-mode-accent " + ("" if isVc else "translate-x-[63px]")}
        ></span>

        <button
            type="button"
            role="radio"
            aria-checked={isVc}
            onClick={lambda (e: MouseEvent) { pick("vc"); }}
            className={"relative z-10 flex-1 h-full rounded-full mono text-[10px] uppercase tracking-[0.14em] cursor-pointer border-0 bg-transparent " + ("text-sand-50" if isVc else "text-ink-600")}
        >
            {"VC"}
        </button>
        <button
            type="button"
            role="radio"
            aria-checked={not isVc}
            onClick={lambda (e: MouseEvent) { pick("girlfriend"); }}
            className={"relative z-10 flex-1 h-full rounded-full mono text-[10px] uppercase tracking-[0.14em] cursor-pointer border-0 bg-transparent " + ("text-sand-50" if not isVc else "text-ink-600")}
        >
            {"GF"}
        </button>
    </div>;
}
