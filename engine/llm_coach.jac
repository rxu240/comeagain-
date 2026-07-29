"""The byLLM coaching layer - an optional module, loaded only when used.

This is the only file that imports byllm, and `coach.jac` reaches it through
`importlib` rather than a static import. That keeps byllm (and its litellm /
openai / tokenizers tail) off the dependency graph of any deployment that does
not want it: with no `ANTHROPIC_API_KEY` set, nothing here is ever imported and
the deterministic coach carries the app on its own.

The LLM is given measurements and asked to phrase them. It is never given the
audio, and never asked for a number.
"""

import from byllm.lib { Model }
import from engine.model { Coaching }

glob llm: Model = Model(model_name="anthropic/claude-sonnet-5");

sem Coaching.summary = "Two sentences to the speaker about how this take landed overall. Address them as 'you'. Name the single thing most worth changing. No greeting, no preamble, no praise the scores do not support.";
sem Coaching.drills = "Three concrete practice instructions, each one sentence, each physically actionable in under a minute. No numbering, no restating the measurement.";


"""Ask an LLM to phrase coaching from measurements it cannot alter."""
def llm_coach(profile: str, context: str) -> Coaching by llm(temperature=0.4);
sem llm_coach = "You are a demanding but fair speech coach reviewing a recording. You are given measured delivery scores (0-100) and the notable moments. Write coaching a working speaker would act on. Use only the measurements given - never invent a number, a word the speaker said, or a detail you were not told.";
sem llm_coach.profile = "The measured delivery profile: each dimension with its score and the analyser's finding.";
sem llm_coach.context = "What the speaker said this recording was for, if they told us.";


"""Ask an LLM for something to say, for someone with nothing prepared.

Only ever called for girlfriend mode - vc mode's prompt is one of three fixed
questions and never reaches an LLM (see `engine.coach.generate_speaking_prompt`).
"""
def generate_prompt(mode: str) -> str by llm(temperature=0.9);
sem generate_prompt = "Write a single short, casual small-talk question a man could ask a woman he is interested in, early in a conversation - warm and specific, not deep or heavy, the kind of question that is easy and fun to answer out loud. Output only the question text - no title, no preamble, no quotation marks.";
sem generate_prompt.mode = "The practice context - always 'girlfriend' for this function.";
