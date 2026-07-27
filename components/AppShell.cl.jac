"""Application state: capture, decode, analyse, show.

All server traffic goes through here. The timer reads elapsed time from a
timestamp rather than incrementing reactive state, because a callback created
in an earlier render sees a stale snapshot of `has` fields.
"""

sv import from ..api { AnalyseTake, RankTake, GeneratePrompt, Leaderboard }
sv import from ..engine.model { TakeReport, RankRow }

import from "..lib.audio" {
    captureSupported, beginCapture, endCapture, releaseMic,
    liveLevel, decodeToPcm
}
import from "..lib.cursorFlag" { startCursorFlag }
import from .CaptureStage { CaptureStage }
import from .ResultsView { ResultsView }
import from .Leaderboard { LeaderboardPanel }

glob _startedAt: float = 0.0;
glob _ticker: any = None;


"""Stop the level/elapsed ticker if one is running."""
def haltTicker() -> None {
    if _ticker {
        clearInterval(_ticker);
        _ticker = None;
    }
}


def:pub AppShell() -> JsxElement {
    has take: TakeReport | None = None,
        audioUrl: str = "",
        purpose: str = "",
        recording: bool = False,
        elapsed: float = 0.0,
        level: float = 0.0,
        busy: bool = False,
        status: str = "",
        error: str = "",
        canRecord: bool = True,
        ranks: list[RankRow] = [],
        ranked: bool = False,
        promptText: str = "",
        promptBusy: bool = False,
        leaderboardOpen: bool = False,
        leaderboardRows: list[RankRow] = [];

    can with entry {
        canRecord = captureSupported();
        startCursorFlag();
    }

    async def analyse(source: any) -> None;
    async def startRec() -> None;
    async def stopRec() -> None;
    async def rankTake(name: str) -> None;
    async def generatePrompt() -> None;
    async def openLeaderboard() -> None;
    def reset() -> None;

    shown = take as TakeReport;

    return <div className="relative z-10 min-h-svh">
        <header className="px-5 pt-7 pb-2 flex items-center justify-between">
            <span className="display text-[15px] tracking-tight text-ink-700">
                {"comeagain?"}
            </span>
            <button
                type="button"
                onClick={openLeaderboard}
                className="eyebrow cursor-pointer bg-transparent border-0 p-0"
            >
                {"Leaderboard"}
            </button>
        </header>

        <main className="px-5 pb-16 max-w-2xl mx-auto safe-bottom">
            {if leaderboardOpen {
                <div className="flex flex-col gap-4 pt-6">
                    <button
                        type="button"
                        onClick={lambda (e: MouseEvent) { leaderboardOpen = False; }}
                        className="eyebrow cursor-pointer bg-transparent border-0 p-0 self-start"
                    >
                        {"< Back"}
                    </button>
                    <LeaderboardPanel rows={leaderboardRows} me=""/>
                </div>
            } else {
                if take == None {
                    <CaptureStage
                        recording={recording}
                        elapsed={elapsed}
                        level={level}
                        busy={busy}
                        status={status}
                        error={error}
                        canRecord={canRecord}
                        purpose={purpose}
                        onPurpose={lambda (v: str) { purpose = v; }}
                        promptText={promptText}
                        promptBusy={promptBusy}
                        onGeneratePrompt={generatePrompt}
                        onStart={startRec}
                        onStop={stopRec}
                    />
                } else {
                    <ResultsView
                        take={shown}
                        audioUrl={audioUrl}
                        ranks={ranks}
                        ranked={ranked}
                        onRank={rankTake}
                        onReset={reset}
                    />
                }
            }}
        </main>
    </div>;
}
