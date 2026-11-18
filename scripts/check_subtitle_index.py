"""Fail packaging if voice/subtitle identity or coverage differs."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
voice_path = root / "cg_voices.json"
data = json.loads((root / "cg_subtitles.json").read_text(encoding="utf-8"))
assert hashlib.sha256(voice_path.read_bytes()).hexdigest() == data["source_sha256"]["voices"]
voices = json.loads(voice_path.read_text(encoding="utf-8"))["cues"]
for cue in voices:
    text = data["subtitles"].get(str(cue["op_index"]))
    assert isinstance(text, str) and text.strip(), "Subtitle missing"
print(json.dumps({"voice_cues": len(voices), "matched": len(voices), "missing": 0}))
