# Five-pass review — 2026-09-12

qiqstr is a mobile Nostr client: users own a local signing identity, receive a relay-backed
social feed, exchange encrypted direct messages, and use Spark, NWC, and Cashu wallet
features. Flutter renders the application, BLoCs coordinate presentation, and the Rust
bridge supplies protocol, cryptography, relay, and LMDB operations. The Nostr identity
seed and Spark wallet recovery key are separate secrets.

This review used five passes. It does not certify every screen, external provider, or
platform as tested.

| Pass | Work and findings |
| --- | --- |
| 1 — Purpose and baseline | Read architecture, startup, DI, routing, authentication, feed, messaging, storage, and wallet paths. The original analyzer passed, but coverage consisted of only two Dart and two Rust tests. |
| 2 — Identity | Reproduced failures in full-width hexadecimal key imports, invalid key validation, recovery-phrase ownership, pasted mnemonic whitespace, note-ID decoding, and stale authentication caches. Fixed those paths, preserved a known recovery phrase when reimporting the same identity, and rejected mismatched stored key pairs. |
| 3 — State and wallets | Reproduced stale search responses and NWC reads crossing account changes. Added cancellation/generation guards, shared Spark connection attempts, discarded stale SDKs, retained imported recovery keys after connection failure, and isolated wallet storage directories using the full account ID. Fixed balance-error clearing and malformed navigation preferences. |
| 4 — Native and UI flows | Exercised signing, profile/follow/note/reply/reaction storage and hydration, mutes, encrypted DMs, AES attachments, and the real bridge. Reproduced acceptance of forged events and outer DM signatures, then added verification. A loopback NWC relay reproduced responses arriving before publication acknowledgement. Phone-size and simulator onboarding tests exposed broken theme imports and a stale terms warning. The welcome state now uses a registered BLoC and the existing Poppins fonts are bundled for offline loading. |
| 5 — Regression and persistence | Added real startup, LMDB persistence and deletion-authorization checks, private-list cache resets with stale-load guards, immediate muted-word matching, and wallet connection/recovery regressions. Replaced the dependency's unsafe wipe with schema-preserving event deletion, stopped unlinking open database directories, and removed destructive initialization and size-based wipe fallbacks. Added `tool/verify.sh` and corrected outdated Coinos documentation to match the Spark implementation. |

## Final validation

The complete verification script passed on macOS with an iPhone 17 Pro simulator running
iOS 26.5. Results below are from the final combined run after the code changes.

| Check | Result |
| --- | --- |
| Rust tests | 3 passed, including the loopback NWC response race |
| Host native library build | Passed |
| Flutter analyzer | No issues found |
| Dart/native/widget suite | 43 passed |
| iOS integration suite | 2 passed: real startup and onboarding/recovery backup |
| Rust bridge regeneration | Passed |
| Patch whitespace validation | `git diff --check` passed |
| Android | Not verified: Android SDK unavailable |

Flutter also reports that four existing iOS plugins do not support Swift Package Manager.
The current simulator builds pass, but dependency support needs attention before a future
Flutter release makes that requirement mandatory.

## Reproduction

```sh
./tool/verify.sh
./tool/verify.sh <simulator-or-device-id>
```

The script resolves Dart dependencies, runs Rust tests, builds the host native library,
runs the analyzer, and executes all Dart/native/widget tests. An optional device ID adds
the mobile integration suite. The Rust bridge was regenerated with
`flutter_rust_bridge_codegen generate`; generated files were not edited manually.

Test identities, wallet credentials, and LMDB directories are generated or mocked for the
tests. The NWC test uses a loopback WebSocket server and simulated balances. The startup
test uses the real application entry point, native libraries, and DI, redirects file paths
to temporary storage, mocks secure storage, and connects to the configured public relays.
No public content was posted and no real payment was sent.

## Coverage limits and remaining work

- Android build/runtime verification is blocked by the missing Android SDK. No Android
  emulator or physical Android device was available.
- Real Spark/NWC payments, Cashu mint settlement, camera/QR scanning, media upload,
  background delivery, push behavior, and every authenticated screen have not been
  exercised end to end. Wallet failure and account-switch tests use controlled SDK/storage
  substitutes; these cannot establish external-provider compatibility.
- The architecture still has existing violations: 39 UI files import data/domain code,
  36 UI files use `setState`, and five presentation files import Flutter widget libraries.
  The welcome screen was migrated, but a complete migration of existing screens remains.
- Existing repositories do not uniformly use abstract interfaces or `Result<T>`, and
  existing service error strings and some UI labels still need localization work.
- Spark now uses full account IDs for SDK cache directories. Existing shorter directories
  remain on disk; the new directory uses the same stored recovery key and must synchronize
  through the SDK. External-provider recovery and historical transaction reconstruction
  were not verified with a funded wallet.
- LMDB cleanup removes events while retaining schema and protocol deletion records. Freed
  pages can be reused, but the allocated file may not immediately shrink; offline database
  compaction remains separate work.
- Legacy Spark recovery values are retained rather than silently deleted. This review
  does not implement conversion of old mnemonic-based wallet formats.

Test-specific analyzer configuration permits relative imports into `lib`, following the
repository's import convention. Other analyzer rules remain enabled.

## Follow-up verification — 2026-10-21

This section records the current follow-up; the September results above are historical.
Final validation results were reconciled on 2026-10-22.
The work fixed reproduced defects and expanded automated coverage. It did not test every
function or establish production readiness for every platform, wallet provider, or
upgrade path. No production certification is implied.

### Changes verified in this follow-up

- Identity changes are serialized, malformed account backups are preserved rather than
  overwritten, and account changes invalidate stale authentication, wallet, messaging,
  and private-list work. Final-account logout stops background services, resets native
  client/signing state, and resets account-dependent dependency registrations.
- Spark recovery-key writes and NWC connection writes are serialized. Invalid stored
  recovery values are rejected without replacing them, late SDK results cannot update a
  different account, and payment preparation rechecks the active account before sending.
  Wallet actions reject invalid input and overlapping submissions; Cashu failures refresh
  the actual retained balance.
- Recipient and sender DM copies now wrap the same rumor. Messaging rejects empty text,
  handles publication failures, maintains conversation order, and cancels stale work.
  Attachment decryption validates keys/nonces and cached plaintext, uses full cache
  digests, and prevents an in-flight decrypt from repopulating a cleared account cache.
- Native publication requires a relay acknowledgement. Failed publication no longer
  leaves the rejected event in the durable local cache. Loopback tests cover rejected
  replacement lists, notes, and deletion across LMDB reopening. Cashu storage retains its
  seed and database, rejects missing/corrupt existing seeds, and resumes recorded mints.
- Social loading and mutations gained regressions for account changes, stale responses,
  failed publication, private-list cache restoration, and disconnected-relay behavior.
  Publication rechecks the signing identity after key retrieval; deferred list startup,
  list/pin synchronization, and late status updates stop when their account or service
  session is no longer current.
  Additional widget and simulator tests exercise navigation and selected authenticated
  screens without publishing public content or making payments.

### Current validation

The `./tool/verify.sh` run exited successfully after the coordinated Breez/FRB
upgrade and account-switch fixes. Flutter 3.44.4, Dart 3.12, and Rust 1.96.0 were used
for the host checks on macOS. Analysis after adding the Cupertino font dependency also
passed, and all 217 original Dart/native/widget tests passed again with coverage collection
requested. Coverage reporting did not produce usable data.

| Check | Result as of this update |
| --- | --- |
| Dart dependency resolution | `flutter pub get --enforce-lockfile` passed |
| Rust formatting and strict Clippy | Passed |
| Rust tests | 23 passed |
| Host native library build | Passed |
| Flutter analyzer | No issues found |
| Dart/native/widget suite | 217 passed |
| Dart coverage report | LCOV output was empty; no coverage percentage established |
| Rust bridge regeneration | Passed with generator/runtime 2.13.0; rebuilt Dart/native API hashes match |
| Account/wallet/DM/attachment regression subset after SDK upgrade | 47 passed |
| Patch whitespace validation | `git diff --check` passed |
| iOS simulator integration suite | 4 passed on iOS 27: real startup with backup retention, onboarding, authenticated navigation across 21 routes/four tabs/the composer, and native secure storage |
| Android ARM64 debug application | Normal debug APK build passed |
| Android 16 KB packaging | Debug: all 16 packaged 64-bit libraries passed ELF LOAD alignment; release: all 14 passed. Both APKs passed ZIP alignment |
| Android emulator integration scenarios | Final rerun: 4 passed on API 36 ARM64 with 16 KB pages, covering startup, onboarding, authenticated navigation, and native secure storage |
| Native secure-storage plugin integration | Passed on Android emulator and iOS simulator using actual native plugin storage |
| Unsigned Android release APK | ARM64 build passed in 69.7 seconds; 81.4 MB |
| Android release launch smoke check | A temporary copy signed with a debug key installed and opened Welcome on the API 36 ARM64 16 KB emulator without AndroidRuntime errors |
| Unsigned iOS device Release build | `flutter build ios --release --no-codesign` passed in 149.9 seconds; 98.3 MB; ARM64 Mach-O and absence of code signing verified |
| iOS simulator preview | Targeted debug run passed in 126.0 seconds and launched Welcome; screenshot review found the expected controls without an error screen |
| Signed Android release and install-over upgrade | Not verified |
| Signed iOS archive and physical-device release | Not verified |
| Newly added GitHub Actions workflow | Configuration reviewed; remote execution not established by these local results |

The 47-test account/wallet subset is included in the 217-test total. A concurrent Flutter
test invocation initially failed during native-asset codesigning before tests started;
the serialized complete rerun passed. Run commands sharing Flutter build outputs
sequentially.

The final `flutter test --coverage` run passed all 217 original tests but wrote a zero-byte
LCOV file: relative test imports loaded application files under file URIs outside the
package coverage filter. An isolated attempt with temporary copies using package imports
crashed in the Dart VM's source-report filtering path (`String::StartsWith`,
`SourceReport::ShouldFiltersIncludeScript`, and `GetScriptIndex`); the reported stack had
no application or Rust frame. A bounded no-match-filter probe passed two tests but still
produced empty LCOV. Temporary test copies were removed and original tests were untouched.
Test counts therefore must not be presented as a measured function or line-coverage rate.

The normal simulator preview succeeded with
`flutter run --debug --no-resident -d <simulator-id>`. Generic simulator builds on the
local Xcode 27.1 toolchain failed when `lipo -verify_arch` received both `arm64` and
`x86_64`; the single-architecture command succeeded. Flutter split the architecture
arguments correctly. Targeting a concrete simulator avoided the toolchain failure
without source or toolchain patches. The macOS 15 CI runner has not been tested for this
issue; its simulator build command remains unchanged. All three lockfile hashes remained
unchanged after the successful preview run, and the unrelated simulator was untouched.

The script now enforces the Dart lockfile and runs Rust formatting, strict Clippy, locked
Rust tests/build, analysis, and the Dart/native/widget suite. Passing a device ID adds the
mobile integration tests. The workflow runs the host checks and builds an iOS debug
simulator application and unsigned iOS device release. An independent Android job builds
an unsigned ARM64 release APK on Ubuntu
24.04 with pinned Java, Android, Flutter, and host Rust tools, checks 16 KB ZIP alignment and
ELF LOAD alignment using `tool/check_android_alignment.py`, and checks that dependency
lockfiles remain unchanged. The workflow has not been run remotely during this review.
A separate security job runs `tool/audit_dependencies.sh`, which
audits both the application's and the resolved Breez package's Rust lockfiles without
advisory suppressions. This security gate is expected to fail on the Breez findings below;
passing functional tests does not make the overall release gate pass. CI does not run mobile
integration tests, produce signed release artifacts, or independently
check a regenerated bridge against committed output.

Android release builds after integration tests must allow normal package resolution:
`flutter build apk --release --target-platform android-arm64`. Using `--no-pub` reproduced
stale test-plugin registration and a compilation failure; normal regeneration resolves
this [Flutter issue #163774](https://github.com/flutter/flutter/issues/163774).
Run `flutter pub get --enforce-lockfile` first and compare lockfile checksums after the
release build, as shown in the README. `pubspec.lock`, `rust/Cargo.lock`, and
`ios/Podfile.lock` remained byte-identical across both successful release builds.
Signature verification confirmed that the original APK was unsigned; installing the
debug-key-signed temporary copy was only a launch smoke check, not validation of store
signing or an upgrade over a previous release.

The `cupertino_icons` 2.0 dependency supplies the Cupertino font referenced by an unused
go_router error-screen branch. Both release artifacts include its tree-shaken 848-byte
font. The earlier font warning did not demonstrate a broken control in an exercised app
flow.

The new `integration_test/secure_storage_test.dart` uses the actual native plugin with
the same default options as authentication. It writes and updates randomly generated
recovery-key fixtures under two unique test keys, verifies reads through a new storage
instance and the native method channel, checks deletion, and removes only its own keys
in teardown. It does not mock storage or read existing account keys. Both platform runs
passed, including actual simulator Keychain operations on iOS. This checks plugin
operations; it does not validate an upgrade from an older signed application, a
Keystore/Keychain migration, device transfer, or process-restart persistence.

### Dependency decisions and remaining review

The package report found no remaining upgrades compatible with the declared Dart
constraints and no retracted resolved versions. This does not mean every dependency is
on its latest major version. Discontinued transitive packages
`flutter_secure_storage_macos` and `js` remain maintenance debt; discontinuation is not
itself a security advisory.

Breez Spark Flutter was upgraded from 0.17.0 to 0.26.1, pinned to Git commit
`f5755c42bb3df15f9d26b557ccfdb957f34e9896`, together with the matching
`flutter_rust_bridge` 2.13.0 Dart package, Rust crate, and generator. A bridge upgrade must
be coordinated with the SDK and regenerated native artifacts, followed by recovery and
payment validation. Lockfiles fix resolved dependencies, but this does not prove
byte-for-byte reproducible mobile builds: Breez has a separate native dependency tree
and precompiled artifacts. Both the app bridge and Breez mobile builds use Cargokit,
whose source-build path invokes the `stable` Rust toolchain. The CI host toolchain is
pinned to 1.96.0, but Cargokit's native mobile compiler follows the runner's `stable`
installation; the reviewed Cargokit configuration does not accept a versioned toolchain.
The application's `cargo audit --file rust/Cargo.lock` alone does not audit that separate
tree; the new security script checks both lockfiles.

`flutter_secure_storage` remains at 9.2.4 pending an Android migration exercise. The
upstream 11.0.0 changelog removes old cipher implementations and requires users of
versions before 10 to migrate through version 10 first. A direct 9-to-11 upgrade can lose
access to stored secrets. A staged release alone does not ensure users run the intermediate
version; the upgrade design must also handle users who skip releases. Verify all saved
accounts, private keys, recovery phrases, Spark keys, and NWC credentials on a real signed
install-over before changing this dependency. Mock secure-storage tests cannot validate
Android Keystore migration. See the
[upstream migration changelog](https://pub.dev/packages/flutter_secure_storage/changelog).

The current application Rust audit reports zero vulnerability-category findings, plus
three unmaintained-package warnings and one unsoundness advisory:

| Resolved crate | Advisory | Classification |
| --- | --- | --- |
| `instant` 0.1.13 | RUSTSEC-2024-0384 | Unmaintained |
| `nostr-relay-pool` 0.44.3 | RUSTSEC-2026-0243 | Unmaintained |
| `paste` 1.0.15 | RUSTSEC-2024-0436 | Unmaintained |
| `lru` 0.16.4 | RUSTSEC-2026-0253 | Unsound |

The application retains its tested Nostr 0.44 stack. Moving to the maintained 0.45 stack
requires authentication and subscription API changes; the isolated migration did not
compile and was not adopted. These residual advisories remain unresolved. Zero
vulnerability-category findings must not be described as an audit with no findings.

### Separate Breez native dependency audit

Read-only `cargo audit --file <sdk>/rust/Cargo.lock --json` was also run against the
previously pinned Breez 0.17.0 source and the latest official 0.26.1 tag. The latter resolves to
commit `f5755c42bb3df15f9d26b557ccfdb957f34e9896`. Both commands exited with status 1.

| SDK lockfile | Locked packages | Vulnerability advisories | Unmaintained entries | Unsound entries | Yanked packages |
| --- | --- | --- | --- | --- | --- |
| [0.17.0 previous pin](https://github.com/breez/breez-sdk-spark-flutter/blob/5eee61acf28316692eeab19198431e56e86f1fce/rust/Cargo.lock) | 577 | 31 | 7 | 7 | 3 |
| [0.26.1 source](https://github.com/breez/breez-sdk-spark-flutter/blob/f5755c42bb3df15f9d26b557ccfdb957f34e9896/rust/Cargo.lock) | 584 | 31 | 7 | 7 | 3 |

Both lockfiles contain the following affected versions and 31 distinct vulnerability
advisories. This is a dependency inventory finding: the audit does not establish which
optional/build-only crates are present in each shipped binary, or prove exploitability
of every finding in this application.

| Advisory | Crate and locked version | Area |
| --- | --- | --- |
| [RUSTSEC-2026-0007](https://rustsec.org/advisories/RUSTSEC-2026-0007.html) | `bytes` 1.11.0 | Integer overflow / memory safety |
| [RUSTSEC-2026-0258](https://rustsec.org/advisories/RUSTSEC-2026-0258.html) | `h2` 0.4.13 | Unbounded frame queue |
| [RUSTSEC-2026-0365](https://rustsec.org/advisories/RUSTSEC-2026-0365.html) | `negentropy` 0.5.0 | Remote allocation denial of service |
| [RUSTSEC-2026-0216](https://rustsec.org/advisories/RUSTSEC-2026-0216.html) | `nostr` 0.43.1 | NIP-44 panic |
| [RUSTSEC-2026-0226](https://rustsec.org/advisories/RUSTSEC-2026-0226.html) | `nostr` 0.43.1 | Unauthenticated wallet events |
| [RUSTSEC-2026-0227](https://rustsec.org/advisories/RUSTSEC-2026-0227.html) | `nostr` 0.43.1 | NIP-44 resource exhaustion |
| [RUSTSEC-2026-0228](https://rustsec.org/advisories/RUSTSEC-2026-0228.html) | `nostr` 0.43.1 | NIP-04 allocation amplification |
| [RUSTSEC-2026-0219](https://rustsec.org/advisories/RUSTSEC-2026-0219.html) | `nostr` 0.43.1 | NIP-04 panic |
| [RUSTSEC-2026-0229](https://rustsec.org/advisories/RUSTSEC-2026-0229.html) | `nostr` 0.43.1 | NIP-98 resource exhaustion |
| [RUSTSEC-2026-0230](https://rustsec.org/advisories/RUSTSEC-2026-0230.html) | `nostr` 0.43.1 | NIP-50 filter panic |
| [RUSTSEC-2026-0225](https://rustsec.org/advisories/RUSTSEC-2026-0225.html) | `nostr` 0.43.1 | Credentials in debug output |
| [RUSTSEC-2026-0232](https://rustsec.org/advisories/RUSTSEC-2026-0232.html) | `nostr-relay-pool` 0.43.1 | Unverified relay events |
| [RUSTSEC-2026-0224](https://rustsec.org/advisories/RUSTSEC-2026-0224.html) | `nostr-relay-pool` 0.43.1 | Verification cache poisoning |
| [RUSTSEC-2026-0231](https://rustsec.org/advisories/RUSTSEC-2026-0231.html) | `nostr-relay-pool` 0.43.1 | Authentication-challenge memory exhaustion |
| [RUSTSEC-2026-0342](https://rustsec.org/advisories/RUSTSEC-2026-0342.html) | `quinn-proto` 0.11.14 | Datagram buffer-limit bypass |
| [RUSTSEC-2026-0339](https://rustsec.org/advisories/RUSTSEC-2026-0339.html) | `quinn-proto` 0.11.14 | Connection-ID memory growth |
| [RUSTSEC-2026-0338](https://rustsec.org/advisories/RUSTSEC-2026-0338.html) | `quinn-proto` 0.11.14 | Stream-frame panic |
| [RUSTSEC-2026-0340](https://rustsec.org/advisories/RUSTSEC-2026-0340.html) | `quinn-proto` 0.11.14 | ACK-frequency panic |
| [RUSTSEC-2026-0185](https://rustsec.org/advisories/RUSTSEC-2026-0185.html) | `quinn-proto` 0.11.14 | Stream reassembly memory exhaustion |
| [RUSTSEC-2026-0220](https://rustsec.org/advisories/RUSTSEC-2026-0220.html) | `ruint` 1.17.2 | Incorrect shift arithmetic |
| [RUSTSEC-2026-0346](https://rustsec.org/advisories/RUSTSEC-2026-0346.html) | `rustls` 0.23.37 | TLS secrets in debug output |
| [RUSTSEC-2026-0285](https://rustsec.org/advisories/RUSTSEC-2026-0285.html) | `rustls` 0.23.37 | TLS encryption-level validation |
| [RUSTSEC-2026-0348](https://rustsec.org/advisories/RUSTSEC-2026-0348.html) | `rustls` 0.23.37 | Certificate decompression memory exhaustion |
| [RUSTSEC-2026-0349](https://rustsec.org/advisories/RUSTSEC-2026-0349.html) | `rustls` 0.23.37 | Key-exchange downgrade |
| [RUSTSEC-2026-0104](https://rustsec.org/advisories/RUSTSEC-2026-0104.html) | `rustls-webpki` 0.103.8 | Revocation-list parser panic |
| [RUSTSEC-2026-0098](https://rustsec.org/advisories/RUSTSEC-2026-0098.html) | `rustls-webpki` 0.103.8 | URI name constraints |
| [RUSTSEC-2026-0099](https://rustsec.org/advisories/RUSTSEC-2026-0099.html) | `rustls-webpki` 0.103.8 | Wildcard name constraints |
| [RUSTSEC-2026-0049](https://rustsec.org/advisories/RUSTSEC-2026-0049.html) | `rustls-webpki` 0.103.8 | Revocation distribution-point matching |
| [RUSTSEC-2026-0382](https://rustsec.org/advisories/RUSTSEC-2026-0382.html) | `rustls-webpki` 0.103.8 | Distrusted intermediate certificates |
| [RUSTSEC-2026-0009](https://rustsec.org/advisories/RUSTSEC-2026-0009.html) | `time` 0.3.44 | Stack exhaustion |
| [RUSTSEC-2026-0381](https://rustsec.org/advisories/RUSTSEC-2026-0381.html) | `webpki-roots` 1.0.5 | Distrusted intermediate trust |

The seven unmaintained entries are `atomic-polyfill` (RUSTSEC-2023-0089), `derivative`
(RUSTSEC-2024-0388), `instant` (RUSTSEC-2024-0384), `nostr-relay-pool`
(RUSTSEC-2026-0243), `paste` (RUSTSEC-2024-0436), `proc-macro-error2`
(RUSTSEC-2026-0173), and `rustls-pemfile` (RUSTSEC-2025-0134). The seven unsound entries
are `anyhow` 1.0.102 (RUSTSEC-2026-0190), three `git2` 0.20.3 findings
(RUSTSEC-2026-0183, RUSTSEC-2026-0008, RUSTSEC-2026-0184), `lru` 0.16.3
(RUSTSEC-2026-0253), and `rand` 0.8.5 plus 0.9.2 (both RUSTSEC-2026-0097). Yanked
packages are `async-utility` 0.3.1, `negentropy` 0.5.0, and `spin` 0.9.8.

An isolated Dart compatibility check against 0.26.1/FRB 2.13.0 found no analyzer errors
in the existing Spark service and its tests; all 12 service tests passed unchanged.
This did not rebuild the app's bridge or validate a live SDK connection. The coordinated
upgrade is justified by payment and balance fixes: upstream 0.22 fixes duplicate balance
accounting and concurrent transfer claims, while 0.23 fixes malformed HTLC hash handling,
invoice amount rounding, and requested/invoice amount validation. See the
[0.22 release notes](https://github.com/breez/spark-sdk/releases/tag/0.22.0) and
[0.23 release notes](https://github.com/breez/spark-sdk/releases/tag/0.23.0).
Upgrading to 0.26.1 alone does not
remediate these findings: release needs an audited upstream/forked native dependency
tree, rebuilt and verified platform artifacts, and provider recovery/payment tests.
Updating only the app's Rust lockfile or modifying a dependency in a developer's local
package cache is not a reproducible fix. This remains a release blocker.

### Spark upgrade persistence fixture

An isolated, copy-based SQLite exercise passed three tests. It used the actual
`current_migrations()` SQL extracted from SDK commits
`68d8e1c623f0deeb9331146e2ea1514e6294ff1b` (the former Flutter pin's underlying SDK) and
`eab30baed1122824a33dc03ee81ef3d9454f5580` (0.26.1), with the SDK's exact
`rusqlite` 0.32.1 and `rusqlite_migration` 1.3.1 versions.

The fixture created a schema-39 wallet with 14 representative rows, closed it, copied
the database, and applied the new WAL setting and schema-44 migrations to the copy.
Payment amounts, HTLC details, descriptions, settings, pending deposits/refunds, contacts,
cross-chain records, and sync queues/revisions were retained; SQLite's integrity check
passed and the original file remained byte-identical. Reopening was idempotent. The old
migration runner rejected the newer schema without changing its rows: downgrade after
migration is not supported by this test, so retain an untouched pre-upgrade backup.

Source comparison found no change to `Seed::Entropy` byte handling or mainnet account/key
derivation defaults for this app's connection path. The fixture runs the SQLite migration
sequence, not the complete SDK, new durable tree store, remote synchronization, or a
funded wallet. These three one-off checks are separate from the 23 application Rust tests
and do not establish provider recovery or payment success.

### Release gates and coverage limits

- Confirm the intended Android application ID and signing identity. The current ID is
  `com.example.qiqstr`, and the package version is still `0.1.0+1`. An update to an existing
  distribution must preserve its application ID and signing continuity and use an
  appropriate higher build number. Release signing no longer falls back to a debug key;
  absent `key.properties`, there is no configured release signer. A signed store artifact
  and upgrade from the prior released binary have not been validated.
- Extend Android coverage to signed releases and supported devices beyond the tested
  API 36 ARM64 emulator. The obsolete NDK
  26.1.10909125 override was replaced with Flutter's NDK default (28.2.13676358 in the
  verified Flutter release). Gradle is pinned to 8.14.6 with a distribution checksum,
  Android Gradle Plugin to 8.11.1, and Kotlin to 2.2.21. The current Flutter configuration
  sets Android minimum API 24, target API 36, and compile API 36; iOS minimum is 15.
  Verify these supported-version changes against previously distributed releases.
  The normal debug APK's 16 packaged 64-bit libraries and unsigned release APK's 14 passed
  ELF LOAD alignment; both APKs passed ZIP alignment. All four mobile scenarios passed
  on a 16 KB-page emulator, and a debug-key-signed copy of the release APK passed a launch
  smoke check. Repeat artifact checks and runtime testing for the final store artifact
  and every shipped ABI. These results do not verify signed upgrades or physical-device
  behavior.
  Android documents native-library and device checks in its
  [16 KB page-size guidance](https://developer.android.com/guide/practices/page-sizes).
- Android configuration disables cloud backup and excludes app data from device transfer.
  This configuration was reviewed, but actual backup, restore, and OEM transfer behavior
  has not been exercised. Explicit transfer exclusions matter because `allowBackup=false`
  alone is not sufficient on every device. See
  [Android's backup documentation](https://developer.android.com/identity/data/autobackup).
  These Android rules make no assertion about iOS backup behavior.
- Cashu has an independent randomly generated `cashu_seed.bin` and a persistent SQLite
  wallet database. Nostr identity and Spark recovery backups do not back up this Cashu
  state. The reviewed app does not expose a Cashu seed/database export-and-restore flow.
  Recovery of retained Cashu balances after device loss, reinstall, or device transfer
  remains a release gap; do not promise recovery from the identity or Spark key alone.
- Run signed physical-device iOS tests and a release archive. Simulator success and an
  unsigned device Release build do not establish release signing, physical-device native
  compatibility, device Keychain
  lifecycle/recovery, or
  camera/QR permissions. Existing CocoaPods fallback builds are evidence only for the
  toolchain tested; no future mandatory Swift Package Manager deadline was verified here.
- Validate Breez API-key configuration, funded Spark recovery and payments, NWC payments,
  Cashu mint settlement and interrupted-operation recovery, and real payment limits/fees.
  Automated wallet tests use controlled substitutes or loopback services. No real funds
  were sent. Full-ID Spark cache-directory migration and legacy wallet-format recovery
  still require external-provider validation.
- Complete end-to-end media upload/download, camera/QR, background/resume, notification,
  poor-network, and accessibility checks on supported devices. Route opening and widget
  tests cover selected behavior; they do not exercise every action on each screen.
- Existing architecture and localization debt remains. The September file counts above
  are historical rather than a current measurement, and an analyzer pass does not prove
  compliance with every repository architecture rule.
