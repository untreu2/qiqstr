#!/usr/bin/env python3
"""check_strings.py <lang> [<lang> ...]

Checks that every <lang>.lproj strings table in the iOS and Mac apps matches English:
same keys, the same {placeholders} (ICU plural branches may differ), %@-style format specifiers and \\n escapes, and valid
.strings syntax (plutil -lint). Prints problems and exits non-zero if any are found.
"""
import os
import re
import subprocess
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
folders = [
    os.path.join(root, "qiqstr_swift", "Qiqstr", "Resources"),
    os.path.join(root, "qiqstr_mac", "Mac", "Resources"),
]
entry = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.M)
placeholder = re.compile(r"\{([A-Za-z0-9_]+)(?:\}|, *plural)|(%(?:\d+\$)?[@dDuUxXoOfeEgGcCsSpaAF])")
branch = re.compile(r"(?:=\d+|zero|one|two|few|many|other) *\{[^{}]*\}")


def variables(value):
    """Variable names ({name}, {count, plural, ...}) and format specifiers, ignoring plural branch text."""
    while branch.search(value):
        value = branch.sub("", value)
    return {a or b for a, b in placeholder.findall(value)}


def required(value):
    """Variables a translation must keep: plain {name}s and format specifiers. A variable used only to pick a
    plural form may be dropped by languages without plurals (Turkish says "{count} üye" for any number)."""
    while branch.search(value):
        value = branch.sub("", value)
    return set(re.findall(r"\{([A-Za-z0-9_]+)\}", value)) | set(re.findall(r"%(?:\d+\$)?[@dDuUxXoOfeEgGcCsSpaAF]", value))



def table(path):
    return dict(entry.findall(open(path, encoding="utf-8").read()))


problems = []
for lang in sys.argv[1:]:
    for folder in folders:
        english = os.path.join(folder, "en.lproj")
        if not os.path.isdir(english):
            continue
        for name in sorted(os.listdir(english)):
            if not name.endswith(".strings"):
                continue
            source = table(os.path.join(english, name))
            path = os.path.join(folder, f"{lang}.lproj", name)
            if not os.path.exists(path):
                problems.append(f"{lang}: missing {path}")
                continue
            lint = subprocess.run(["plutil", "-lint", path], capture_output=True, text=True)
            if lint.returncode != 0:
                problems.append(f"{lang}: {lint.stdout.strip() or lint.stderr.strip()}")
            target = table(path)
            for key in source.keys() - target.keys():
                problems.append(f"{lang}/{name}: missing key {key}")
            for key in target.keys() - source.keys():
                problems.append(f"{lang}/{name}: extra key {key}")
            for key in source.keys() & target.keys():
                want, got = source[key], target[key]
                if not (required(want) <= variables(got) <= variables(want)):
                    problems.append(f"{lang}/{name}: {key}: placeholders {sorted(variables(want))} != {sorted(variables(got))}")
                if want.count("\\n") != got.count("\\n"):
                    problems.append(f"{lang}/{name}: {key}: line breaks differ ({want.count(chr(92) + 'n')} vs {got.count(chr(92) + 'n')})")
                if want.strip() and not got.strip():
                    problems.append(f"{lang}/{name}: {key}: empty translation")

for problem in problems:
    print(problem)
print(f"{len(problems)} problem(s)")
sys.exit(1 if problems else 0)
