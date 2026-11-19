#!/usr/bin/env python3
"""Parse docs/story.md -> data/dialogue/lines_<group>.json + messages.json.

Line:    - `key` **speaker** [fx]: text
Message: - msg `id` **from** HH:MM (chN): text
Group = key prefix before the first '_' (ch1, ch2, ch3, ch4, endA, endB).
"""
import json, re, sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs/story.md"
OUT = ROOT / "data/dialogue"

LINE = re.compile(r"^- `([A-Za-z0-9_]+)` \*\*([^*]+)\*\*(?: \[(\w+)\])?: (.+)$")
MSG = re.compile(r"^- msg `([A-Za-z0-9_]+)` \*\*([^*]+)\*\* (\d\d:\d\d) \(ch(\d)\): (.+)$")
FX = {"none", "phone", "radio", "door", "entity", "far"}

def main() -> int:
    speakers = json.loads((OUT / "speakers.json").read_text(encoding="utf-8"))
    groups: dict[str, dict] = defaultdict(dict)
    messages: dict[str, dict] = {}
    errors = []
    for n, raw in enumerate(SRC.read_text(encoding="utf-8").splitlines(), 1):
        s = raw.strip()
        if m := MSG.match(s):
            mid, frm, time, ch, text = m.groups()
            if frm not in speakers:
                errors.append(f"{n}: unknown sender {frm}")
            if mid in messages:
                errors.append(f"{n}: duplicate message {mid}")
            messages[mid] = {"from": frm, "time": time, "text": text.strip(), "chapter": int(ch)}
        elif m := LINE.match(s):
            key, spk, fx, text = m.groups()
            fx = fx or "none"
            if spk not in speakers:
                errors.append(f"{n}: unknown speaker {spk}")
            if fx not in FX:
                errors.append(f"{n}: unknown fx {fx}")
            group = key.split("_")[0]
            if any(key in g for g in groups.values()):
                errors.append(f"{n}: duplicate key {key}")
            groups[group][key] = {"speaker": spk, "text": text.strip(), "fx": fx}
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    for old in OUT.glob("lines_*.json"):
        if old.stem != "lines_test":
            old.unlink()
    for group, lines in groups.items():
        (OUT / f"lines_{group}.json").write_text(json.dumps(lines, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    (OUT / "messages.json").write_text(json.dumps(messages, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    total = sum(len(g) for g in groups.values())
    print(f"{total} lines in {len(groups)} groups {sorted(groups)}, {len(messages)} messages")
    return 0

if __name__ == "__main__":
    sys.exit(main())
