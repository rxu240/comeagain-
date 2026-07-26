"""Signal-processing primitives for prosody analysis.

Everything downstream (segmentation, the eight delivery dimensions, coaching)
reads from the single `FrameData` bundle produced by `analyze_frames`. Audio
arrives as 16 kHz mono int16 PCM that the browser already decoded, so this
module never touches a codec.
"""

import numpy as np;
import base64;

glob SR: int = 16000;
glob FRAME: int = 640;
glob HOP: int = 160;
glob HOP_S: float = 0.01;
glob EPS: float = 1e-10;

glob F0_MIN: float = 60.0;
glob F0_MAX: float = 400.0;


"""Per-frame acoustic features on a fixed 10 ms grid."""
obj FrameData {
    has db: np.ndarray,
        f0: np.ndarray,
        voiced: np.ndarray,
        centroid: np.ndarray,
        hf_ratio: np.ndarray,
        flux: np.ndarray,
        n_frames: int = 0,
        duration: float = 0.0,
        noise_floor: float = -60.0,
        speech_floor: float = -40.0;
}


"""Base64 int16 little-endian PCM -> float32 in [-1, 1]."""
def decode_pcm(payload: str) -> np.ndarray {
    raw = base64.b64decode(payload);
    ints = np.frombuffer(raw, dtype=np.int16).astype(np.float32);
    return ints / 32768.0;
}


"""Stack overlapping analysis windows into an (n_frames, FRAME) matrix."""
def frame_matrix(x: np.ndarray) -> np.ndarray {
    if len(x) < FRAME {
        x = np.pad(x, (0, FRAME - len(x)));
    }
    windows = np.lib.stride_tricks.sliding_window_view(x, FRAME);
    return np.ascontiguousarray(windows[::HOP]);
}


"""Per-frame RMS level in dBFS."""
def frame_db(frames: np.ndarray) -> np.ndarray {
    power = np.mean(np.square(frames), axis=1);
    return 10.0 * np.log10(power + EPS);
}


"""5-tap median filter over voiced frames only, to drop octave errors."""
def median_smooth_f0(f0: np.ndarray, voiced: np.ndarray) -> np.ndarray {
    n = len(f0);
    if n < 5 {
        return np.copy(f0);
    }
    padded = np.pad(f0, (2, 2), mode="edge");
    stack = np.lib.stride_tricks.sliding_window_view(padded, 5);
    masked = np.where(np.greater(stack, 0.0), stack, np.nan);
    allnan = np.all(np.isnan(masked), axis=1);
    safe = np.where(np.expand_dims(allnan, 1), 0.0, masked);
    med = np.nan_to_num(np.nanmedian(safe, axis=1), nan=0.0);
    return np.where(voiced, med, 0.0);
}


"""Batched normalised-autocorrelation pitch tracker.

Returns (f0_hz, voiced_mask); unvoiced frames carry f0 = 0.0. The
autocorrelation is bias-corrected by the overlap count so long lags (low
voices) are not systematically penalised, which is the usual cause of
octave-doubling on male speech.
"""
def estimate_f0(frames: np.ndarray) -> tuple[np.ndarray, np.ndarray] {
    hann = np.hanning(FRAME).astype(np.float32);
    win = frames * hann;
    win = win - np.mean(win, axis=1, keepdims=True);

    nfft = 1;
    while nfft < 2 * FRAME {
        nfft = nfft * 2;
    }

    spec = np.fft.rfft(win, n=nfft, axis=1);
    power = np.real(spec * np.conj(spec));
    corr = np.fft.irfft(power, n=nfft, axis=1)[:, 0:FRAME];

    zero_lag = np.take(corr, 0, axis=1);
    overlap = (FRAME - np.arange(FRAME)).astype(np.float32);
    corr = corr / overlap;
    corr = corr / (np.expand_dims(zero_lag, 1) / float(FRAME) + EPS);

    lag_lo = int(float(SR) / F0_MAX);
    lag_hi = int(float(SR) / F0_MIN);
    if lag_hi >= FRAME {
        lag_hi = FRAME - 1;
    }

    band = corr[:, lag_lo:lag_hi];
    best = np.argmax(band, axis=1);
    peak = np.max(band, axis=1);
    lags = (best + lag_lo).astype(np.int64);

    left_i = np.expand_dims(np.maximum(lags - 1, 0), 1);
    right_i = np.expand_dims(np.minimum(lags + 1, FRAME - 1), 1);
    mid_i = np.expand_dims(lags, 1);
    left = np.ravel(np.take_along_axis(corr, left_i, axis=1));
    right = np.ravel(np.take_along_axis(corr, right_i, axis=1));
    centre = np.ravel(np.take_along_axis(corr, mid_i, axis=1));

    denom = left - 2.0 * centre + right;
    shift = np.where(np.greater(np.abs(denom), EPS), 0.5 * (left - right) / (denom + EPS), 0.0);
    lagf = lags.astype(np.float32) + np.clip(shift, -1.0, 1.0);

    voiced = np.greater(peak, 0.32);
    f0 = np.where(voiced, float(SR) / np.maximum(lagf, 1.0), 0.0);
    in_range = np.logical_and(np.greater_equal(f0, F0_MIN), np.less_equal(f0, F0_MAX));
    f0 = np.where(in_range, f0, 0.0);
    voiced = np.greater(f0, 0.0);
    return (median_smooth_f0(f0, voiced), voiced);
}


"""Spectral centroid, high-frequency energy ratio and spectral flux.

The HF ratio is the workhorse for articulation: fricatives and plosive bursts
put energy in the 2-6 kHz band, so mumbled speech measures low.
"""
def spectral_features(frames: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray] {
    hann = np.hanning(FRAME).astype(np.float32);
    nfft = 1024;
    mag = np.abs(np.fft.rfft(frames * hann, n=nfft, axis=1));
    freqs = np.fft.rfftfreq(nfft, d=1.0 / float(SR));

    total = np.sum(mag, axis=1) + EPS;
    centroid = np.sum(mag * freqs, axis=1) / total;

    band_all = np.logical_and(np.greater_equal(freqs, 100.0), np.less_equal(freqs, 6000.0));
    band_hi = np.logical_and(np.greater_equal(freqs, 2000.0), np.less_equal(freqs, 6000.0));
    energy_all = np.sum(np.compress(band_all, mag, axis=1), axis=1) + EPS;
    energy_hi = np.sum(np.compress(band_hi, mag, axis=1), axis=1);
    hf_ratio = energy_hi / energy_all;

    norm = mag / (np.expand_dims(np.max(mag, axis=1), 1) + EPS);
    zeros = np.zeros((1, int(norm.shape[1])), dtype=norm.dtype);
    diff = np.diff(norm, axis=0, prepend=zeros);
    flux = np.sum(np.maximum(diff, 0.0), axis=1) / float(norm.shape[1]);

    return (centroid, hf_ratio, flux);
}


"""Run the full front-end and bundle every per-frame feature."""
def analyze_frames(samples: np.ndarray) -> FrameData {
    frames = frame_matrix(samples);
    db = frame_db(frames);
    pitch = estimate_f0(frames);
    spec = spectral_features(frames);

    noise_floor = float(np.percentile(db, 10.0));
    speech = db[np.greater(db, np.percentile(db, 20.0))];
    loud = float(np.percentile(speech, 90.0)) if len(speech) > 0 else -20.0;
    speech_floor = max(noise_floor + 8.0, loud - 32.0);

    return FrameData(
        db=db,
        f0=pitch[0],
        voiced=pitch[1],
        centroid=spec[0],
        hf_ratio=spec[1],
        flux=spec[2],
        n_frames=int(len(db)),
        duration=float(len(samples)) / float(SR),
        noise_floor=noise_floor,
        speech_floor=speech_floor
    );
}


"""Frames carrying speech, median-cleaned to remove single-frame flicker."""
def speech_mask(fd: FrameData) -> np.ndarray {
    raw = np.greater(fd.db, fd.speech_floor);
    if len(raw) < 7 {
        return raw;
    }
    padded = np.pad(raw.astype(np.float32), (3, 3), mode="edge");
    stack = np.lib.stride_tricks.sliding_window_view(padded, 7);
    return np.greater(np.median(stack, axis=1), 0.5);
}


"""Contiguous True runs as [(start_frame, end_frame_exclusive), ...]."""
def runs_of(mask: np.ndarray) -> list[tuple[int, int]] {
    out: list[tuple[int, int]] = [];
    if len(mask) == 0 {
        return out;
    }
    flat = mask.astype(np.int8);
    edges = np.diff(flat, prepend=np.zeros(1, dtype=np.int8), append=np.zeros(1, dtype=np.int8));
    starts = np.flatnonzero(np.equal(edges, 1)).tolist();
    ends = np.flatnonzero(np.equal(edges, -1)).tolist();
    for (s, e) in zip(starts, ends) {
        out.append((int(s), int(e)));
    }
    return out;
}


"""Intensity-peak syllable detector (de Jong & Wempe style).

A nucleus is a voiced intensity peak that clears the surrounding dip by
`dip_db` and sits at least 100 ms from its neighbour. This is what makes
speaking rate measurable without a transcript.
"""
def syllable_nuclei(fd: FrameData, voiced_speech: np.ndarray) -> list[int] {
    dip_db = 2.5;
    min_gap = 10;
    db = fd.db;
    n = int(len(db));
    if n < 3 {
        return [];
    }

    smooth = np.copy(db);
    if n >= 5 {
        padded = np.pad(db, (2, 2), mode="edge");
        smooth = np.mean(np.lib.stride_tricks.sliding_window_view(padded, 5), axis=1);
    }

    prev = smooth[0:n - 2];
    curr = smooth[1:n - 1];
    nxt = smooth[2:n];
    is_peak = np.logical_and(np.greater(curr, prev), np.greater_equal(curr, nxt));
    peaks: list[int] = (np.flatnonzero(is_peak) + 1).tolist() as list[int];

    nuclei: list[int] = [];
    last = -999;
    for p in peaks {
        if not bool(voiced_speech[p]) {
            continue;
        }
        if p - last < min_gap {
            if len(nuclei) > 0 and float(smooth[p]) > float(smooth[nuclei[-1]]) {
                nuclei[-1] = int(p);
                last = int(p);
            }
            continue;
        }
        lo = max(0, p - 25);
        hi = min(n, p + 26);
        dip = min(float(np.min(smooth[lo:p + 1])), float(np.min(smooth[p:hi])));
        if float(smooth[p]) - dip >= dip_db {
            nuclei.append(int(p));
            last = int(p);
        }
    }
    return nuclei;
}


"""Convert Hz to semitones relative to `ref`, for perceptual pitch spans."""
def hz_to_semitones(f0: np.ndarray, ref: float) -> np.ndarray {
    safe = np.maximum(f0, EPS);
    return 12.0 * np.log2(safe / max(ref, EPS));
}
