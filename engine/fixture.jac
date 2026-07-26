"""A synthetic speech-like take, for exercising the pipeline without a mic.

Not a speech synthesiser - it is a signal with the properties the analyser
actually measures: a harmonic-rich voiced source with a falling phrase
contour, 4.5 Hz syllable modulation, fricative noise bursts that put energy in
the consonant band, and real pauses between utterances.
"""

import numpy as np;
import base64;
import from engine.dsp { SR }


"""One utterance: harmonics under a syllable envelope, plus fricative bursts."""
def utterance(base_f0: float, seconds: float, rise: bool, level: float) -> np.ndarray {
    n = int(seconds * float(SR));
    t = np.arange(n).astype(np.float32) / float(SR);
    ramp = t / max(seconds, 0.01);

    # Declarative phrases fall about 3 semitones; a question rises instead.
    shift = 3.0 * ramp if rise else -3.0 * ramp;
    f0 = base_f0 * np.power(2.0, shift / 12.0);
    phase = 2.0 * np.pi * np.cumsum(f0) / float(SR);

    wave = np.zeros(n, dtype=np.float32);
    for h in range(1, 12) {
        wave = wave + (1.0 / float(h * h)) * np.sin(phase * float(h));
    }

    # sin-squared peaks twice per cycle, so 2.25 Hz gives ~4.5 syllables/sec.
    env = 0.45 + 0.55 * np.square(np.sin(2.0 * np.pi * 2.25 * t));
    voiced = wave * env;

    # Fricative bursts: 50 ms of noise roughly every third syllable.
    noise = np.random.normal(0.0, 1.0, n).astype(np.float32);
    burst = np.zeros(n, dtype=np.float32);
    period = int(float(SR) / 2.8);
    k = int(0.05 * float(SR));
    start = int(0.12 * float(SR));
    while start + k < n {
        burst[start:start + k] = 1.0;
        start = start + period;
    }
    fricative = noise * burst * 0.28;

    return ((voiced + fricative) * level).astype(np.float32);
}


"""Four utterances with pauses, as base64 int16 PCM - the browser's wire form."""
def synth_take() -> str {
    np.random.seed(7);
    parts: list[np.ndarray] = [];
    plan = [
        (128.0, 2.4, False, 0.30),
        (140.0, 1.8, False, 0.26),
        (132.0, 2.1, True, 0.22),
        (126.0, 2.6, False, 0.18)
    ];
    gaps = [0.55, 0.85, 0.45, 0.40];

    for i in range(len(plan)) {
        p = plan[i];
        parts.append(utterance(p[0], p[1], p[2], p[3]));
        room = np.random.normal(0.0, 0.0006, int(gaps[i] * float(SR)));
        parts.append(room.astype(np.float32));
    }

    x = np.concatenate(parts);
    x = np.clip(x, -0.99, 0.99);
    pcm = (x * 32767.0).astype(np.int16);
    return base64.b64encode(pcm.tobytes()).decode("ascii");
}
