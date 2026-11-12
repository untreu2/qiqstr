#!/usr/bin/env python3

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile


MIN_ALIGNMENT = 16_384


def resolve_readelf(explicit_path):
    if explicit_path:
        candidate = Path(explicit_path).expanduser().absolute()
        if not candidate.is_file():
            raise FileNotFoundError(f"readelf not found: {candidate}")
        return candidate

    ndk_path = os.environ.get("ANDROID_NDK_HOME") or os.environ.get("ANDROID_NDK_ROOT")
    if ndk_path:
        executable = "llvm-readelf.exe" if os.name == "nt" else "llvm-readelf"
        candidates = list(
            Path(ndk_path).glob(f"toolchains/llvm/prebuilt/*/bin/{executable}")
        )
        if len(candidates) == 1:
            return candidates[0]

    executable = shutil.which("llvm-readelf")
    if executable:
        return Path(executable)
    raise FileNotFoundError(
        "Pass --readelf or set ANDROID_NDK_HOME/ANDROID_NDK_ROOT to an installed NDK"
    )


def load_alignments(readelf, library):
    result = subprocess.run(
        [str(readelf), "-lW", str(library)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        raise ValueError(
            f"readelf exited {result.returncode}: {result.stderr.strip()}"
        )
    alignments = [
        int(line.split()[-1], 0)
        for line in result.stdout.splitlines()
        if line.split() and line.split()[0] == "LOAD"
    ]
    if not alignments:
        raise ValueError("ELF has no LOAD segments")
    if any(alignment < MIN_ALIGNMENT for alignment in alignments):
        raise ValueError(
            "LOAD alignment below 16 KB: "
            + ", ".join(hex(alignment) for alignment in alignments)
        )
    return alignments


def check_apk(apk, readelf):
    checked = 0
    failures = []
    with zipfile.ZipFile(apk) as archive, tempfile.TemporaryDirectory() as directory:
        for index, entry in enumerate(archive.infolist()):
            if entry.is_dir() or not entry.filename.endswith(".so"):
                continue
            try:
                with archive.open(entry) as source:
                    header = source.read(64)
                    if len(header) < 16 or header[:4] != b"\x7fELF":
                        raise ValueError("shared library has an invalid ELF header")
                    if header[4] == 1:
                        continue
                    if header[4] != 2:
                        raise ValueError(f"unsupported ELF class: {header[4]}")
                    checked += 1
                    library = Path(directory) / f"library_{index}.so"
                    with library.open("wb") as output:
                        output.write(header)
                        shutil.copyfileobj(source, output)
                alignments = load_alignments(readelf, library)
                print(
                    f"PASS {entry.filename}: LOAD alignment "
                    + ", ".join(hex(alignment) for alignment in alignments)
                )
                library.unlink()
            except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
                failures.append(f"{entry.filename}: {error}")

    if not checked:
        failures.append("APK contains no 64-bit ELF shared libraries")
    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    if failures:
        return 1
    print(f"Verified 16 KB LOAD alignment for {checked} 64-bit ELF libraries")
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Verify 16 KB LOAD alignment for 64-bit ELF libraries in an APK"
    )
    parser.add_argument("apk", type=Path)
    parser.add_argument("--readelf", type=Path)
    args = parser.parse_args()
    try:
        return check_apk(args.apk, resolve_readelf(args.readelf))
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"FAIL {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
