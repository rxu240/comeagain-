# TONECRAFT

**Delivery analysis for people who speak for a living.** Record or upload a
take; TONECRAFT measures eight dimensions of *how* you said it — tone, pitch,
pacing, pausing, volume, intonation, stress, articulation — and reports on each
utterance separately, so the feedback lands on a specific line rather than on
the recording as a whole.

It transcribes the take too, and the transcript is not a convenience feature:
**intonation and stress are not measurable without knowing the words.** A rise
at the end of "Did you see the revenue line?" is correct; the identical rise on
"This is the part that matters most" is uptalk. The audio is the same either
way — only the text tells them apart. Transcription runs locally, so it costs
nothing per minute and the audio never leaves the machine.

Built at JacHacks SF. Server and client are both written in Jac.

---

## Why this is a Jac project, not a Python project with Jac sprinkled on

The analysis is a graph problem, and Jac's Object-Spatial Programming is the
reason the code is shaped the way it is.

A take becomes a graph:

```
root ──Holds──> Take ──Covers──> Segment ──Scores──> Reading
                  └───Rates────> Reading
```

`ScorePass` is a walker. It enters the `Take`, visits every `Segment`, and
hangs a `Reading` off each one for each of the eight dimensions. Adding a ninth
dimension means writing one function and one line in `score_window` — there is
no pipeline to thread it through, because the traversal is a language
construct rather than a loop someone has to maintain.

The same is true across the network boundary. `walker:pub AnalyseTake` *is* the
`POST /walker/AnalyseTake` endpoint; the React client calls it with
`root spawn AnalyseTake(...)` and gets back hydrated, typed `TakeReport`
objects — no serialisers, no DTOs, no client-side type definitions that can
drift from the server's.

**Composition:** 3,276 lines of hand-written Jac against 499 lines of
everything else (the stylesheet, a numpy type stub, and `jac.toml`) — about
**87% Jac**. Both the backend and the entire React UI are `.jac`.

---

## What it actually measures

Six dimensions come from the signal alone. Two — intonation and stress — also
read the transcript, because they are about the relationship between the melody
and the words.

| Dimension | Measured by | Target band |
|---|---|---|
| **Pitch** | F0 span, p10–p90, in semitones from your own median | 4–12 st |
| **Intonation** | Terminal F0 change per sentence, judged against the contour that sentence's *form* implies | fall −6…−1 st · rise +1…+6 st |
| **Pacing** | Syllable nuclei ÷ phonation time (articulation rate) | 3.4–5.2 syll/s |
| **Pausing** | Silence share over the take; landing gap per utterance | 8–30% / 0.18–1.0 s |
| **Volume** | Dynamic range p90−p10, plus end-of-line drop detection | 6–18 dB |
| **Stress** | Absolute dB/semitone gap between leaned-on syllables and the rest, plus whether accents land on content words | 4–12 dB |
| **Articulation** | 2–6 kHz energy share — where consonants live | 18–48% |
| **Tone** | Weighted mean of the seven above — *not* an independent measurement | — |

Tone is labelled that way deliberately. It is a composite, its card says so, and
its metrics name the two dimensions that moved it, so any number traces back to
something you can hear. Real voice-quality measurement (jitter, spectral tilt —
the cues behind "warm" and "tense") is open work, not something claimed here.

The front end is a batched autocorrelation pitch tracker (bias-corrected for
lag, parabolic-interpolated, median-filtered against octave errors) and a
de Jong & Wempe style intensity-peak syllable detector. Verified against a
synthetic 200 Hz source: **median F0 within 0.1 Hz**, segment count exact.

Scores use a target band with soft shoulders: **85–100** inside the band,
**25–85** tapering out to the failure bound, below 25 past it, with a floor so
one bad number never reads as a flat zero. The bands come from the delivery
literature, not from taste.

### Intonation: statements fall, yes/no questions rise, wh-questions fall

The transcript carries punctuation and the leading word, which is enough to pick
the contour a sentence should land on:

| Sentence form | Example | Expected terminal |
|---|---|---|
| statement | "We shipped three features this month." | fall |
| yes/no question | "Did you see the revenue line?" | **rise** |
| wh-question | "What drove the increase in sign-ups?" | **fall** |
| fragment (no terminal punctuation) | "…and the second thing" | level, not penalised |

The wh-question row is why sorting on `?` alone is not good enough: a question
already marked as one by its grammar normally *falls* in English, so a naive
rule flags a correct delivery as a fault. On the reference take the wh-question
measures −1.9 st and scores 92.8.

### Stress: emphasis range, and whether it lands on the right word

The first version of this dimension counted the share of syllables whose
prominence **z-score** cleared a fixed threshold. A z-score is taken against the
speaker's own mean, so that share is fixed by the shape of a normal distribution
rather than by the speech. Simulated across a twentyfold range of real
expressiveness it moved from 0.221 to 0.223 — every delivery from monotone to
theatrical scored ~92. It measured nothing.

It now measures the **absolute** dB and semitone gap between the syllables you
lean on and the ones you do not, which moves when the delivery moves:

| Delivery | old metric → score | new metric → score |
|---|---|---|
| robotic monotone | 0.014 → 30.4 | 0.4 dB → 23.8 |
| very flat | 0.221 → **92.0** | 2.2 dB → 53.5 |
| normal | 0.225 → **92.5** | 8.7 dB → 97.5 |
| expressive | 0.225 → **92.5** | 17.3 dB → 53.1 |
| theatrical | 0.223 → **92.3** | 43.2 dB → 5.0 |

With a transcript it also checks *placement*: English leaves function words
("the", "of", "is") unaccented, so emphasis landing there is a specific, fixable
habit — and naming the word beats any score.

### Reading pitch reliably

Autocorrelation trackers fail on fricatives and on the low-energy decay at a
phrase end, and they fail *confidently*: the final "s" of "sign-ups?" came back
as a run of 250–380 Hz frames from a speaker whose median is 85 Hz, which pushed
that phrase's terminal reading to the ±15 st clamp. Two gates reject those
frames — nothing beyond an octave from the speaker's own median, and nothing
25 dB below the phrase's own peak. Terminal contours are also taken as a
median-to-median difference across the closing window rather than a
least-squares slope, since a slope fitted to a handful of scattered voiced
frames extrapolates to absurd rates.

### Segment-level feedback

Segments are cut at pauses, so one segment is one thing you said. Each is
scored independently — a take can average 92 while one line inside it scores 76
— and tapping it opens its own eight-dimension readout plus a control that
plays back just those seconds.

Note that per-segment *pausing* deliberately measures something different from
the take-level figure: segments are bounded by pauses by construction, so
scoring their internal silence would mark every utterance down. What matters
for an utterance is the gap it lands into.

---

## Audio path

The browser does all codec work, so the server never needs ffmpeg:

```
MediaRecorder / file upload
  → AudioContext.decodeAudioData        (any container the browser can read)
  → OfflineAudioContext                 (downmix to mono, resample to 16 kHz)
  → Int16Array → base64                 (via FileReader, no manual chunking)
  → root spawn AnalyseTake(...)
      ├─ analyze_frames()  → DSP features on a 10 ms grid
      └─ transcribe()      → words, timings, sentence forms
```

The recogniser reads the **same** float32 array the DSP front-end does, which is
why adding transcription introduced no codec and no ffmpeg dependency.

Audio is never written to disk. Only the derived numbers and the text persist.

### Transcription

`faster-whisper` (CTranslate2, `base.en`, int8) on CPU — no GPU, no API key, no
per-minute cost, no audio leaving the machine. About **7× realtime**: a 14 s
take transcribes in ~2 s, and a full analyse-and-score request over HTTP
measured **1.98 s** end to end.

It is strictly optional. If the package is absent every acoustic dimension still
scores, `Transcript.available` is False, and the intonation card says outright
that endings were not checked rather than guessing. Two things guard against the
recogniser inventing words in room noise: segments above a `no_speech_prob`
threshold are dropped, as are sentences below a mean-confidence floor. On the
reference take the five real sentences came back at `no_speech_prob` 0.000 and
confidence ≥ 0.94, while a hallucinated `"post."` came back at 0.317 / 0.24.

---

## Design

Beige glassmorphism with an inscriptional serif — **Marcellus** for display
(the letterforms of classical rhetoric, which is what the app is about),
**Jost** for body, **IBM Plex Mono** for every number, so measurements read as
instrument output. shadcn/ui supplies the primitives (Drawer, Button, Badge)
through the `jac-super` plugin; they are themed to the beige palette rather
than used as-is.

The signature element is the **prosody ribbon**: the pitch track in semitones
against your own median in the upper lane, the loudness envelope below, pauses
drawn as literal gaps, and brass ticks on stressed syllables. Tapping a band
selects that utterance.

---

## Run it

Requires **Python 3.12+**.

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt      # Windows: .venv\Scripts\pip
jac install                                    # npm deps + Bun for the client
jac start --dev main.jac                       # http://localhost:8000
```

Optional AI coaching layer:

```bash
pip install -r requirements-llm.txt
export ANTHROPIC_API_KEY=sk-ant-...
```

Without it the deterministic coach runs — `byllm` is loaded through `importlib`
and is never imported unless both the key and the package are present.

### Check it without a microphone

```bash
jac run verify.jac                # real speech, known ground truth, asserts
jac run selftest.jac              # synthesises a take, runs the full API path
jac run engine/smoke.jac          # DSP front-end against known ground truth
jac run tools/make_fixture_wav.jac  # writes fixture-take.wav to upload
```

`verify.jac` is the one that covers the transcript work. `fixture-take.wav` is
synthetic harmonics rather than words, so it cannot exercise a recogniser at all;
`fixture-speech.b64` (and the matching `.wav`) is real speech containing three
statements, a yes/no question and a wh-question. The harness prints the
per-sentence detail and then asserts what must not regress: sentence forms
classify correctly, terminal contours stay physically plausible, the take-level
intonation number sits inside the range of the segments it summarises, and the
stress dimension still discriminates between utterances.

---

## Deploy

`jac start` is a normal long-running server, so any process host works:

```bash
docker build -t tonecraft .
docker run -p 8000:8000 tonecraft
```

That image runs on Render, Railway, Fly.io or Cloud Run unchanged. Set
`JAC_DATA_PATH` to a mounted volume to keep takes across restarts.

`jac build --client pwa` produces an installable PWA (manifest + service
worker), and `jac build --client mobile --platform android` wraps the same
client with Capacitor for a store build.

---

## Layout

```
main.jac                  entry — server imports, then the cl { } client block
api.sv.jac                walker:pub endpoints (Analyse/List/Load/Delete)
engine/
  dsp.jac                 framing, RMS, F0 tracking, spectral features, nuclei
  asr.jac                 transcript: words, timings, sentence form → contour
  dimensions.jac          the eight dimensions + the Window they read
  stress.jac              emphasis range and accent placement
  segmentation.jac        utterance boundaries, prosody-ribbon resampling
  scoring.jac             target bands, soft shoulders, formatting
  model.jac               graph archetypes + the wire objects the client renders
  coach.jac               deterministic coaching; lazy-loads the LLM layer
  llm_coach.jac           byLLM layer (the only file that imports byllm)
  fixture.jac             synthetic speech-like take for testing
  numpy.pyi               check-time stubs — see below
  faster_whisper.pyi
  cmudict.pyi
components/*.cl.jac       the React UI, in Jac
lib/audio.cl.jac          capture, decode, resample, encode
styles/global.css         design tokens and the glass system
```

### `engine/numpy.pyi`

Jac's checker can't resolve numpy's own stubs, which leaves every array
expression `<Unknown>` and blocks it at the next typed boundary. This file is
the "type the source" fix the `jac-types` guide recommends: it is read only by
`jac check`, while `import numpy as np` still binds the real package at
runtime. Extend it when the engine reaches for a new numpy call.

Two Jac specifics worth knowing if you edit the engine: comparison operators
always produce `bool`, so element-wise comparisons must go through
`np.greater`/`np.logical_and`; and multi-dimensional subscripts take slices,
not bare scalars (`np.take(a, 0, axis=1)`, not `a[:, 0]`).

---

### If the server starts throwing `ValueError: Invalid anchor id`

Deleting `.jac/data` while a browser still holds a session will do this: the
cookie points at a graph anchor that no longer exists, and the request fails
before your walker runs. Stop the server, remove `.jac/data`, restart, and use
a fresh browser origin (a private window, or `127.0.0.1` instead of
`localhost` — they are separate cookie hosts). Reset persistence with the
server stopped, not while it is running.

---

## Known limitations

- Syllable counting is intensity-based, so it over-counts on very breathy or
  heavily modulated speech (21 vs an expected ~18 on the smoke fixture). Rate is
  reliable; the absolute syllable total is approximate, and the ~17% over-count
  propagates into the words-per-minute figure, which is itself a conversion from
  syllables at a fixed 1.5 syllables/word rather than a measured word count.
- **Tone is a composite, not a measurement** — see above.
- Sentence form comes from the recogniser's punctuation, so it inherits the
  recogniser's mistakes. A missed `?` gets scored as a statement. Declarative
  questions ("You shipped it today?") are marked as statements by punctuation
  alone and will read as uptalk; catching those needs syntax, not punctuation.
- `base.en` is English-only. The acoustic dimensions are language-independent,
  but the intonation-form rules encoded here are English — a language with
  different question prosody would need its own table.
- Pitch tracking assumes one speaker. Overlapping voices will confuse F0.
- The 2–6 kHz articulation proxy responds to microphone and room as well as to
  the speaker; compare takes recorded on the same setup.
- Analysis is capped at 180 seconds per take.
- The **microphone capture path is not verified.** Upload is tested end to end;
  no audio input device was available in the build environment, so recording,
  the level meter, and audio playback render and type-check but have never been
  run against live input.
