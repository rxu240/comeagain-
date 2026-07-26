"""Check-time stub for the faster-whisper surface the transcript uses.

Same rationale as `numpy.pyi`: Jac's checker cannot resolve the real package's
types, which leaves every recogniser result as `<Unknown>` and blocks it at the
next typed boundary. Consumed only by `jac check`; `import from faster_whisper`
still binds the real package at runtime.

Deliberately loose (`Any` rather than precise unions) because the checker
rejects some PEP 604 forms inside stubs — the values are narrowed on the Jac
side in `engine/asr.jac`.
"""

from typing import Any, Iterable

class Word:
    start: float
    end: float
    word: str
    probability: float

class Segment:
    id: int
    start: float
    end: float
    text: str
    words: Any
    no_speech_prob: float

class TranscriptionInfo:
    language: str
    language_probability: float
    duration: float

class WhisperModel:
    def __init__(
        self,
        model_size_or_path: str,
        device: str = ...,
        device_index: int = ...,
        compute_type: str = ...,
        cpu_threads: int = ...,
        num_workers: int = ...,
        download_root: Any = ...,
        local_files_only: bool = ...,
    ) -> None: ...
    def transcribe(
        self,
        audio: Any,
        language: Any = ...,
        task: str = ...,
        beam_size: int = ...,
        best_of: int = ...,
        temperature: Any = ...,
        condition_on_previous_text: bool = ...,
        word_timestamps: bool = ...,
        vad_filter: bool = ...,
        vad_parameters: Any = ...,
        without_timestamps: bool = ...,
        initial_prompt: Any = ...,
    ) -> tuple[Iterable[Segment], TranscriptionInfo]: ...
