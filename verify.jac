"""End-to-end check of the transcript, intonation and stress work on real speech.

`fixture-take.wav` is synthetic harmonics rather than words, so it cannot
exercise a recogniser at all. `fixture-speech.wav` is real speech with known
ground truth: three statements, one yes/no question and one wh-question. The
wh-question is the important one - English lets it fall like a statement, so the
old "every ending should fall" rule scored a correct delivery as uptalk, and a
naive "anything ending in ? should rise" rule would get it wrong in the other
direction.

Prints the per-sentence detail, then asserts the parts that must not regress.
Run with `jac run verify.jac`; a silent tail means every assertion held.
"""

import numpy as np;
import from engine.dsp { SR, analyze_frames, decode_pcm }
import from engine.asr { transcribe, ASR_SIZE }
import from engine.dimensions {
    build_context, window_of, score_window, terminal_slope
}
import from engine.segmentation { segment_bounds }
import from engine.model { DimensionReport }


"""One dimension out of a scored window, by key."""
def pick(dims: list[DimensionReport], key: str) -> DimensionReport {
    for d in dims {
        if d.key == key { return d; }
    }
    return DimensionReport();
}


"""A dimension's metric values as a compact string."""
def metrics_of(d: DimensionReport) -> str {
    parts: list[str] = [];
    for m in d.metrics { parts.append(m.label + "=" + m.value); }
    return "  ".join(parts);
}


with entry {
    # `fixture-speech.b64` is the wav pre-decoded to mono 16 kHz int16 PCM -
    # the form the browser hands the server, so the harness exercises the same
    # decode path (`decode_pcm`) the real API does.
    samples = decode_pcm(open("fixture-speech.b64").read());
    fd = analyze_frames(samples);
    tr = transcribe(samples, ASR_SIZE);
    ctx = build_context(fd, tr);

    print("=== TRANSCRIPT ===");
    print("source:", tr.source, "| available:", tr.available);
    print(tr.text);
    print("");

    print("=== PER UTTERANCE ===");
    bounds = segment_bounds(ctx);
    ctx.bounds = bounds;
    for i in range(len(bounds)) {
        b = bounds[i];
        nxt = bounds[i + 1][0] if i + 1 < len(bounds) else fd.n_frames;
        w = window_of(ctx, b[0], b[1], float(nxt - b[1]) * 0.01);
        scored = score_window(ctx, w, False);

        ino = pick(scored.dimensions, "intonation");
        stf = pick(scored.dimensions, "stress");
        slope = terminal_slope(w);

        print("--- segment", i, "---");
        print("   text     :", w.text if w.text != "" else "(no words matched)");
        print("   form     :", w.kind, "-> wants", w.expects);
        print("   terminal :", float(int(slope * 100.0)) / 100.0, "st over final 400ms");
        print("   INTONATION", ino.score, "|", ino.headline);
        print("      ", metrics_of(ino));
        print("      ", ino.detail);
        print("   STRESS    ", stf.score, "|", stf.headline);
        print("      ", metrics_of(stf));
    }

    print("");
    print("=== WHOLE TAKE ===");
    whole = window_of(ctx, 0, fd.n_frames, 0.0);
    all_scored = score_window(ctx, whole, True);
    for d in all_scored.dimensions {
        print("  ", d.key, d.score, "|", d.headline);
        print("      ", metrics_of(d));
    }
    print("");
    print("overall", all_scored.overall);

    print("");
    print("=== ASSERTIONS ===");

    # The transcript itself.
    assert tr.available , "transcript unavailable: " + tr.note;
    assert len(tr.utterances) == 5 , "expected 5 sentences, got " + str(len(tr.utterances));
    assert "quarterly numbers" in tr.text , "first sentence missing from transcript";
    assert "sign-ups" in tr.text , "hyphenated word was rebuilt with a space";

    # Sentence form drives the expected contour. These four are the whole point.
    forms = [(u.kind, u.expects) for u in tr.utterances];
    assert forms[0] == ("statement", "fall") , "statement misclassified: " + str(forms[0]);
    assert forms[1] == ("yesno", "rise") , "yes/no question misclassified: " + str(forms[1]);
    assert forms[3] == ("wh", "fall") , "wh-question must fall, not rise: " + str(forms[3]);
    print("  form classification ....... ok  " + str(forms));

    # Pitch reliability gate: an octave error at a phrase end used to push the
    # terminal reading to the +-15 st clamp. Real terminals are single digits.
    terminals: list[float] = [];
    for (lo, hi) in bounds {
        w = window_of(ctx, lo, hi, 0.0);
        s = terminal_slope(w);
        terminals.append(s);
        assert abs(s) < 12.0 ,
            "terminal " + str(s) + " st is not a plausible contour - octave error leaked through";
    }
    print("  terminal contours ........ ok  " + str([float(int(t * 10.0)) / 10.0 for t in terminals]));

    # The take number has to sit inside the range of the segments it summarises,
    # or it is not a summary of them.
    take_ino = pick(all_scored.dimensions, "intonation").score;
    seg_inos: list[float] = [];
    for (lo, hi) in bounds {
        sw = window_of(ctx, lo, hi, 0.0);
        seg_inos.append(pick(score_window(ctx, sw, False).dimensions, "intonation").score);
    }
    assert take_ino >= min(seg_inos) - 0.1 and take_ino <= max(seg_inos) + 0.1 ,
        "take intonation " + str(take_ino) + " outside segment range " + str(min(seg_inos)) + "-" + str(max(seg_inos));
    print("  take/segment coherence ... ok  take=" + str(take_ino) + " segments=" + str(min(seg_inos)) + "-" + str(max(seg_inos)));

    # Stress must not be the old constant. Every segment scoring within a
    # point of every other is the signature of the z-score bug returning.
    stresses: list[float] = [];
    for (lo, hi) in bounds {
        sw = window_of(ctx, lo, hi, 0.0);
        stresses.append(pick(score_window(ctx, sw, False).dimensions, "stress").score);
    }
    spread = max(stresses) - min(stresses);
    assert spread > 5.0 ,
        "stress spread is only " + str(spread) + " points - it is measuring nothing again";
    print("  stress discriminates ..... ok  spread=" + str(float(int(spread * 10.0)) / 10.0) + " over " + str(stresses));

    print("");
    print("all assertions held.");
}
