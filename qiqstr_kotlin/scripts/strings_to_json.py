import json
import os
import re
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
source = os.path.join(root, "..", "qiqstr_swift", "Qiqstr", "Resources")
target = os.path.join(root, "app", "src", "main", "assets", "i18n")
entry = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.M)
escapes = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "r": "\r"}


def unescape(value):
    return re.sub(r'\\(.)', lambda m: escapes.get(m.group(1), m.group(1)), value)


tables = sys.argv[1:] or ["Localizable", "Auth", "Feed", "Profile", "Explore", "DM", "Wallet", "Settings"]
for lang in ["en", "tr", "de"]:
    os.makedirs(os.path.join(target, lang), exist_ok=True)
    for table in tables:
        path = os.path.join(source, f"{lang}.lproj", f"{table}.strings")
        if not os.path.exists(path):
            continue
        out = os.path.join(target, lang, f"{table}.json")
        existing = json.load(open(out)) if os.path.exists(out) else {}
        values = {unescape(k): unescape(v) for k, v in entry.findall(open(path, encoding="utf-8").read())}
        existing.update({k: v for k, v in values.items() if k not in existing})
        json.dump(dict(sorted(existing.items())), open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("ok")
