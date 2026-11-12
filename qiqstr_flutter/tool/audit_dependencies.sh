#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

audit_version="$(cargo audit --version)"
if [[ "$audit_version" != *" 0.22.2" ]]; then
  printf 'Expected cargo-audit 0.22.2; found %s\n' "$audit_version" >&2
  printf 'Install it with: cargo install cargo-audit --version 0.22.2 --locked\n' >&2
  exit 1
fi

audit_status=0

audit_lockfile() {
  local label="$1"
  local lockfile="$2"
  local result

  printf '\nAuditing %s\nLockfile: %s\n' "$label" "$lockfile"
  if cargo audit --file "$lockfile"; then
    printf '%s: cargo audit exited successfully\n' "$label"
  else
    result=$?
    printf '%s: cargo audit failed with exit status %s\n' "$label" "$result" >&2
    audit_status=1
  fi
}

audit_lockfile 'Qiqstr native dependencies' 'rust/Cargo.lock'

if breez_lockfile="$(python3 - <<'PY'
import json
import sys
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.request import url2pathname

config_path = Path('.dart_tool/package_config.json').resolve()
try:
    config = json.loads(config_path.read_text())
    package = next(
        entry for entry in config['packages']
        if entry['name'] == 'breez_sdk_spark_flutter'
    )
    root_uri = urlsplit(urljoin(config_path.as_uri(), package['rootUri']))
    if root_uri.scheme != 'file' or root_uri.netloc not in ('', 'localhost'):
        raise ValueError(f'Unsupported package root URI: {package["rootUri"]}')
    package_root = Path(url2pathname(root_uri.path))
    lockfile = package_root / 'rust' / 'Cargo.lock'
    if not lockfile.is_file():
        raise FileNotFoundError(f'Breez native lockfile not found: {lockfile}')
    print(lockfile)
except (OSError, ValueError, KeyError, StopIteration) as error:
    print(
        f'Cannot resolve Breez native lockfile: {error}. '
        'Run flutter pub get --enforce-lockfile first.',
        file=sys.stderr,
    )
    sys.exit(1)
PY
)"; then
  audit_lockfile 'Breez SDK Spark bundled native dependencies' "$breez_lockfile"
else
  audit_status=1
fi

exit "$audit_status"
