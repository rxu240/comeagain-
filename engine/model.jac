"""Graph archetypes and the wire objects the client renders.

The persisted side is a small topology: `root -> Take -> Segment -> Reading`.
Every analysis pass is a walker that traverses it, so adding a ninth delivery
dimension means adding a walker, not editing a pipeline.

The `*Report` objects are the read model. Walkers report them directly, which
gives the React client hydrated, typed instances instead of loose dicts.
"""

glob DIMENSIONS: list[str] = [
    "tone", "pitch", "pacing", "pausing",
    "volume", "intonation", "stress", "articulation"
];

glob DIMENSION_NAMES: dict[str, str] = {
    "tone": "Tone",
    "pitch": "Pitch",
    "pacing": "Pacing",
    "pausing": "Pausing",
    "volume": "Volume",
    "intonation": "Intonation",
    "stress": "Stress",
    "articulation": "Articulation"
};

glob DIMENSION_BLURBS: dict[str, str] = {
    "tone": "A read across the seven measured dimensions - not a separate measurement.",
    "pitch": "Where your voice sits and how far it travels.",
    "pacing": "Syllables per second while you are actually speaking.",
    "pausing": "How often you stop, and whether the stops land well.",
    "volume": "Loudness and whether it holds to the end of a line.",
    "intonation": "The melody of each phrase and how it resolves.",
    "stress": "Which syllables you lean on, and how regularly.",
    "articulation": "Crispness of consonants and edge definition."
};


# --- Persisted graph -------------------------------------------------------

"""One recording session."""
node Take {
    has uid: str = "",
        label: str = "",
        duration: float = 0.0,
        created_at: str = "",
        overall: float = 0.0,
        summary: str = "",
        transcript: str = "";
}

"""A single utterance, bounded by the pauses on either side of it."""
node Segment {
    has idx: int = 0,
        start: float = 0.0,
        end: float = 0.0,
        f_start: int = 0,
        f_end: int = 0,
        trail: float = 0.0,
        score: float = 0.0,
        text: str = "",
        kind: str = "";
}

"""One dimension's verdict, attached either to a Take or to a Segment."""
node Reading {
    has dimension: str = "",
        score: float = 0.0,
        band: str = "steady",
        headline: str = "",
        detail: str = "";
}

"""One name on the public leaderboard, hung off the shared commons root."""
node Rank {
    has name: str = "",
        score: float = 0.0,
        label: str = "",
        created_at: str = "";
}

edge Holds {}
edge Covers: Take --> Segment {}
edge Scores: Segment --> Reading {}
edge Rates: Take --> Reading {}


# --- Transcript ------------------------------------------------------------

"""One recognised word with the span it occupies in the take."""
obj Word {
    has text: str = "",
        start: float = 0.0,
        end: float = 0.0,
        conf: float = 0.0;
}

"""One recognised sentence, and the melody its grammatical form implies.

`kind` is the sentence form (`statement`, `yesno`, `wh`, `exclamation`,
`fragment`); `expects` is the terminal contour that form should land on
(`fall`, `rise`, `level`). They are separate because two different forms can
want the same contour - a wh-question falls exactly like a statement.
"""
obj Utterance {
    has text: str = "",
        start: float = 0.0,
        end: float = 0.0,
        kind: str = "statement",
        expects: str = "fall",
        words: list[Word] = [];
}

"""The transcript for a take, plus an honest note on how it was produced."""
obj Transcript {
    has text: str = "",
        utterances: list[Utterance] = [],
        source: str = "none",
        available: bool = False,
        note: str = "";
}


# --- Wire objects ----------------------------------------------------------

"""One row on the public leaderboard as the client renders it."""
obj RankRow {
    has name: str = "",
        score: float = 0.0,
        label: str = "",
        createdAt: str = "";
}

"""A single labelled number shown under a dimension."""
obj MetricPoint {
    has label: str = "",
        value: str = "";
}

"""One dimension's verdict as the client renders it."""
obj DimensionReport {
    has key: str = "",
        name: str = "",
        blurb: str = "",
        score: float = 0.0,
        band: str = "steady",
        headline: str = "",
        detail: str = "",
        metrics: list[MetricPoint] = [];
}

"""A timestamped observation the user can tap to hear."""
obj Moment {
    has t: float = 0.0,
        tEnd: float = 0.0,
        dimension: str = "",
        severity: str = "note",
        note: str = "";
}

"""Per-utterance findings."""
obj SegmentReport {
    has idx: int = 0,
        start: float = 0.0,
        end: float = 0.0,
        score: float = 0.0,
        headline: str = "",
        text: str = "",
        kind: str = "",
        rate: float = 0.0,
        pitchSt: float = 0.0,
        words: list[Word] = [],
        dimensions: list[DimensionReport] = [],
        moments: list[Moment] = [];
}

"""Everything the results screen needs, in one report."""
obj TakeReport {
    has takeId: str = "",
        label: str = "",
        createdAt: str = "",
        duration: float = 0.0,
        overall: float = 0.0,
        summary: str = "",
        coaching: list[str] = [],
        dimensions: list[DimensionReport] = [],
        segments: list[SegmentReport] = [],
        moments: list[Moment] = [],
        contour: list[float] = [],
        envelope: list[float] = [],
        voicedMask: list[int] = [],
        beats: list[float] = [],
        coachedBy: str = "rules",
        transcript: str = "",
        transcriptSource: str = "none",
        transcriptNote: str = "",
        mode: str = "vc",
        attention: float = 0.0,
        attentionHeadline: str = "",
        attentionDetail: str = "";
}

"""Coaching written for one speaker, one take."""
obj Coaching {
    has summary: str = "",
        drills: list[str] = [],
        source: str = "rules";
}

"""One row in the history list."""
obj TakeSummary {
    has takeId: str = "",
        label: str = "",
        createdAt: str = "",
        duration: float = 0.0,
        overall: float = 0.0;
}
