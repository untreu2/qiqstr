# qiqstr monorepo

- `qiqstr_flutter/` contains the Flutter client. Read `qiqstr_flutter/AGENTS.md` before changing it.
- `qiqstr_swift/` contains the native SwiftUI client. Read `qiqstr_swift/AGENTS.md` before changing it.
- Run build, generation, and test commands from the relevant application directory. Each app owns its Rust bridge and generated artifacts.

## Browser

Zen Browser is for the user only. Never open, drive, script, quit, or read data from Zen (`/Applications/Zen.app`, `~/Library/Application Support/zen`), including with computer use.

Use Google Chrome for all browser work. Never run a bare `open <url>`; use `open -a "Google Chrome" <url>`.
