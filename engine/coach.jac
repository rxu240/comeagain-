"""Coaching copy: deterministic drills, optionally sharpened by an LLM.

The rule layer always runs, so the app is fully useful with no API key. When
`ANTHROPIC_API_KEY` is present the same measurements are handed to a byLLM
function that writes the summary and rewrites the drills in the speaker's
context. The LLM never sees audio and never invents a number - it is given the
scores and asked to phrase them.
"""

import os;
import importlib;
import random;
import from engine.model { DimensionReport, Coaching }
import from engine.scoring { fmt1 }

glob PROMPT_FALLBACKS: list[str] = [
    "Describe the best meal you have ever eaten, from the moment you sat down to the last bite. Include what it smelled like, who you were with, and one specific detail that made it memorable. Speak as if you are convincing a friend to try that same dish next week.",
    "Explain how to tie your shoelaces to someone who has never seen a shoe before. Walk through each step in order, name every part you touch, and warn them about the one mistake beginners always make. Speak slowly enough that a stranger could follow along with their eyes closed.",
    "Tell the story of a time you got lost - somewhere in a new city, in a building, anywhere. Describe how you realized you were lost, what you did first, and how it finally resolved. End with one sentence about what you would do differently if it happened again today."
];

# The three questions every VC eventually asks a founder. Kept literal and
# fixed rather than handed to an LLM, so the practice prompt is always
# recognisably one of these three - never a paraphrase that drifts off them.
glob VC_PROMPTS: list[str] = [
    "Why you? Make the case, out loud, for why you specifically are the right person to build this - not the idea, you.",
    "Why this solution? Walk through why the approach you have chosen is the right one, as if a partner just asked you to defend it on the spot.",
    "Why now? Make the case for why this has to happen this year, and not two years from now."
];

glob GIRLFRIEND_PROMPTS: list[str] = [
    "What's something you've gotten really into lately that most people wouldn't guess about you?",
    "What does a genuinely good weekend look like for you, start to finish?",
    "What's a small thing that instantly puts you in a good mood?",
    "If you could only eat food from one country for the rest of your life, what would you pick and why?",
    "What's something you're low-key proud of that you never really get to talk about?",
    "What's the best trip you've ever taken, and what made it stick with you?"
];

glob DRILLS: dict[str, str] = {
    "pacing-fast": "Read one paragraph out loud at half your natural speed. Then take it to three-quarters. That is your real presenting pace.",
    "pacing-slow": "Read a paragraph and cut every gap that is not doing work. Aim to finish it in three-quarters of the time.",
    "pausing-none": "Mark the full stops in your script and hold each one for a slow two-count. Silence is the only punctuation a listener can hear.",
    "pausing-many": "Record again with your script in front of you. Long gaps almost always mean you are composing mid-sentence rather than pausing on purpose.",
    "pitch-flat": "Say the same sentence three ways: as a fact, as a question, as a surprise. Feel where your voice moves, then keep a third of that in normal delivery.",
    "pitch-wide": "Re-record with the goal of sounding like you are explaining something to one person across a table, not to a room.",
    "volume-trail": "Say the last three words of every sentence louder than the first three. Most speakers lose the end of the line, which is where the point lives.",
    "volume-flat": "Pick the single most important word in each sentence and put visible weight on it. Let the rest sit back.",
    "intonation-uptalk": "End statements on a downward step. Record one sentence, then say it again dropping the last syllable a note lower.",
    "intonation-flat": "Read a sentence and deliberately land the final word lower than everything before it. That fall is what makes a claim sound decided.",
    "stress-even": "Underline one word per sentence. Only that word gets emphasis. Even stress is what makes competent delivery sound robotic.",
    "stress-heavy": "Cut your emphases in half. If everything is emphasised, the listener has nothing to hold on to.",
    "articulation-soft": "Over-articulate final consonants for one run-through - the t in 'want', the d in 'need'. It will feel exaggerated and sound normal.",
    "articulation-sharp": "Back off the sibilants slightly and let the vowels carry more of the line."
};


"""True when an Anthropic key is configured, so the LLM layer can be tried."""
def llm_available() -> bool {
    return os.environ.get("ANTHROPIC_API_KEY", "") != "";
}


"""Load the byLLM layer on demand; None when byllm is not installed.

Imported through importlib rather than statically so that byllm stays an
optional dependency - a deployment that ships without it still starts, and
still coaches.
"""
def load_llm_coach() -> any {
    try {
        module = importlib.import_module("engine.llm_coach");
        return module.llm_coach;
    } except Exception {
        return None;
    }
}


"""Pick the deterministic drills that match this take's weakest dimensions."""
def rule_drills(dims: list[DimensionReport]) -> list[str] {
    keys: list[str] = [];
    for d in dims {
        if d.score >= 70.0 { continue; }
        low = d.headline.lower();
        if d.key == "pacing" {
            keys.append("pacing-fast" if "fast" in low or "rush" in low else "pacing-slow");
        } elif d.key == "pausing" {
            keys.append("pausing-none" if "breathe" in low or "no room" in low else "pausing-many");
        } elif d.key == "pitch" {
            keys.append("pitch-flat" if "narrow" in low else "pitch-wide");
        } elif d.key == "volume" {
            keys.append("volume-trail" if "trailing" in low else "volume-flat");
        } elif d.key == "intonation" {
            keys.append("intonation-uptalk" if "rise" in low else "intonation-flat");
        } elif d.key == "stress" {
            keys.append("stress-even" if "even" in low else "stress-heavy");
        } elif d.key == "articulation" {
            keys.append("articulation-soft" if "soft" in low else "articulation-sharp");
        }
    }

    out: list[str] = [];
    for k in keys {
        if k in DRILLS and len(out) < 3 { out.append(DRILLS[k]); }
    }
    if len(out) == 0 {
        out.append("Nothing here needs fixing. Re-record the same script one notch faster and see whether the scores hold.");
    }
    return out;
}


"""Deterministic two-sentence summary of the take."""
def rule_summary(overall: float, dims: list[DimensionReport]) -> str {
    tone = "";
    worst_name = "";
    worst_detail = "";
    low = 999.0;
    for d in dims {
        if d.key == "tone" { tone = d.headline; continue; }
        if d.score < low { low = d.score; worst_name = d.name.lower(); worst_detail = d.headline.lower(); }
    }

    grade = "This take is working.";
    if overall < 55.0 { grade = "This take needs work before it is ready."; }
    elif overall < 72.0 { grade = "This take is solid with one clear weak spot."; }

    if worst_name == "" {
        return grade + " Overall delivery reads as " + tone.lower() + ".";
    }
    return grade + " Overall it reads as " + tone.lower() + "; the thing holding it back is " + worst_name + " - " + worst_detail + ".";
}


"""Flatten the dimension scores into the text the LLM is allowed to work from."""
def profile_text(overall: float, dims: list[DimensionReport]) -> str {
    lines: list[str] = ["Overall delivery score: " + fmt1(overall) + "/100."];
    for d in dims {
        lines.append(d.name + ": " + fmt1(d.score) + "/100 - " + d.headline + ". " + d.detail);
    }
    return " ".join(lines);
}


"""Coaching for a take: LLM when configured, deterministic otherwise."""
def coach_take(overall: float, dims: list[DimensionReport], context: str) -> Coaching {
    fallback = Coaching(
        summary=rule_summary(overall, dims),
        drills=rule_drills(dims),
        source="rules"
    );
    if not llm_available() { return fallback; }

    writer = load_llm_coach();
    if not writer { return fallback; }

    try {
        out = writer(
            profile_text(overall, dims),
            context if context != "" else "Not specified."
        ) as Coaching;
        if out.summary == "" or len(out.drills) == 0 { return fallback; }
        out.source = "llm";
        return out;
    } except Exception {
        return fallback;
    }
}


"""Load the byLLM prompt writer on demand; None when byllm is not installed."""
def load_prompt_writer() -> any {
    try {
        module = importlib.import_module("engine.llm_coach");
        return module.generate_prompt;
    } except Exception {
        return None;
    }
}


"""A short speaking prompt for the given mode.

VC mode is always one of the three canonical questions - deterministic, never
handed to an LLM, so the practice prompt never drifts off "why you / why this
solution / why now". Girlfriend mode asks small talk; the LLM adds variety
when configured, and a canned pool of small-talk questions otherwise.
"""
def generate_speaking_prompt(mode: str) -> str {
    if mode == "vc" { return random.choice(VC_PROMPTS); }

    if not llm_available() { return random.choice(GIRLFRIEND_PROMPTS); }

    writer = load_prompt_writer();
    if not writer { return random.choice(GIRLFRIEND_PROMPTS); }

    try {
        out = String(writer(mode)).strip();
        if out == "" { return random.choice(GIRLFRIEND_PROMPTS); }
        return out;
    } except Exception {
        return random.choice(GIRLFRIEND_PROMPTS);
    }
}
