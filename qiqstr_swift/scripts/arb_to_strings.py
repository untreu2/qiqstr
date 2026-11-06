import json, sys, os
src, dst = sys.argv[1], sys.argv[2]
for lang in ["en", "tr", "de"]:
    data = json.load(open(os.path.join(src, f"app_{lang}.arb")))
    os.makedirs(os.path.join(dst, f"{lang}.lproj"), exist_ok=True)
    with open(os.path.join(dst, f"{lang}.lproj", "Localizable.strings"), "w") as f:
        for k, v in data.items():
            if k.startswith("@"): continue
            v = v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
            f.write(f'"{k}" = "{v}";\n')
