"""The transcript: what was said, when, and what melody the grammar implies.

Runs locally through faster-whisper (CTranslate2), so a take never leaves the
machine and the transcript costs nothing per minute. The recogniser takes the
*same* float32 array the DSP front-end reads, so there is still no codec and no
ffmpeg anywhere in the server.

Two things come out of here that the acoustics alone cannot supply:

1. **Words with timings**, so a score can be attached to "the revenue line"
   rather than to "second 3.98".
2. **Sentence form**, from terminal punctuation plus the first word. This is
   what makes intonation judgeable at all: English statements fall, yes/no
   questions rise, and wh-questions fall like statements. Without the text
   every rise looks like uptalk, which is exactly the bug this module fixes.

The transcript is strictly optional. If faster-whisper is not installed, every
acoustic dimension still scores and `Transcript.available` is False - the app
degrades, it does not break.
"""

import numpy as np;
import from engine.model { Word, Utterance, Transcript }

glob ASR_SIZE: str = "base.en";

# Wh-questions asking for new information fall; only yes/no and declarative
# questions reliably rise. Sorting on "?" alone marks a correct wh-question as
# uptalk, so the lead word is part of the decision.
glob WH_WORDS: list[str] = [
    "what", "why", "how", "when", "where", "who", "whom", "whose", "which"
];

glob SENT_END: str = ".?!";

# Whisper invents words in trailing room noise: on the reference take the five
# real sentences came back at no_speech_prob 0.000 and mean confidence >= 0.94,
# while a hallucinated "post." came back at 0.317 / 0.24. Both gates are cheap
# and the margin between the two populations is wide.
glob MAX_NO_SPEECH: float = 0.25;
glob MIN_CONFIDENCE: float = 0.5;

# A token that begins with one of these attaches to the previous word with no
# space, which is what keeps "sign-ups?" from being rebuilt as "sign -ups?".
glob NO_SPACE_BEFORE: str = "-'’,.?!;:)]}%…";

# Constructing a WhisperModel costs ~2.4s, so it is built once per size and
# kept. A dict is used rather than a rebound global because mutating a `glob`
# container needs no rebinding.
glob _MODELS: dict[str, any] = {};


"""The recogniser for `size`, constructed on first use and then reused."""
def get_model(size: str) -> any {
    if size not in _MODELS {
        import from faster_whisper { WhisperModel }
        _MODELS[size] = WhisperModel(size, device="cpu", compute_type="int8");
    }
    return _MODELS[size];
}


"""Sentence form and the terminal contour that form should land on.

Returns `(kind, expects)`. A sentence with no terminal punctuation is a
`fragment` - a thought left open, where a level or slightly rising ending is
correct rather than a fault.
"""
def classify(text: str) -> tuple[str, str] {
    t = text.strip();
    if len(t) == 0 { return ("fragment", "level"); }

    tail = t[len(t) - 1];
    head = t.lower().lstrip("\"'([- ");
    lead = head.split(" ")[0].strip(",.?!;:\"')");

    if tail == "?" {
        if lead in WH_WORDS { return ("wh", "fall"); }
        return ("yesno", "rise");
    }
    if tail == "!" { return ("exclamation", "fall"); }
    if tail == "." { return ("statement", "fall"); }
    return ("fragment", "level");
}


"""True if this word closes a sentence, i.e. ends in '.', '?' or '!'."""
def closes_sentence(w: str) -> bool {
    t = w.strip();
    if len(t) == 0 { return False; }
    return t[len(t) - 1] in SENT_END;
}


"""Group a recogniser segment's words into one Utterance per sentence.

Whisper emits a "segment" that can hold several sentences, and per-sentence
intonation needs them apart. Splitting on the word that carries the terminal
punctuation keeps each Utterance's span tight to its own words.
"""
def split_sentences(words: list[Word]) -> list[Utterance] {
    out: list[Utterance] = [];
    run: list[Word] = [];

    for w in words {
        run.append(w);
        if closes_sentence(w.text) {
            out.append(utterance_of(run));
            run = [];
        }
    }
    if len(run) > 0 { out.append(utterance_of(run)); }
    return out;
}


"""Rebuild a sentence from its words, respecting words that hyphenate on."""
def join_words(run: list[Word]) -> str {
    out = "";
    for w in run {
        piece = w.text;
        if len(piece) == 0 { continue; }
        if len(out) > 0 and not (piece[0] in NO_SPACE_BEFORE) { out += " "; }
        out += piece;
    }
    return out.strip();
}


"""Mean recogniser confidence across a run of words."""
def mean_conf(run: list[Word]) -> float {
    if len(run) == 0 { return 0.0; }
    total = 0.0;
    for w in run { total += w.conf; }
    return total / float(len(run));
}


"""Build one Utterance from the words that make it up."""
def utterance_of(run: list[Word]) -> Utterance {
    text = join_words(run);
    form = classify(text);
    return Utterance(
        text=text,
        start=float(round(run[0].start, 2)),
        end=float(round(run[len(run) - 1].end, 2)),
        kind=form[0],
        expects=form[1],
        words=run
    );
}


"""Transcribe 16 kHz mono float32 audio into sentences with word timings.

`samples` is the array `dsp.decode_pcm` already produced - the recogniser and
the DSP front-end read exactly the same buffer.
"""
def transcribe(samples: np.ndarray, size: str) -> Transcript {
    if len(samples) < 1600 {
        return Transcript(
            source="none", available=False,
            note="Too short to transcribe."
        );
    }

    model: any = None;
    try {
        model = get_model(size);
    } except Exception as e {
        return Transcript(
            source="unavailable", available=False,
            note="Speech recognition is not installed: " + str(e)
        );
    }

    utterances: list[Utterance] = [];
    try {
        result = model.transcribe(
            samples,
            word_timestamps=True,
            vad_filter=True,
            beam_size=5,
            condition_on_previous_text=False
        );
        for seg in list(result[0]) {
            raw = seg.words;
            if raw is None { continue; }
            if float(seg.no_speech_prob) > MAX_NO_SPEECH { continue; }

            words: list[Word] = [];
            for w in list(raw) {
                token = str(w.word).strip();
                if len(token) == 0 { continue; }
                words.append(Word(
                    text=token,
                    start=float(round(float(w.start), 2)),
                    end=float(round(float(w.end), 2)),
                    conf=float(round(float(w.probability), 2))
                ));
            }
            if len(words) == 0 { continue; }
            for u in split_sentences(words) {
                if mean_conf(u.words) >= MIN_CONFIDENCE { utterances.append(u); }
            }
        }
    } except Exception as e {
        return Transcript(
            source="failed", available=False,
            note="Transcription failed: " + str(e)
        );
    }

    if len(utterances) == 0 {
        return Transcript(
            source="whisper-" + size, available=False,
            note="No speech was recognised in this take."
        );
    }

    full = " ".join([u.text for u in utterances]).strip();
    return Transcript(
        text=full, utterances=utterances,
        source="whisper-" + size, available=True
    );
}


"""The utterances overlapping a time span, longest overlap first.

Segments come from pauses in the signal and sentences come from the grammar,
so the two do not always line up one-to-one. Ranking by overlap lets a segment
claim the sentence it mostly contains.
"""
def utterances_in(tr: Transcript, start: float, end: float) -> list[Utterance] {
    hits: list[Utterance] = [];
    for u in tr.utterances {
        lo = max(start, u.start);
        hi = min(end, u.end);
        if hi - lo > 0.0 { hits.append(u); }
    }
    return hits;
}


"""The utterance that best matches a span, as a 0- or 1-item list.

A list rather than an optional because it keeps the return type concrete:
`best_utterance(...) as any` at every call site would push the loss of typing
into the callers, which is what the `.pyi` boundary exists to avoid.
"""
def best_utterance(tr: Transcript, start: float, end: float) -> list[Utterance] {
    best: list[Utterance] = [];
    top = 0.0;
    for u in tr.utterances {
        lo = max(start, u.start);
        hi = min(end, u.end);
        overlap = hi - lo;
        if overlap > top { top = overlap; best = [u]; }
    }
    return best;
}
