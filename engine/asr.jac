"""The transcript: what was said, when, and what melody the grammar implies.

Runs locally through faster-whisper (CTranslate2), so a take never leaves the
machine and the transcript costs nothing per minute. The recogniser takes the
*same* float32 array the DSP front-end reads, so there is still no codec and no
ffmpeg anywhere in the server. The Whisper call itself runs in `transcribe_service`
(a sibling process with its own warm-model worker pool), reached over HTTP -
this keeps a slow transcription from blocking the thread pool that also serves
cheap reads like ListTakes/LoadTake.

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

import os;
import base64;
import requests;
import numpy as np;
import from engine.model { Word, Utterance, Transcript }

glob ASR_SIZE: str = "base.en";

# The actual Whisper call lives in a separate process (transcribe_service/),
# so a shared thread pool serving cheap reads (ListTakes, LoadTake) never
# blocks on CPU-bound transcription work. See transcribe_service/main.py for
# the ported logic this used to run inline.
glob TRANSCRIBE_SERVICE_URL: str = os.environ.get(
    "TRANSCRIBE_SERVICE_URL", "http://localhost:8001"
);

"""Transcribe 16 kHz mono float32 audio into sentences with word timings.

`samples` is the array `dsp.decode_pcm` already produced - the recogniser and
the DSP front-end read exactly the same buffer. The actual recognition runs in
`transcribe_service` (a separate process pool, see module docstring) so this
call is a plain HTTP POST rather than an inline model invocation - the shape
of the result is unchanged from when it ran in-process.
"""
def transcribe(samples: np.ndarray, size: str) -> Transcript {
    if len(samples) < 1600 {
        return Transcript(
            source="none", available=False,
            note="Too short to transcribe."
        );
    }

    payload = {
        "samples": base64.b64encode(samples.astype(np.float32).tobytes()).decode("ascii"),
        "size": size
    };

    body: dict = {};
    try {
        resp = requests.post(
            TRANSCRIBE_SERVICE_URL + "/transcribe",
            json=payload,
            timeout=60
        );
        resp.raise_for_status();
        body = resp.json();
    } except Exception as e {
        return Transcript(
            source="unavailable", available=False,
            note="Speech recognition is not installed: " + str(e)
        );
    }

    if not body.get("available", False) {
        return Transcript(
            source=body.get("source", "failed"), available=False,
            note=body.get("note", "Transcription failed.")
        );
    }

    utterances: list[Utterance] = [];
    for u in body.get("utterances", []) {
        words: list[Word] = [
            Word(text=w["text"], start=w["start"], end=w["end"], conf=w["conf"])
            for w in u.get("words", [])
        ];
        utterances.append(Utterance(
            text=u["text"], start=u["start"], end=u["end"],
            kind=u["kind"], expects=u["expects"], words=words
        ));
    }

    return Transcript(
        text=body.get("text", ""), utterances=utterances,
        source=body.get("source", "whisper-" + size), available=True
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
