# TONECRAFT

**Delivery analysis for people who speak for a living.** Record or upload a
take; TONECRAFT measures eight dimensions of *how* you said it — tone, pitch,
pacing, pausing, volume, intonation, stress, articulation — and reports on each
utterance separately, so the feedback lands on a specific line rather than on
the recording as a whole.

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

No transcript, no speech recognition. Everything is derived from the signal, so
it works on any language and never depends on what you said.

| Dimension | Measured by | Target band |
|---|---|---|
| **Pitch** | F0 span, p10–p90, in semitones from your own median | 4–12 st |
| **Intonation** | Slope of the last 400 ms of voiced speech per phrase | falling, −8 to −0.5 st |
| **Pacing** | Syllable nuclei ÷ phonation time (articulation rate) | 3.4–5.2 syll/s |
| **Pausing** | Silence share over the take; landing gap per utterance | 8–30% / 0.18–1.0 s |
| **Volume** | Dynamic range p90−p10, plus end-of-line drop detection | 6–18 dB |
| **Stress** | Prominence z-score per nucleus (0.6·loudness + 0.4·pitch) | 16–42% stressed |
| **Articulation** | 2–6 kHz energy share — where consonants live | 18–48% |
| **Tone** | Weighted composite, read out as a plain-language verdict | — |

The front end is a batched autocorrelation pitch tracker (bias-corrected for
lag, parabolic-interpolated, median-filtered against octave errors) and a
de Jong & Wempe style intensity-peak syllable detector. Verified against a
synthetic 200 Hz source: **median F0 within 0.1 Hz**, segment count exact.

Scores use a target band with soft shoulders — full marks inside the band, a
smooth taper to the failure bound, and a floor so one bad number never reads as
zero. The bands come from the delivery literature, not from taste.

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
```

Audio is never written to disk. Only the derived numbers persist.

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
jac run selftest.jac              # synthesises a take, runs the full API path
jac run engine/smoke.jac          # DSP front-end against known ground truth
jac run tools/make_fixture_wav.jac  # writes fixture-take.wav to upload
```

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
  dimensions.jac          the eight dimensions + the Window they read
  segmentation.jac        utterance boundaries, prosody-ribbon resampling
  scoring.jac             target bands, soft shoulders, formatting
  model.jac               graph archetypes + the wire objects the client renders
  coach.jac               deterministic coaching; lazy-loads the LLM layer
  llm_coach.jac           byLLM layer (the only file that imports byllm)
  fixture.jac             synthetic speech-like take for testing
  numpy.pyi               check-time stub — see below
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

## Known limitations

- Syllable counting is intensity-based, so it over-counts on very breathy or
  heavily modulated speech. Rate is reliable; the absolute syllable total is
  approximate.
- Pitch tracking assumes one speaker. Overlapping voices will confuse F0.
- The 2–6 kHz articulation proxy responds to microphone and room as well as to
  the speaker; compare takes recorded on the same setup.
- Analysis is capped at 180 seconds per take.
