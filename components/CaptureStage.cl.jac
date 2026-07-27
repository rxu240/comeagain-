"""The opening screen: say something, or bring a file."""

import from .RecordButton { RecordButton }


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
    promptText: str,
    promptBusy: bool,
    onGeneratePrompt: Callable[[], None],
    onStart: Callable[[], None],
    onStop: Callable[[], None]
) -> JsxElement {
    genLabel = "Generate a prompt";
    if promptBusy { genLabel = "Generating..."; }
    elif promptText != "" { genLabel = "New prompt"; }

    return <div className="flex flex-col items-center justify-center gap-9 min-h-[75svh]">
        <header className="text-center px-2">
            <h1 className="display text-[2.5rem] leading-[1.1] text-ink-900">
                {"Be heard."}
            </h1>
        </header>

        {if promptText != "" {
            <div className="glass-quiet w-full max-w-sm rounded-2xl px-5 py-4">
                <p className="text-[14px] leading-relaxed text-ink-700 m-0">{promptText}</p>
            </div>
        }}

        <button
            type="button"
            onClick={onGeneratePrompt}
            disabled={promptBusy}
            className="glass-quiet rounded-full px-4 py-2 mono text-[11px] uppercase tracking-[0.2em] text-ink-600 cursor-pointer border-0"
        >
            {genLabel}
        </button>

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

    </div>;
}
