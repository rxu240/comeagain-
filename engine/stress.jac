"""Stress: how much weight lands on a syllable, and whether it is the right one.

This module exists because the first version of the stress dimension measured
nothing. It counted the fraction of syllables whose prominence *z-score* cleared
a fixed threshold - but a z-score is taken against the speaker's own mean, so
that fraction is fixed by the shape of a normal distribution, not by the speech.
Simulating the original code across a twentyfold range of real expressiveness
moved the measured value from 0.221 to 0.223, and every one of those landed
inside the "ideal" band. A monotone and a theatrical reading scored the same.

The fix is two measurements that are not self-referential:

1. **Emphasis range**, in absolute dB and semitones - the real acoustic distance
   between the syllables a speaker leans on and the ones they do not. Flat
   delivery genuinely measures small here; expressive delivery genuinely
   measures large.

2. **Emphasis placement**, which needs the transcript: English puts accent on
   content words and leaves function words ("the", "of", "is") unaccented.
   Leaning on function words is a specific, fixable habit, and naming the word
   is far more useful than any score.
"""

import numpy as np;
import from engine.dsp { HOP_S }
import from engine.model { Transcript, Word }

# Closed-class words that normally carry no accent in English. Stressing one is
# not automatically wrong - contrastive focus ("it was THE reason") is real -
# but doing it repeatedly is the habit worth surfacing.
glob FUNCTION_WORDS: list[str] = [
    "a", "an", "the", "and", "or", "but", "nor", "for", "yet", "so",
    "of", "in", "on", "at", "to", "by", "from", "with", "into", "onto",
    "as", "if", "than", "that", "this", "these", "those", "then",
    "is", "are", "was", "were", "be", "been", "being", "am",
    "do", "does", "did", "has", "have", "had",
    "will", "would", "can", "could", "shall", "should", "may", "might", "must",
    "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them",
    "my", "your", "his", "its", "our", "their",
    "there", "here", "about", "up", "out", "over", "just", "not"
];

glob PUNCT: str = ".,?!;:\"'()[]{}-…";


"""A word reduced to its comparable form: lowercase, no surrounding punctuation."""
def normalise(token: str) -> str {
    return token.strip().strip(PUNCT).lower();
}


"""True if this token is a closed-class word that normally carries no accent."""
def is_function_word(token: str) -> bool {
    return normalise(token) in FUNCTION_WORDS;
}


"""Absolute acoustic contrast between the leaned-on syllables and the rest.

Returns `(db_range, st_range)`: the gap between the mean of the top third of
syllables and the mean of the bottom third, in real dB and real semitones. Both
are absolute, so unlike a z-score they move when the speaking actually changes.
"""
def emphasis_range(db_at: np.ndarray, st_at: np.ndarray) -> tuple[float, float] {
    n = int(len(db_at));
    if n < 4 { return (0.0, 0.0); }

    third = max(n // 3, 1);
    db_sorted = np.sort(db_at);
    st_sorted = np.sort(st_at);

    db_gap = float(np.mean(db_sorted[n - third:n])) - float(np.mean(db_sorted[0:third]));
    st_gap = float(np.mean(st_sorted[n - third:n])) - float(np.mean(st_sorted[0:third]));
    return (max(db_gap, 0.0), max(st_gap, 0.0));
}


"""Where an accent landed and what it landed on."""
obj Placement {
    has content: int = 0,
        function: int = 0,
        considered: int = 0,
        leaned: list[str] = [];
}


"""The word containing a given time, or an empty string."""
def word_at(words: list[Word], t: float) -> str {
    for w in words {
        if t >= w.start and t <= w.end { return w.text; }
    }
    return "";
}


"""Check whether the most prominent syllables landed on content words.

Only the top third of syllables by prominence are considered - those are the
ones a listener hears as accented. `leaned` collects the function words that
took an accent, de-duplicated, so the coaching can name them.
"""
def placement(
    nuclei: list[int], prom: list[float], tr: Transcript, start: float, end: float
) -> Placement {
    out = Placement();
    if not tr.available or len(nuclei) < 4 { return out; }

    words: list[Word] = [];
    for u in tr.utterances {
        for w in u.words {
            if w.end >= start and w.start <= end { words.append(w); }
        }
    }
    if len(words) == 0 { return out; }

    order = np.argsort(np.array(prom));
    keep = max(len(nuclei) // 3, 2);
    top: list[int] = order.tolist()[len(nuclei) - keep:len(nuclei)] as list[int];

    for i in top {
        token = word_at(words, float(nuclei[i]) * HOP_S);
        if token == "" { continue; }
        out.considered += 1;
        if is_function_word(token) {
            out.function += 1;
            plain = normalise(token);
            if plain not in out.leaned { out.leaned.append(plain); }
        } else {
            out.content += 1;
        }
    }
    return out;
}
