"""The public leaderboard: who has the room's best delivery.

Rendered after the speaker puts their own take on the board, so the list
always answers the question they just asked - where did I land?
"""

sv import from ..engine.model { RankRow }


def:pub LeaderboardPanel(rows: list[RankRow], me: str) -> JsxElement {
    return <section className="glass rounded-3xl px-6 py-6">
        <div className="flex items-baseline justify-between">
            <span className="eyebrow">Leaderboard</span>
            <span className="eyebrow">{String(len(rows)) + " ranked"}</span>
        </div>

        {if len(rows) == 0 {
            <p className="mt-4 text-[13px] leading-relaxed text-ink-400">
                {"Nobody on the board yet. Yours is the take to beat."}
            </p>
        }}

        <ol className="list-none p-0 m-0 mt-4 flex flex-col gap-2.5">
            {for (i, row) in enumerate(rows) {
                <li
                    key={"rk" + String(i)}
                    className={
                        "flex items-center gap-3 rounded-2xl px-3 py-2 "
                        + ("glass-quiet" if row.name == me else "")
                    }
                >
                    <span className="mono text-[11px] text-ink-400 w-6 shrink-0 text-right">
                        {String(i + 1)}
                    </span>
                    <span className="flex-1 text-[14px] text-ink-700 truncate">
                        {row.name}
                    </span>
                    <span className="mono text-[10px] uppercase tracking-[0.14em] text-ink-400 shrink-0 hidden sm:inline">
                        {row.label}
                    </span>
                    <span className="mono text-[13px] text-brass shrink-0">
                        {String(Math.round(row.score))}
                    </span>
                </li>
            }}
        </ol>
    </section>;
}
