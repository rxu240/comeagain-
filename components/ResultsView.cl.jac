"""The results screen.

Order is deliberate: the verdict, then the evidence (the ribbon), then what to
do about it, then the detail. A speaker who reads only the top third still
leaves knowing the one thing to change.
"""

sv import from ..engine.model { TakeReport, SegmentReport, DimensionReport, RankRow }
import from .ScoreCrest { ScoreCrest }
import from .ProsodyRibbon { ProsodyRibbon }
import from .DimensionCard { DimensionCard }
import from .SegmentList { SegmentList }
import from .SegmentSheet { SegmentSheet }
import from .MomentList { MomentList }
import from .LiveTranscript { LiveTranscript }
import from .MetricTrace { MetricTrace }
import from .Leaderboard { LeaderboardPanel }


"""The tone dimension, which the crest displays as the headline read."""
def toneOf(dims: list[DimensionReport]) -> DimensionReport {
    for d in dims {
        if d.key == "tone" { return d; }
    }
    return dims[0] if len(dims) > 0 else DimensionReport();
}


"""Everything except tone, which is already shown in the crest."""
def mechanicsOf(dims: list[DimensionReport]) -> list[DimensionReport] {
    out: list[DimensionReport] = [];
    for d in dims {
        if d.key != "tone" { out.push(d); }
    }
    return out;
}


def:pub ResultsView(
    take: TakeReport,
    audioUrl: str,
    ranks: list[RankRow],
    ranked: bool,
    onRank: Callable[[str], None],
    onReset: Callable[[], None]
) -> JsxElement {
    has activeIdx: int = -1;
    has sheetOpen: bool = False;
    has playTime: float = -1.0;
    has rankOpen: bool = False;
    has rankName: str = "";

    def pickSegment(idx: int) {
        activeIdx = idx;
        sheetOpen = True;
    }

    def closeSheet(next: bool) {
        sheetOpen = next;
    }

    def playRange(start: float, end: float) {
        el = document.getElementById("tc-audio");
        if not el { return; }
        stopAt = end;
        el.currentTime = start;
        watcher = lambda(e: any) {
            if el.currentTime >= stopAt {
                el.pause();
                el.removeEventListener("timeupdate", watcher);
            }
        };
        el.addEventListener("timeupdate", watcher);
        el.play();
    }

    def followWord() {
        box = document.getElementById("tc-live-box");
        marker = document.getElementById("tc-live-now");
        if not box or not marker { return; }
        y = marker.offsetTop;
        pad = 12.0;
        if y < box.scrollTop + pad or y + marker.offsetHeight > box.scrollTop + box.clientHeight - pad {
            box.scrollTop = y - box.clientHeight / 2.0;
        }
    }

    def tickTime(_e: any) {
        el = document.getElementById("tc-audio");
        if not el { return; }
        playTime = el.currentTime;
        window.requestAnimationFrame(lambda(_t: any) { followWord(); });
    }

    def endPlayback(_e: any) {
        playTime = -1.0;
    }

    def submitRank(e: MouseEvent) {
        onRank(rankName);
        rankOpen = False;
    }

    def playAll(e: MouseEvent) {
        el = document.getElementById("tc-audio");
        if el {
            el.currentTime = 0.0;
            el.play();
        }
    }

    selected: SegmentReport | None = None;
    for s in take.segments {
        if s.idx == activeIdx { selected = s; }
    }

    tone = toneOf(take.dimensions);
    mechanics = mechanicsOf(take.dimensions);

    return <div className="flex flex-col gap-6">
        <ScoreCrest
            overall={take.overall}
            tone={tone}
            summary={take.summary}
            label={take.label}
            duration={take.duration}
            coachedBy={take.coachedBy}
        />

        <ProsodyRibbon
            contour={take.contour}
            envelope={take.envelope}
            voiced={take.voicedMask}
            beats={take.beats}
            duration={take.duration}
            segments={take.segments}
            activeIdx={activeIdx}
            onPick={pickSegment}
        />

        {if audioUrl != "" {
            <div className="flex gap-2">
                <button
                    type="button"
                    onClick={playAll}
                    className="glass-btn rounded-full h-11 px-6 cursor-pointer"
                >
                    <span className="mono text-[11px] uppercase tracking-[0.2em] text-ink-600">
                        {"Play take"}
                    </span>
                </button>
                <button
                    type="button"
                    onClick={lambda (e: MouseEvent) { onReset(); }}
                    className="glass-btn rounded-full h-11 px-6 cursor-pointer"
                >
                    <span className="mono text-[11px] uppercase tracking-[0.2em] text-ink-600">
                        {"New take"}
                    </span>
                </button>
                {if not ranked {
                    <button
                        type="button"
                        onClick={lambda (e: MouseEvent) { rankOpen = not rankOpen; }}
                        className="glass-btn rounded-full h-11 px-6 cursor-pointer"
                    >
                        <span className="mono text-[11px] uppercase tracking-[0.2em] text-ink-600">
                            {"Rank this?"}
                        </span>
                    </button>
                }}
            </div>
        }}

        {if rankOpen and not ranked {
            <section className="glass-quiet rounded-3xl px-6 py-5">
                <span className="eyebrow">Put this take on the board</span>
                <div className="mt-3 flex gap-2">
                    <input
                        type="text"
                        value={rankName}
                        onChange={lambda (e: ChangeEvent) { rankName = e.target.value; }}
                        placeholder="Your name"
                        aria-label="Name for the leaderboard"
                        className="glass-quiet flex-1 min-w-0 rounded-2xl px-4 py-3 text-[14px] text-ink-900 placeholder:text-ink-400 outline-none border-0"
                    />
                    <button
                        type="button"
                        onClick={submitRank}
                        className="glass-btn rounded-full h-11 px-6 cursor-pointer shrink-0"
                    >
                        <span className="mono text-[11px] uppercase tracking-[0.2em] text-ink-600">
                            {"Rank it"}
                        </span>
                    </button>
                </div>
            </section>
        }}

        {if ranked {
            <LeaderboardPanel rows={ranks} me={rankName.trim()}/>
        }}

        {if take.transcript != "" {
            <LiveTranscript
                segments={take.segments}
                transcript={take.transcript}
                source={take.transcriptSource}
                time={playTime}
            />
        }}

        <MetricTrace
            segments={take.segments}
            duration={take.duration}
            activeIdx={activeIdx}
            time={playTime}
            onPick={pickSegment}
        />

        {if len(take.coaching) > 0 {
            <section className="glass rounded-3xl px-6 py-6">
                <span className="eyebrow">Work on this</span>
                <ul className="list-none p-0 mt-4 flex flex-col gap-3.5">
                    {for (i, drill) in enumerate(take.coaching) {
                        <li key={"c" + String(i)} className="flex gap-3">
                            <span
                                className="mt-2.5 shrink-0 w-3 h-px bg-brass"
                                aria-hidden="true"
                            ></span>
                            <span className="text-[14px] leading-relaxed text-ink-700">{drill}</span>
                        </li>
                    }}
                </ul>
            </section>
        }}

        <MomentList moments={take.moments} compact={False}/>

        <section>
            <div className="flex items-baseline justify-between px-1 mb-3">
                <span className="eyebrow">Across the take</span>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                {for (i, d) in enumerate(mechanics) {
                    <DimensionCard key={"d" + String(i)} dim={d} rank={i}/>
                }}
            </div>
        </section>

        <SegmentList
            segments={take.segments}
            activeIdx={activeIdx}
            onPick={pickSegment}
        />

        {if take.transcriptNote != "" {
            <section className="glass-quiet rounded-3xl px-6 py-5">
                <span className="eyebrow">Transcript</span>
                <p className="mt-3 text-[13px] leading-relaxed text-ink-400">
                    {take.transcriptNote}
                </p>
            </section>
        }}

        <SegmentSheet
            segment={selected}
            open={sheetOpen}
            onOpenChange={closeSheet}
            onPlay={playRange}
        />

        {if audioUrl != "" {
            <audio
                id="tc-audio"
                src={audioUrl}
                preload="metadata"
                className="hidden"
                onTimeUpdate={tickTime}
                onEnded={endPlayback}
            ></audio>
        }}
    </div>;
}
