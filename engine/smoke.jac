"""Runtime smoke test for the DSP front-end against a synthetic signal.

Builds three 200 Hz 'utterances' separated by 500 ms of near-silence, each
amplitude-modulated at 4 Hz to imitate syllable nuclei. Run with
`jac run engine/smoke.jac` and check the printed values against the comments.
"""

import numpy as np;
import from engine.dsp {
    SR, HOP_S, analyze_frames, speech_mask, runs_of, syllable_nuclei
}


"""Synthesise three voiced bursts at a known F0 with 4 Hz syllable modulation."""
def synth() -> np.ndarray {
    f0 = 200.0;
    parts: list[np.ndarray] = [];
    for _i in range(3) {
        t = np.arange(int(1.5 * float(SR))).astype(np.float32) / float(SR);
        # Sawtooth-ish glottal source: a few harmonics keeps autocorrelation honest.
        wave = np.zeros(len(t), dtype=np.float32);
        for h in range(1, 8) {
            wave = wave + (1.0 / float(h)) * np.sin(2.0 * np.pi * f0 * float(h) * t);
        }
        env = 0.5 + 0.5 * np.sin(2.0 * np.pi * 4.0 * t);
        parts.append((wave * env * 0.2).astype(np.float32));
        parts.append(np.zeros(int(0.5 * float(SR)), dtype=np.float32) + 0.0001);
    }
    return np.concatenate(parts).astype(np.float32);
}


with entry:__main__ {
    x = synth();
    fd = analyze_frames(x);
    sm = speech_mask(fd);

    voiced_speech = np.logical_and(fd.voiced, sm);
    vf = fd.f0[np.greater(fd.f0, 0.0)];

    print("duration      ", round(fd.duration, 2), " expect ~6.0");
    print("median f0     ", round(float(np.median(vf)), 1), " expect ~200.0");
    print("speech frames ", int(np.count_nonzero(sm)), "/", fd.n_frames);
    print("speech runs   ", len(runs_of(sm)), " expect 3");
    print("pause runs    ", len(runs_of(np.logical_not(sm))));
    print("syllables     ", len(syllable_nuclei(fd, voiced_speech)), " expect ~18 (4Hz x 1.5s x 3)");
    print("mean hf_ratio ", round(float(np.mean(fd.hf_ratio)), 3));
}
