"""The TONECRAFT server API.

Four public walkers, each of which jac-scale exposes as `POST /walker/<name>`.
`AnalyseTake` is the only heavy one: it decodes the PCM the browser sent,
builds the take's segment graph, and hands that graph to `ScorePass`, which
walks it and hangs a `Reading` off every segment for every dimension.

Audio never touches disk. Only the derived numbers persist.
"""

import uuid;
import from datetime { datetime }

import from engine.dsp { HOP_S, decode_pcm, analyze_frames }
import from engine.dimensions {
    TakeContext, build_context, window_of, score_window
}
import from engine.segmentation { segment_bounds, ribbon }
import from engine.asr { transcribe, best_utterance, ASR_SIZE }
import from engine.model {
    Take, Segment, Reading, Rank, Holds, Covers, Scores, Rates,
    TakeReport, TakeSummary, SegmentReport, DimensionReport, Moment,
    RankRow, Transcript, Word
}
import from engine.coach { coach_take }
import from engine.scoring { r2 }


"""Take-level moments: earliest first, at most two per dimension.

Every segment flagging the same finding produces one identical note per
segment, which reads as noise rather than as a timeline. Capping per dimension
keeps the list varied and scannable; the per-segment lists keep everything.
"""
def curate_moments(items: list[Moment]) -> list[Moment] {
    ordered = sorted(items, key=moment_time);
    seen: dict[str, int] = {};
    out: list[Moment] = [];
    for m in ordered {
        taken = seen.get(m.dimension, 0);
        if taken >= 2 { continue; }
        seen[m.dimension] = taken + 1;
        out.append(m);
    }
    return out;
}


"""A short human label for an unnamed take."""
def default_label(when: datetime) -> str {
    return "Take " + when.strftime("%b %d, %H:%M");
}


# Sort keys as named functions rather than lambdas: jaclang 0.16.7 miscompiles
# braced lambdas inside walker abilities (runtime NameError), and newer
# jaclang rejects the old `lambda x: T : expr` form. Plain defs run on both.

"""When a moment happens."""
def moment_time(m: Moment) -> float { return m.t; }

"""When a take was recorded."""
def summary_created(s: TakeSummary) -> str { return s.createdAt; }

"""A segment's position in the take."""
def segment_idx(s: SegmentReport) -> int { return s.idx; }

"""A leaderboard entry's score."""
def rank_score(x: RankRow) -> float { return x.score; }


# --- Walkers ---------------------------------------------------------------

"""Walks a take's segments and scores every delivery dimension on each one."""
walker ScorePass {
    has ctx: TakeContext;
    has segments: list[SegmentReport] = [];
    has moments: list[Moment] = [];

    can enter_take with Take entry {
        visit [-->[?:Segment]];
    }

    can score_segment with Segment entry {
        w = window_of(self.ctx, here.f_start, here.f_end, here.trail);
        scored = score_window(self.ctx, w, False);
        here.score = scored.overall;

        for d in scored.dimensions {
            here +>:Scores:+> Reading(
                dimension=d.key, score=d.score, band=d.band,
                headline=d.headline, detail=d.detail
            );
        }

        here.text = w.text;
        here.kind = w.kind;

        words: list[Word] = [];
        spoken = best_utterance(self.ctx.transcript, here.start, here.end);
        if len(spoken) > 0 { words = spoken[0].words; }

        self.segments.append(SegmentReport(
            idx=here.idx,
            start=here.start,
            end=here.end,
            score=scored.overall,
            headline=scored.dimensions[0].headline,
            text=w.text,
            kind=w.kind,
            words=words,
            dimensions=scored.dimensions,
            moments=scored.moments
        ));
        self.moments += scored.moments;
    }
}


"""Analyse a recording and persist the take. The app's one heavy endpoint."""
walker:pub AnalyseTake {
    has audio: str = "";
    has label: str = "";
    has purpose: str = "";
    has reports: list[TakeReport] = [];

    can run with Root entry {
        samples = decode_pcm(self.audio);
        fd = analyze_frames(samples);
        # The transcript is what makes intonation and stress judgeable, so it
        # runs before scoring and rides along in the context.
        tr = transcribe(samples, ASR_SIZE);
        ctx = build_context(fd, tr);
        bounds = segment_bounds(ctx);
        # So take-level intonation judges the same windows the segments do.
        ctx.bounds = bounds;

        now = datetime.now();
        take = (here +>:Holds:+> Take(
            uid=uuid.uuid4().hex,
            label=self.label if self.label != "" else default_label(now),
            duration=r2(fd.duration),
            created_at=now.isoformat()
        ))[0];

        for i in range(len(bounds)) {
            b = bounds[i];
            next_start = bounds[i + 1][0] if i + 1 < len(bounds) else fd.n_frames;
            take +>:Covers:+> Segment(
                idx=i,
                start=r2(float(b[0]) * HOP_S),
                end=r2(float(b[1]) * HOP_S),
                f_start=b[0],
                f_end=b[1],
                trail=r2(float(next_start - b[1]) * HOP_S)
            );
        }

        pass_ = ScorePass(ctx=ctx);
        _ = take spawn pass_;

        whole = window_of(ctx, 0, fd.n_frames, 0.0);
        overall_scored = score_window(ctx, whole, True);
        take.overall = overall_scored.overall;

        for d in overall_scored.dimensions {
            take +>:Rates:+> Reading(
                dimension=d.key, score=d.score, band=d.band,
                headline=d.headline, detail=d.detail
            );
        }

        advice = coach_take(overall_scored.overall, overall_scored.dimensions, self.purpose);
        take.summary = advice.summary;
        take.transcript = tr.text;

        strands = ribbon(ctx);
        report (TakeReport(
            takeId=take.uid,
            label=take.label,
            createdAt=take.created_at,
            duration=take.duration,
            overall=take.overall,
            summary=advice.summary,
            coaching=advice.drills,
            dimensions=overall_scored.dimensions,
            segments=pass_.segments,
            moments=curate_moments(pass_.moments + overall_scored.moments),
            contour=strands.contour,
            envelope=strands.envelope,
            voicedMask=strands.voiced,
            beats=strands.beats,
            coachedBy=advice.source,
            transcript=tr.text,
            transcriptSource=tr.source,
            transcriptNote=tr.note
        ));
    }
}


"""Every saved take, newest first."""
walker:pub ListTakes {
    has reports: list[list[TakeSummary]] = [];
    has found: list[TakeSummary] = [];

    can collect with Root entry {
        visit [-->[?:Take]];
    }

    can gather with Take entry {
        self.found.append(TakeSummary(
            takeId=here.uid,
            label=here.label,
            createdAt=here.created_at,
            duration=here.duration,
            overall=here.overall
        ));
    }

    can finish with Root exit {
        report sorted(self.found, key=summary_created, reverse=True);
    }
}


"""Rebuild a stored take's report by walking its persisted readings."""
walker:pub LoadTake {
    has takeId: str = "";
    has reports: list[TakeReport] = [];

    can run with Root entry {
        matches = [here -->[?:Take, uid == self.takeId]];
        if len(matches) == 0 {
            report TakeReport();
            return;
        }
        take = matches[0];

        segments: list[SegmentReport] = [];
        for seg in [take ->:Covers:->] {
            dims: list[DimensionReport] = [];
            for rd in [seg ->:Scores:->] {
                dims.append(rebuild(rd));
            }
            segments.append(SegmentReport(
                idx=seg.idx, start=seg.start, end=seg.end,
                score=seg.score,
                headline=dims[0].headline if len(dims) > 0 else "",
                text=seg.text, kind=seg.kind,
                dimensions=dims
            ));
        }

        overall_dims: list[DimensionReport] = [];
        for rd in [take ->:Rates:->] {
            overall_dims.append(rebuild(rd));
        }

        report TakeReport(
            takeId=take.uid,
            label=take.label,
            createdAt=take.created_at,
            duration=take.duration,
            overall=take.overall,
            summary=take.summary,
            dimensions=overall_dims,
            segments=sorted(segments, key=segment_idx),
            transcript=take.transcript,
            transcriptSource="stored" if take.transcript != "" else "none"
        );
    }
}


"""Forget a take and everything hanging off it."""
walker:pub DeleteTake {
    has takeId: str = "";
    has reports: list[bool] = [];

    can run with Root entry {
        matches = [here -->[?:Take, uid == self.takeId]];
        if len(matches) == 0 {
            report False;
            return;
        }
        take = matches[0];
        for seg in [take ->:Covers:->] {
            for rd in [seg ->:Scores:->] { del rd; }
            del seg;
        }
        for rd in [take ->:Rates:->] { del rd; }
        del take;
        report True;
    }
}


"""The board's rows, best take first, capped so it stays a podium not a log."""
def top_ranks() -> list[RankRow] {
    rows: list[RankRow] = [];
    for r in [root.shared -->[?:Rank]] {
        rows.append(RankRow(
            name=r.name, score=r.score, label=r.label, createdAt=r.created_at
        ));
    }
    ordered = sorted(rows, key=rank_score, reverse=True);
    if len(ordered) > 20 { ordered = ordered[0:20]; }
    return ordered;
}


"""Put a name on the public leaderboard for an analysed take.

The entry lives on the shared commons root rather than the session's own
root, so every visitor reads the same board.
"""
walker:pub RankTake {
    has takeId: str = "";
    has name: str = "";
    has reports: list[list[RankRow]] = [];

    can run with Root entry {
        matches = [here -->[?:Take, uid == self.takeId]];
        if len(matches) == 0 {
            report top_ranks();
            return;
        }
        take = matches[0];

        who = self.name.strip();
        if who == "" { who = "Anonymous"; }
        if len(who) > 24 { who = who[0:24]; }

        fresh = (root.shared ++> Rank(
            name=who,
            score=take.overall,
            label=take.label,
            created_at=take.created_at
        ))[0];
        grant(fresh, level=ReadPerm);

        report top_ranks();
    }
}


"""The public leaderboard, readable by anyone."""
walker:pub Leaderboard {
    has reports: list[list[RankRow]] = [];

    can run with Root entry {
        report top_ranks();
    }
}


"""Turn a persisted Reading back into the shape the client renders."""
def rebuild(rd: Reading) -> DimensionReport {
    from_model = DimensionReport(
        key=rd.dimension,
        score=rd.score,
        band=rd.band,
        headline=rd.headline,
        detail=rd.detail
    );
    return from_model;
}
