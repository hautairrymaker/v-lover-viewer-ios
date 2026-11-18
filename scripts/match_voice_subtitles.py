"""Match existing voice cues to exact source rows; never transcribe media."""
import argparse
import hashlib
import json
from pathlib import Path


def match(catalog, scenario):
    subtitles = {}
    ops = scenario["ops"]
    for cue in catalog["cues"]:
        index = int(cue["op_index"])
        if index < 0 or index >= len(ops):
            raise ValueError("Voice source index outside scenario")
        op = ops[index]
        if (op.get("op") != "say" or op.get("voice") != cue["voice"]
                or op.get("source") != cue["source"]):
            raise ValueError("Voice source identity mismatch")
        text = op.get("text")
        if not isinstance(text, str) or not text.strip():
            raise ValueError("Source subtitle missing")
        subtitles[str(index)] = text
    return subtitles


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--voices", type=Path, required=True)
    parser.add_argument("--scenario", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Preserve existing subtitle data")
    catalog = json.loads(args.voices.read_text(encoding="utf-8"))
    scenario = json.loads(args.scenario.read_text(encoding="utf-8"))
    subtitles = match(catalog, scenario)
    result = {"subtitles": subtitles, "source_sha256": {
        "voices": hashlib.sha256(args.voices.read_bytes()).hexdigest(),
        "scenario": hashlib.sha256(args.scenario.read_bytes()).hexdigest()}}
    args.output.write_text(json.dumps(result, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"cues": len(catalog["cues"]), "matched": len(subtitles), "missing": 0}))
