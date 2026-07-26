"""The opening screen: say something, or bring a file.

The eight dimensions are printed here rather than hidden behind a marketing
line, because the list *is* the product description and a speaker recognises
their own weak spot in it immediately.
"""

import from .RecordButton { RecordButton }

glob MEASURES: list[str] = [
    "Tone", "Pitch", "Pacing", "Pausing",
    "Volume", "Intonation", "Stress", "Articulation"
];


def:pub CaptureStage(
    recording: bool,
    elapsed: float,
    level: float,
    busy: bool,
    status: str,
    error: str,
    canRecord: bool,
    purpose: str,
    onPurpose: Callable[[str], None],
    onStart: Callable[[], None],
    onStop: Callable[[], None]
) -> JsxElement {
    return <div className="flex flex-col items-center gap-9 pt-6">
        <header className="text-center px-2">
            <h1 className="display text-[2.5rem] leading-[1.1] text-ink-900">
                {"Hate when people say “huh?”"}
                <br/>
                {"like they can’t hear you?"}
            </h1>
            <p className="mt-3 text-[15px] leading-relaxed text-ink-600 max-w-[34ch] mx-auto">
                {"TONECRAFT is the first AI speech communication coach. Record a minute of speaking and it reads your delivery second by second."}
            </p>
        </header>

        <RecordButton
            recording={recording}
            elapsed={elapsed}
            level={level}
            busy={busy}
            onStart={onStart}
            onStop={onStop}
        />

        {if not canRecord {
            <p className="text-[13px] text-clay text-center max-w-[34ch]">
                {"This browser will not give us a microphone. Allow microphone access and reload the page."}
            </p>
        }}

        {if status != "" {
            <p className="mono text-[11px] uppercase tracking-[0.2em] text-ink-400" aria-live="polite">
                {status}
            </p>
        }}

        {if error != "" {
            <p className="text-[13px] text-clay text-center max-w-[34ch]" role="alert">{error}</p>
        }}

        <div className="w-full max-w-sm flex flex-col gap-3">
            <input
                type="text"
                value={purpose}
                onChange={lambda (e: ChangeEvent) { onPurpose(e.target.value); }}
                placeholder="What is this for? (optional)"
                aria-label="What this recording is for"
                className="glass-quiet w-full rounded-2xl px-4 py-3 text-[14px] text-ink-900 placeholder:text-ink-400 outline-none border-0"
            />
        </div>

        <div className="w-full max-w-md px-2">
            <div className="hairline mb-4"></div>
            <ul className="list-none p-0 m-0 flex flex-wrap justify-center gap-x-4 gap-y-2">
                {for (i, name) in enumerate(MEASURES) {
                    <li key={"me" + String(i)} className="eyebrow">{name}</li>
                }}
            </ul>
        </div>
    </div>;
}
