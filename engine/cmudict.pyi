"""Check-time stub for the CMU Pronouncing Dictionary lookup.

`dict()` maps a lowercase word to its pronunciations, each a list of ARPAbet
phones. Vowel phones carry a trailing stress digit: 1 primary, 2 secondary,
0 unstressed - which is what lets `engine/stress.jac` know which syllable of a
word is *supposed* to carry the weight.
"""

from typing import Any

def dict() -> Any: ...
def phones() -> Any: ...
def symbols() -> Any: ...
