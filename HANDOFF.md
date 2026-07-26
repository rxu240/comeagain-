# TONECRAFT — handoff, 2026-07-26 ~14:45 PDT

Session added a **transcript**, rewrote **intonation** and **stress**, and fixed
the **score scale**. Written for someone picking this up cold. Every claim is
labelled **VERIFIED** (I ran it and read the output), **ASSUMED** (never
executed), or **BLOCKED**.

JacHacks SF hacking window closes **19:15 PDT**.

---

## 0. ONE THING IS BROKEN RIGHT NOW — **RESOLVED 2026-07-26 ~14:15**

Fix (a) below was applied: `fixture-speech.b64` regenerated from the wav,
`load_wav` replaced with `decode_pcm(open("fixture-speech.b64").read())`,
`wave.pyi` deleted. **VERIFIED** — `jac check` passes on all four entry files,
`jac run verify.jac` holds all assertions with the exact §5 values, and
`jac run selftest.jac` passes. Everything is committed (`49df4be`).
The rest of this section is kept as the record of the dead end.

`verify.jac` **did not type-check.** Everything else did.

```
main.jac         1 passed
api.sv.jac       1 passed
selftest.jac     1 passed
verify.jac       1 failed        <-- 5 errors, 36 warnings
```
**VERIFIED** — ran `jac check` on each, 2026-07-26 14:40.

Verbatim errors:
```
[ERROR] error[E1055]: No matching overload found for method "__truediv__" with the given arguments
  --> verify.jac:63:21
[ERROR] error[E1053]: Cannot assign <Unknown> to parameter 'obj' of type Sized
  --> verify.jac:69:29
[ERROR] error[E1032]: Type is Unknown, cannot access attribute "astype"
  --> verify.jac:74:23
[ERROR] error[E1053]: Cannot assign <Unknown> to parameter 'samples' of type ndarray
  --> verify.jac:82:25
```

### Why

I deleted `fixture-speech.b64` (592 KB of base64) and rewrote `verify.jac`'s
`load_wav()` to read `fixture-speech.wav` through the stdlib `wave` module
instead. `raw = w.readframes(...)` resolves to **Unknown**, and that Unknown
propagates into every numpy call that touches the buffer.

I wrote `wave.pyi` (in the repo root, beside `verify.jac`) to type it. **It did
not help** — a hand-written `.pyi` shadowing a *stdlib* module does not appear to
be consumed by `jac check`, unlike `engine/numpy.pyi` which shadows a
site-packages module and works fine. **VERIFIED as a dead end** — three attempts:

1. Chained `np.frombuffer(raw, ...).astype(np.float32) / 32768.0` → E1055.
2. Split into `ints: np.ndarray = ...;` then `x = ints / 32768.0;` (the exact
   two-step form `dsp.decode_pcm` uses successfully) → same E1055.
3. Pre-declared `raw: bytes = b"";` before the `with` block in case it was
   `with`-scoping → same E1055.

The chain is identical to the one in `engine/dsp.jac:38-42`, which checks clean.
The only difference is where `raw` comes from: `base64.b64decode()` (typed) vs
`wave.readframes()` (Unknown). That isolates the cause to the `wave` stub.

### Two ways to fix — pick one

**(a) Fastest, guaranteed.** Regenerate the base64 fixture, revert `load_wav`,
delete `wave.pyi`. `decode_pcm` already types cleanly. Cost: 592 KB of base64 in
the repo.

```bash
cd /c/jh/tonecraft && /c/jh/.venv/Scripts/python.exe -c "
import wave, numpy as np, base64
with wave.open('fixture-speech.wav','rb') as w:
    sr,nch = w.getframerate(), w.getnchannels(); raw=w.readframes(w.getnframes())
x = np.frombuffer(raw,dtype=np.int16).astype(np.float32)/32768.0
if nch>1: x=x.reshape(-1,nch).mean(axis=1)
n=int(len(x)*16000/sr)
x=np.interp(np.linspace(0,len(x)-1,n),np.arange(len(x)),x).astype(np.float32)
pcm=(np.clip(x,-0.99,0.99)*32767).astype(np.int16)
open('fixture-speech.b64','w').write(base64.b64encode(pcm.tobytes()).decode())
"
```
then in `verify.jac` restore `samples = decode_pcm(open("fixture-speech.b64").read());`
and re-add `decode_pcm` to the `engine.dsp` import (currently imports `SR`).

**(b) What I was about to do.** Drop `wave`; read the file with builtin
`open(path,"rb").read()` (returns `bytes`, a known type) and locate the `data`
chunk by searching for the marker rather than assuming a 44-byte header.
**ASSUMED** — not written, not tested.

---

## 1. What was wrong before this session, and what it is now

### 1a. Stress measured nothing — **VERIFIED, fixed**

`dim_stress` counted the share of syllables whose prominence **z-score** cleared
a fixed `0.55`. A z-score is taken against the speaker's own mean, so that share
is pinned by the shape of a normal distribution, not by the speech.

Simulated across a 20× range of real expressiveness (`0.6*z_db + 0.4*z_f0 > 0.55`,
400 trials each, 40 nuclei):

| delivery | dB sd | old raw metric | old score |
|---|---|---|---|
| robotic monotone | 0.2 | 0.014 | 30.4 |
| very flat | 1.0 | 0.221 | **92.0** |
| normal | 4.0 | 0.225 | **92.5** |
| expressive | 8.0 | 0.225 | **92.5** |
| theatrical | 20.0 | 0.223 | **92.3** |

**The raw metric moved 0.221 → 0.223 across a twentyfold range.** Every human
scored ~92.

Now measured as the **absolute** dB/semitone gap between the top third and bottom
third of syllables (`engine/stress.jac:emphasis_range`), plus accent *placement*
from the transcript (content word vs function word):

| delivery | new dB gap | new score |
|---|---|---|
| robotic monotone | 0.4 | 23.8 |
| very flat | 2.2 | 53.5 |
| normal | 8.7 | 97.5 |
| expressive | 17.3 | 53.1 |
| theatrical | 43.2 | 5.0 |

The same fixed-`0.55` threshold was also selecting the prosody ribbon's beat
markers in `engine/segmentation.jac`; that now takes the top third by rank.

### 1b. Intonation wanted everything to fall — **VERIFIED, fixed**

Old target: `lo_ideal=-8.0, hi_ideal=-0.5` — i.e. every phrase ending should
fall. A correctly-rising yes/no question was scored as uptalk.

Now driven by sentence form from the transcript (`engine/asr.jac:classify`):

| form | example | expected terminal |
|---|---|---|
| statement | "We shipped three features this month." | fall |
| yes/no question | "Did you see the revenue line?" | **rise** |
| wh-question | "What drove the increase in sign-ups?" | **fall** |
| fragment (no terminal punctuation) | — | level, not penalised |

**The wh-question row is the subtle one.** Sorting on `?` alone is wrong in the
opposite direction: a wh-question is already marked as a question by its grammar,
so English lets it fall like a statement. Source: Pronuncian / Baruch CUNY TFCS,
and it is why the classifier branches on the lead word, not just punctuation.

### 1c. `terminal_slope` produced impossible numbers — **VERIFIED, fixed**

Was a `np.polyfit` slope over whatever frames happened to be voiced in the last
400 ms, scaled by 0.4. When only a few scattered frames survived, the fit spanned
tens of milliseconds and extrapolated to nonsense. Observed on the reference
take: **−8.28, +11.82, −11.59, +20.00 (clamped), +14.68 st**. A real declarative
fall is 2–6 st.

Now a **median-to-median** difference between the last third and first third of
reliable frames in a 450 ms window (`TERMINAL_FRAMES = 45`). Same take:
**−5.03, +8.49, −2.45, −1.93, +2.19 st**.

### 1d. Pitch tracker octave errors were being scored as speech — **VERIFIED, fixed**

This is what actually caused 1c's worst case. Raw F0 dump over the end of
segment 3 ("What drove the increase in sign-ups?"), male voice, ~85 Hz median:

```
78@-27 111@-28 144@-32 -@-40 -@-47 -@-50 -@-53 -@-45 129@-40 -@-34 -@-31 -@-28
372@-25 311@-25 249@-24 249@-24 249@-23 177@-24 177@-24 356@-25 225@-31 ...
```
(format: `Hz@dB`, `-` = unvoiced.) The final `s` of "sign-ups" tracked at
**249–379 Hz** — three to four times the speaker's pitch, at −23 to −45 dB.

Fix (`engine/dimensions.jac:reliable`): reject frames more than an octave from
the speaker's median (`MAX_F0_DEVIATION = 12.0` semitones) or more than
`RELIABLE_DB_DROP = 25.0` dB below the window's own speech peak. Everything that
reads pitch goes through it, because the same artifacts were corrupting pitch
span too — take-level pitch went **90.5 → 99.4** once they were excluded.

Segment 3's terminal went **+15.0 (clamped garbage) → −1.93 st**, and its
intonation verdict from "Statement ending on a rise" to "Lands the way it
should." That is the wh-question falling correctly, as predicted.

### 1e. The score scale used 20% of its range — **VERIFIED, fixed**

`band_score` returned **90–100** for anything inside the target band, then fell
to ~30 outside. "Textbook" and "barely acceptable" were 10 points apart, so
every dimension in normal speech reported in the nineties. Now **85–100** inside,
**25–85** tapering out, **<25** past the failure bound.

### 1f. Tone was presented as a measurement — **VERIFIED, fixed (labelling only)**

`dim_tone` is a weighted mean of the other seven (`engine/dimensions.jac:609`),
and take-level `overall` **is just the tone score**. It is now labelled as a
composite in `DIMENSION_BLURBS`, its metric row reads "Derived from 7
dimensions", and the README says so. **Not** made into a real measurement — real
voice quality (jitter, spectral tilt) is open work.

### 1g. Take-level numbers contradicted the segments they summarised — **VERIFIED, fixed**

Two separate bugs, both found by reading output that looked wrong:

- Take intonation reported **0/5 endings correct while the segments it summarises
  scored 91, 95 and 93.** Cause: the take-level loop built its own windows from
  Whisper's word timestamps, which are ~100 ms coarser than the pause-based
  segment bounds, so it measured the terminal on the pre-final syllable.
  Fix: `TakeContext.bounds` carries the same spans the segment pass uses. Set it
  in `api.sv.jac` after `segment_bounds(ctx)`.
- Take stress read **86 while every segment read 22–30.** Cause: measured across
  the whole take it picks up loudness differences *between* utterances, which is
  volume consistency, not stress. Fix: `window_emphasis` averages the per-phrase
  contrast when `whole=True`.

Also: the take headline said "Uptalk on statements" on a single instance.
Now needs `max(2, counted // 4)` before naming a pattern.

---

## 2. New files

| file | what |
|---|---|
| `engine/asr.jac` | transcript: words, timings, sentence form → expected contour |
| `engine/stress.jac` | `emphasis_range`, `placement`, `FUNCTION_WORDS` |
| `engine/faster_whisper.pyi` | check-time stub |
| `engine/cmudict.pyi` | check-time stub |
| `verify.jac` | real-speech harness with assertions — **currently broken, §0** |
| `fixture-speech.wav` | 13.89 s, 5 sentences, known ground truth |
| `wave.pyi` | **delete this** if you take fix (a) |

Modified: `api.sv.jac`, `engine/{dimensions,model,scoring,segmentation}.jac`,
`engine/numpy.pyi` (added `reshape`), `components/{ResultsView,SegmentList,SegmentSheet}.cl.jac`,
`requirements.txt`, `Dockerfile`, `README.md`.

**Nothing is committed.** `git status` shows 12 modified, 7 untracked.

---

## 3. Transcription — free, local, verified

`faster-whisper==1.2.1` (CTranslate2, `base.en`, int8) + `cmudict==1.1.3`.
No API key, no per-minute cost, audio never leaves the machine. Resolves cleanly
against the existing `numpy 2.5.1` / `jaclang 0.16.7` venv — **VERIFIED** via
`pip install --dry-run` before installing.

**VERIFIED** on `fixture-speech.wav`: 5/5 sentences correct, `?` preserved on
both questions, word-level timings, **7.0× realtime** (13.89 s audio → 1.99 s),
transcript identical across four different TTS rates and two voices.

It reads the **same float32 array** `analyze_frames` does, so there is still no
codec and no ffmpeg in the server.

### Hallucination filter — **VERIFIED**

Whisper invented `"post."`, `"Kind"`, `"of"` in trailing room noise. Confidence
separates cleanly:

```
nsp=0.000 meanconf=0.94  'The quarterly numbers came in ahead of plan.'
nsp=0.000 meanconf=0.99  'Did you see the revenue line?'
nsp=0.000 meanconf=1.00  'This is the part that matters most.'
nsp=0.317 meanconf=0.24  'post.'                                  <-- junk
```
Gates: `MAX_NO_SPEECH = 0.25`, `MIN_CONFIDENCE = 0.5`. `beam_size=5` also removes
it on its own; both are in place. Word joining respects `NO_SPACE_BEFORE` so
`"sign-ups?"` is not rebuilt as `"sign -ups?"`.

### Degradation — **ASSUMED, not tested**

`transcribe()` catches import and runtime failure and returns
`Transcript(available=False)` with a note; `take_intonation` then scores melody
only and says "endings not checked". **I never ran with faster-whisper
uninstalled**, so the fallback path is code-reviewed, not executed.

---

## 4. Prior art — the check I skipped the first time

Closest match is **SpeakEasy** (UC Berkeley AI Hackathon 2024): Whisper
word-level timestamps → per-sentence segmentation → prosody → LLM feedback, with
explicit "sentence-by-sentence feedback". **Architecturally the same shape as
this.** It calls **Hume AI**, which returns *emotion* labels ("excitement",
"interest") rather than delivery measured in physical units — that is the actual
remaining gap, and it is narrower than I first implied.

Others: **Talky** (nwHacks 2018, 3 awards — pauses, loudness, rate),
**Jabber AI** (Berkeley 2024, Hume prosody, real-time), **Orator** (nathacks
2025, 3rd — STT + YOLO gestures + EEG, no prosody), **ArticuLab** (TreeHacks
2023, VR). Commercial: Speeko tracks intonation explicitly; Orai / Yoodli /
Poised track pace, fillers, tone.

**The load-bearing find:** **AuToBI** (Rosenberg) does automatic ToBI annotation
— pitch-accent detection 73.5%, phrase-boundary detection 90.8% — and
**"requires an input segmentation of the signal into words."** **Wav2ToBI**
(Interspeech 2023) reaches F1 0.82/0.86. This is the external confirmation that
stress and intonation are not measurable without a transcript, i.e. that points
1–4 of the critique were one problem.

No JacHacks SF 2026 project gallery was published yet at time of search, so
same-event overlap is **unknown**. Devpost's own search needs JS and returned
empty via WebFetch; individual project pages fetch fine.

---

## 5. Verified end-to-end

**HTTP** — `POST /walker/AnalyseTake`, real speech: **200, ok=True, 707,984
bytes, 1.98 s**. Response envelope is `{ok, type, data, error, meta}` and the
report is at **`data.reports[0]`** — not `reports[0]`; my first probe script got
this wrong and silently printed `None` for everything.

Per-segment from that response:

| # | text | kind | intonation | stress |
|---|---|---|---|---|
| 0 | The quarterly numbers came in ahead of plan. | statement | 91.1 lands as it should | 91.3 |
| 1 | Did you see the revenue line? | yesno | 73.8 question lifts | 52.2 too even |
| 2 | We shipped three features this month. | statement | 95.1 lands as it should | 90.7 |
| 3 | What drove the increase in sign-ups? | **wh** | **92.8 lands as it should** | 99.3 |
| 4 | This is the part that matters most. | statement | 71.0 ending on a rise | 72.0 swinging hard |

Take-level intonation **85.4** now sits inside the segment range 71.0–95.1.

**Browser** — real Chrome, upload → results. Transcript section renders with a
`WHISPER-BASE.EN` source badge; every list row shows its own words; drawer shows
the blockquote plus `WH-QUESTION - SHOULD FALL, LIKE A STATEMENT`. **VERIFIED**
by screenshot and by `read_page` accessibility dump:

```
"0:00-0:02" / "The quarterly numbers came in ahead of plan." / "Volume 80 · Level swings hard"
"0:03-0:04" / "Did you see the revenue line?"                / "Stress 52 · Emphasis is too even"
"0:05-0:07" / "We shipped three features this month."         / "Volume 71 · Level swings hard"
"0:08-0:10" / "What drove the increase in sign-ups?"          / "Volume 83 · Level swings hard"
"0:11-0:13" / "This is the part that matters most."           / "Intonation 71 · Statement ending on a rise"
```

`verify.jac` assertions, **before** the `wave` rewrite broke it — these all
passed and are the thing to get running again:
```
form classification ....... ok  [('statement','fall'),('yesno','rise'),('statement','fall'),('wh','fall'),('statement','fall')]
terminal contours ........ ok  [-5.0, 8.4, -2.4, -1.9, 2.1]
take/segment coherence ... ok  take=85.4 segments=71.0-95.1
stress discriminates ..... ok  spread=47.0 over [91.3, 52.2, 90.7, 99.3, 72.0]
all assertions held.
```

`selftest.jac` still passes on the synthetic fixture. **Note:** it reports
`transcriptSource='none'` — correct, because `fixture-take.wav` is synthetic
harmonics with no words. **That fixture can never test the transcript**, which is
why `fixture-speech.wav` exists.

---

## 6. Still not verified

- **Microphone capture.** Unchanged from before this session and still the
  largest untested surface. No audio input device available. Upload is the only
  verified path. Half of "either upload or record".
- **`docker build`.** Never run. I added a model-prefetch layer
  (`ENV HF_HOME=/opt/models` + a `WhisperModel(...)` call) so a cold start does
  not block on a ~75 MB download — **ASSUMED correct, never built.** This is the
  highest-risk untested change I made, because it is a new build step.
- **Deploy.** Still blocked; see the `tonecraft-hosting-blocked` memory. The
  image is now larger (model weights + ctranslate2 + onnxruntime), which makes
  the payload-size blocker worse, not better.
- **`transcriptNote` UI branch.** Renders only when transcription fails; never
  triggered.
- **byLLM coaching** with a real `ANTHROPIC_API_KEY`. Never set; `coachedBy` was
  always `"rules"`.
- **`LoadTake` over HTTP with a transcript.** `Take.transcript` is persisted and
  `LoadTake` returns it with `transcriptSource="stored"`, verified only in-process
  via `selftest.jac`, not over HTTP.

---

## 7. Two operational traps that cost real time today

**`Invalid anchor id` (already in memory, hit it anyway).** Deleting `.jac/data`
while a browser holds a session cookie gives:
```
ValueError: Invalid anchor id a358d1f84b3c4501bad4c8ee0476de53 !
```
and the UI shows "The analyser did not respond … (TypeError: Failed to fetch)" —
which looks like a server crash but is not. The server keeps answering `GET /`
with 200. Fix: stop server → `rm -rf .jac/data` → restart → **use a different
cookie host** (`localhost` vs `127.0.0.1` are separate). Better: don't delete
`.jac/data` at all. I deleted it twice and burned both origins' cookies.

**The server can hang rather than die.** After heavy use `curl` returned `000`
(connection refused) while `tasklist` still showed one `jac.exe`, and the last
log lines were `GET /static/manifest.json 500`. `taskkill //F //IM jac.exe` and
restart. Budget ~30 s for startup with `--client pwa`.

**New Jac gotcha, not yet in memory:** inside a JSX slot body you must **not**
re-wrap a nested conditional in braces. Verbatim:
```
C:\jh\tonecraft\components\SegmentSheet.cl.jac, line 62, col 21: Redundant '{...}'
slot wrapping inside a JSX slot body — slot bodies are already in slot mode.
Drop the outer braces: write 'if ... { ... }' directly instead of '{if ... { ... }}'.
```
So `{if x { ... }}` at the top level of a component, but bare `if x { ... }`
inside another `{if ... { ... }}` block.

---

## 8. 40% Jac rule

`4,419` lines of hand-written Jac (excluding `.jac/` build output and generated
`components/ui/*`) against `660` lines of everything else (`global.css`, four
`.pyi` stubs, `jac.toml`, `requirements.txt`, `Dockerfile`) — **~87% Jac**,
unchanged in character by this session's additions. All new engine code is `.jac`;
the only new non-Jac files are check-time type stubs, which the `jac-types` guide
sanctions and which are never imported at runtime.

---

## 9. Suggested order from here

1. **Fix `verify.jac`** (§0, option (a) is ~5 minutes). Nothing else should be
   claimed working until the assertion harness runs again.
2. `jac run verify.jac` and `jac run selftest.jac` — both must pass.
3. `git add -A && git commit` — the rubric says the repo will be checked, and
   right now none of today's work is committed.
4. Only then, if time: `docker build` (§6), or the microphone path.

Do **not** move the UI to `.tsx` and do not "simplify" the `.pyi` stubs away —
both would breach the 40% rule the project is judged on.
