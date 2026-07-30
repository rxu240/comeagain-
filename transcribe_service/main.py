"""Standalone transcription service.

Ported from tonecraft/engine/asr.jac's transcribe() so the CPU-bound Whisper
call runs in its own process pool instead of inline inside a Jac walker's
shared request thread pool. Every concurrent AnalyseTake used to compete for
the same threads that also serve cheap reads (ListTakes, LoadTake); this
service isolates that one expensive call behind a bounded worker pool with a
warm model per worker, so the main app's thread pool never blocks on it.

Contract: POST /transcribe {"samples": <base64 f32le bytes>, "size": "base.en"}
returns the same shape as engine/asr.jac's Transcript/Utterance/Word objects.
"""

import base64
import os
from concurrent.futures import ProcessPoolExecutor
from contextlib import asynccontextmanager

import numpy as np
from fastapi import FastAPI
from pydantic import BaseModel

ASR_SIZE_DEFAULT = "base.en"

# Wh-questions asking for new information fall; only yes/no and declarative
# questions reliably rise. Sorting on "?" alone marks a correct wh-question as
# uptalk, so the lead word is part of the decision.
WH_WORDS = ["what", "why", "how", "when", "where", "who", "whom", "whose", "which"]

SENT_END = ".?!"

# Whisper invents words in trailing room noise: on the reference take the five
# real sentences came back at no_speech_prob 0.000 and mean confidence >= 0.94,
# while a hallucinated "post." came back at 0.317 / 0.24. Both gates are cheap
# and the margin between the two populations is wide.
MAX_NO_SPEECH = 0.25
MIN_CONFIDENCE = 0.5

# A token that begins with one of these attaches to the previous word with no
# space, which is what keeps "sign-ups?" from being rebuilt as "sign -ups?".
NO_SPACE_BEFORE = "-'’,.?!;:)]}%…"

# Constructing a WhisperModel costs ~2.4s, so each worker process builds it
# once (via the pool initializer below) and keeps it for the process lifetime.
_MODELS: dict = {}


def get_model(size: str):
    if size not in _MODELS:
        from faster_whisper import WhisperModel

        _MODELS[size] = WhisperModel(size, device="cpu", compute_type="int8")
    return _MODELS[size]


def _warm_model():
    """Pool initializer: build the default model once per worker process."""
    get_model(ASR_SIZE_DEFAULT)


def classify(text: str) -> tuple[str, str]:
    t = text.strip()
    if len(t) == 0:
        return ("fragment", "level")

    tail = t[-1]
    head = t.lower().lstrip("\"'([- ")
    lead = head.split(" ")[0].strip(",.?!;:\"')")

    if tail == "?":
        if lead in WH_WORDS:
            return ("wh", "fall")
        return ("yesno", "rise")
    if tail == "!":
        return ("exclamation", "fall")
    if tail == ".":
        return ("statement", "fall")
    return ("fragment", "level")


def closes_sentence(w: str) -> bool:
    t = w.strip()
    if len(t) == 0:
        return False
    return t[-1] in SENT_END


def join_words(run: list[dict]) -> str:
    out = ""
    for w in run:
        piece = w["text"]
        if len(piece) == 0:
            continue
        if len(out) > 0 and piece[0] not in NO_SPACE_BEFORE:
            out += " "
        out += piece
    return out.strip()


def mean_conf(run: list[dict]) -> float:
    if len(run) == 0:
        return 0.0
    total = sum(w["conf"] for w in run)
    return total / float(len(run))


def utterance_of(run: list[dict]) -> dict:
    text = join_words(run)
    kind, expects = classify(text)
    return {
        "text": text,
        "start": round(run[0]["start"], 2),
        "end": round(run[-1]["end"], 2),
        "kind": kind,
        "expects": expects,
        "words": run,
    }


def split_sentences(words: list[dict]) -> list[dict]:
    out = []
    run: list[dict] = []
    for w in words:
        run.append(w)
        if closes_sentence(w["text"]):
            out.append(utterance_of(run))
            run = []
    if len(run) > 0:
        out.append(utterance_of(run))
    return out


def transcribe_sync(samples: np.ndarray, size: str) -> dict:
    """The heavy call. Runs inside a worker process, off the async event loop."""
    if len(samples) < 1600:
        return {"text": "", "utterances": [], "source": "none",
                "available": False, "note": "Too short to transcribe."}

    try:
        model = get_model(size)
    except Exception as e:
        return {"text": "", "utterances": [], "source": "unavailable",
                "available": False,
                "note": "Speech recognition is not installed: " + str(e)}

    utterances: list[dict] = []
    try:
        result = model.transcribe(
            samples,
            word_timestamps=True,
            vad_filter=True,
            beam_size=5,
            condition_on_previous_text=False,
        )
        for seg in list(result[0]):
            raw = seg.words
            if raw is None:
                continue
            if float(seg.no_speech_prob) > MAX_NO_SPEECH:
                continue

            words: list[dict] = []
            for w in list(raw):
                token = str(w.word).strip()
                if len(token) == 0:
                    continue
                words.append({
                    "text": token,
                    "start": round(float(w.start), 2),
                    "end": round(float(w.end), 2),
                    "conf": round(float(w.probability), 2),
                })
            if len(words) == 0:
                continue
            for u in split_sentences(words):
                if mean_conf(u["words"]) >= MIN_CONFIDENCE:
                    utterances.append(u)
    except Exception as e:
        return {"text": "", "utterances": [], "source": "failed",
                "available": False, "note": "Transcription failed: " + str(e)}

    if len(utterances) == 0:
        return {"text": "", "utterances": [], "source": "whisper-" + size,
                "available": False, "note": "No speech was recognised in this take."}

    full = " ".join(u["text"] for u in utterances).strip()
    return {"text": full, "utterances": utterances,
            "source": "whisper-" + size, "available": True, "note": ""}


_pool: ProcessPoolExecutor | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _pool
    workers = max(1, int(os.environ.get("TRANSCRIBE_WORKERS", os.cpu_count() - 1 or 1)))
    _pool = ProcessPoolExecutor(max_workers=workers, initializer=_warm_model)
    yield
    _pool.shutdown(wait=False, cancel_futures=True)


app = FastAPI(lifespan=lifespan)


class TranscribeRequest(BaseModel):
    samples: str  # base64-encoded little-endian float32 PCM
    size: str = ASR_SIZE_DEFAULT


@app.post("/transcribe")
async def transcribe(req: TranscribeRequest):
    raw = base64.b64decode(req.samples)
    samples = np.frombuffer(raw, dtype=np.float32)

    import asyncio
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(_pool, transcribe_sync, samples, req.size)


@app.get("/health")
async def health():
    return {"status": "ok"}
