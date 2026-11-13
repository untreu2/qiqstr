# App Store submission checklist

Answers and settings for App Store Connect that cannot live in code. Review them before each submission.

## Before archiving

1. `scripts/build-rust.sh` (release, device + simulator). The XCFramework must contain an `ios-arm64` slice; a `PROFILE=dev` build is simulator-only.
2. `xcodegen generate`, set `DEVELOPMENT_TEAM` in `project.yml` (or in Xcode), bump `CURRENT_PROJECT_VERSION` for every upload and keep it identical in the app and both extensions.
3. Archive the `Qiqstr` scheme in Release. The `-QIQ_LOGIN` launch argument is compiled out of Release (`#if DEBUG`).
4. Privacy manifests ship in the app (`Qiqstr/Resources/PrivacyInfo.xcprivacy`), the share extension and the widget extension. If a new API from Apple's required-reason list is used, update them.

## App Review notes (paste and adapt)

> qiqstr is a client for Nostr, an open social protocol. Accounts are key pairs created on the device; there is no server account and no sign-in with a third party.
>
> To review: tap "Create a new account", accept the terms, and skip the optional onboarding steps. The Explore feed shows public content immediately.
>
> Moderation (guideline 1.2): users accept terms with a zero-tolerance clause before any content is shown. Every note, profile, conversation, live stream, live chat message and article has Report and Mute/Block in its menu. Reported content is hidden for the reporter immediately, and blocked users disappear from feeds, threads, replies, messages and notifications. Posts marked sensitive are blurred. Reports and complaints sent to the support link (Settings > Contact support) are reviewed within 24 hours.
>
> Account deletion (5.1.1(v)): Settings > Delete account. It sends deletion requests to relays and erases the account's keys and data from the device.
>
> Payments: the app does not hold funds and sells nothing. The wallet tab remote-controls a Lightning wallet the user already owns, through Nostr Wallet Connect. Zaps are optional tips sent directly from the user's wallet to another person's wallet; they unlock no content or features, and the developer receives nothing.

## Decisions for the owner

- **Zaps on notes (3.1.1 / 3.2.1(vii)).** Notes show a zap button that tips the author of that note. Apple has rejected Nostr clients for content-attached tips before. If review objects, set `AppStorePolicy.allowsContentZaps = false` (`Qiqstr/Core/Utilities/AppStorePolicy.swift`): the button and one-tap zaps disappear from notes, and zapping a person from their profile stays.
- **Cashu (3.1.5).** Redeeming a Cashu token briefly holds ecash on the device before paying it out to the connected wallet. If the account is an individual (not an organisation) enrolment and review flags this as a wallet, set `AppStorePolicy.allowsCashu = false`.
- **Sensitive content toggle (1.2).** The global "show sensitive content" switch is hidden in this build (`AppStorePolicy.allowsSensitiveContentToggle = false`); users can still reveal one post at a time.
- **Support contact.** Settings > Contact support and the terms point to GitHub issues. An e-mail address is friendlier for reviewers and users; if you add one, change `AuthTermsText.supportURL` and section 15 of the terms.

## App Privacy (nutrition label)

The developer collects no data: there is no server, analytics or crash reporting. Answer **"No, we do not collect data from this app"**. Data sent to relays, media hosts and wallets goes to third-party services the user chooses and is described in the in-app privacy policy. Tracking: **No**.

Privacy Policy URL: host the text of `Qiqstr/UI/Auth/AuthTermsText.swift` (for example as an iOS-specific page next to `TERMS.md`). The repository-wide `TERMS.md` still describes the Flutter app.

## Age rating

User-generated content with unrestricted web content: answer "Yes" to user-generated content and to unrestricted web access (links open in Safari views). Expect a 17+ / 18+ rating.

## Export compliance

The app implements its own encryption (NIP-44, MLS for messages, SQLCipher, AES-GCM for media) using standard algorithms. Answer "Yes, the app uses encryption", then "Yes, it qualifies for an exemption" only after confirming with your own export-control assessment (standard, published algorithms in a mass-market app usually fall under the 5D992 / mass-market exemption, which still requires the annual self-classification report for US distribution). Once settled, add `ITSAppUsesNonExemptEncryption` to `Qiqstr/Resources/Info.plist` so the question is not asked for every build.

## Screenshots and metadata

- Do not show "zap a note" flows if note zaps are turned off for review.
- Keep the description free of claims such as "nobody can ban you" or "censorship-proof"; describe moderation tools instead.
- Support URL must open a page with a way to contact you.

## Known open items (not blocking submission)

Everything else from the November 2026 audit is fixed. What is left needs an upstream release:

- **Dependencies.** `cargo audit` still lists advisories that no release can fix today. None is exploitable in this app:
  - `libsqlite3-sys` 0.28 (CVE-2026-119375, `-wal` file with a different page size). The attacker would need to write files into the app container. The fixed release also bundles an affected SQLCipher, and `cdk-sqlite` 0.18 still requires `rusqlite` 0.31.
  - `libcrux-*` 0.0.x. Only `libcrux-sha3` is compiled, through `hpke-rs`, and only its one-shot SHAKE is called. The affected incremental squeeze and AVX2 code is never used. The other `libcrux` crates are in `Cargo.lock` but not built.
  - `crypto-bigint` 0.5, through `elliptic-curve` 0.13 used by OpenMLS. This is a timing side channel; the fix needs the `elliptic-curve` 0.14 ecosystem.
  - `lru` 0.16 and the unmaintained `nostr-relay-pool` 0.44. `nostr-sdk` 0.45 fixes both, but `mdk-core` 0.8 (messages) still requires `nostr` 0.44. The `lru` bug needs a key whose destructor panics, and nostr keys never do.
  - Upgrade when `mdk-core` moves to `nostr` 0.45.

## How the audit fixes behave

- **Zap totals:** a receipt counts only with a signed zap request that matches the recipient, note and paid amount. Once the recipient's Lightning provider key is known, the receipt must also be signed by that provider. The key is known for your own account, for profiles you open and for people you zap; it is cached for 3 days. Receipts for other recipients are checked only against the request.
- **Lists:** if no relay returns your pins, bookmarks, followed topics or relay list, the app asks before starting a new list. It doesn't ask for accounts created on this device in the last 24 hours.
- **Messages:**
  - Message requests from people you don't follow stay in Requests. They don't notify, don't set the tab dot, and keep media hidden until you accept or reply.
  - Messages that arrive before their key update are decrypted once the update lands.
  - Older history loads 200 messages at a time.
  - Failed sends are kept on the device, encrypted at rest, and offered for retry after a restart.
  - An idle chat polls less often, backing off from 8 s to 60 s. Live delivery uses a subscription.
  - The encrypted message store is excluded from device backups, because restoring old MLS state would break existing chats.
- **Wallet:** an NWC payment that times out is checked with `lookup_invoice` before being reported as "may still complete". Cashu ecash and its seed are kept per account, using the "complete unless open" file protection class. On upgrade, existing ecash moves to the first account that opens the wallet. It is kept on account deletion, so funds are not destroyed.
- **Notifications:** the widget count and tab dot skip muted, spam-filtered and hidden items. Unread dots stay when you return from a notification and clear the next time the tab is opened.
- **Terms:** the in-app policy is shown in English, Turkish or German. The translation says the English text prevails. `TERMS.md` at the repository root still describes the cross-platform app.
