"""Synthetic identity matching tests; no game dialogue is displayed."""
from copy import deepcopy
from match_voice_subtitles import match

cue = {"op_index": 0, "voice": "sample", "source": {"sheet": "sample", "row": 1}}
op = {"op": "say", "voice": "sample", "source": cue["source"], "text": "Sample subtitle"}
catalog = {"cues": [cue]}
assert match(catalog, {"ops": [op]}) == {"0": "Sample subtitle"}
passed = 1
for field, value in [("voice", "other"), ("source", {"sheet": "other", "row": 1}), ("text", "")]:
    altered = deepcopy(op)
    altered[field] = value
    try:
        match(catalog, {"ops": [altered]})
    except ValueError:
        passed += 1
    else:
        raise AssertionError("Accepted invalid subtitle association")
print(f"{passed}/4 controlled subtitle matching checks passed")
