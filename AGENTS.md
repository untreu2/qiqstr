# qiqstr for iOS (Swift)

Native SwiftUI port of [qiqstr](https://github.com/untreu2/qiqstr). The Rust core from the Flutter app (nostr-sdk, LMDB, NIP-17, NWC, Cashu) is shared and exposed to Swift with **UniFFI**.

## Build

```sh
scripts/build-rust.sh                   # release XCFramework, device + simulator
PROFILE=dev TARGETS=aarch64-apple-ios-sim scripts/build-rust.sh   # fast simulator-only build
xcodegen generate                       # Qiqstr.xcodeproj is generated from project.yml
xcodebuild -project Qiqstr.xcodeproj -scheme Qiqstr -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd build
```

`Qiqstr.xcodeproj` and the XCFramework are build products and are not committed. Run `xcodegen generate` after adding or removing Swift files.

## Rust ↔ Swift

- `rust/src/api/*.rs` is the Rust core from the Flutter app, minus flutter_rust_bridge annotations.
- `rust/src/ffi.rs` is **generated** by `scripts/gen_ffi.py`. It wraps every public `api` function with `#[uniffi::export]`, runs async work on a dedicated Tokio runtime, and maps `anyhow::Error` to `QiqError`. Re-run the script after changing the Rust API. Do not edit it by hand.
- Streams use the `EventSink` callback interface (`rust/src/sink.rs`). On the Swift side, wrap them with `EventStream.make { sink in try await someStreamingFn(..., sink: sink) }` to get an `AsyncThrowingStream<String, Error>`.
- Generated Swift bindings live in `QiqstrCore` (a local Swift package). `import QiqstrCore` exposes the functions in camelCase, for example `dbGetHydratedFeedNotes(...)`, `createNoteEvent(...)`, `sendEvent(...)`. The full list is in `QiqstrCore/Sources/QiqstrCore/qiqstr_core.swift`.
- Use `coreErrorMessage(error)` to show Rust errors.

## App layering

| Layer | Path | Responsibility |
|---|---|---|
| App | `Qiqstr/App` | Entry point, tab shell, `Route` navigation, service registry |
| Core | `Qiqstr/Core` | Theme, localization, shared components, utilities |
| Domain | `Qiqstr/Domain/Models` | Plain value models parsed from Rust JSON (`Note`, `Profile`, `Article`, `NotificationItem`, `ParsedContent`) |
| Data | `Qiqstr/Data` | Rust bridge helpers, accounts (Keychain), `Session`, `SyncService`, feature services |
| UI | `Qiqstr/UI/<Feature>` | SwiftUI screens, with a view model per screen (`@Observable` class, `@MainActor`) |

Rules:
- Views never call `QiqstrCore` directly. They use a view model, which uses services in `Data/`.
- State management uses `@Observable` view models and services. Do not use Combine `ObservableObject`.
- Every user-facing string goes through `L("arbKey")`. Keys come from `Qiqstr/Resources/<lang>.lproj/Localizable.strings`, ported from the Flutter ARB files (en, tr, de). Placeholders use `L("moreReplies", ["count": 3])`. If you need a new string, add it to **all three** `.strings` files.
- Avoid comments. Code should read clearly on its own.
- Swift 5 language mode, default actor isolation is MainActor.

## Design language

qiqstr is monochrome. Use `AppColors` (black/white, near-black `#0A0A0A` dark background), the orange `accent` for small highlights only (unread dots), Poppins Bold (`AppFont.brand`) for the wordmark and big headings, the system font elsewhere, capsule primary buttons (`PrimaryButton`: black-on-white or white-on-black), and soft rounded-square icon tiles (`IconTile`). Interaction colors: `reaction` red, `reply` blue, `repost` green, `zap` yellow.

It should feel like a native iOS 26 app with **Liquid Glass**: system `TabView` and `NavigationStack` toolbars (they're glass automatically), `.glassEffect(...)`, `.buttonStyle(.glass)` / `.glassProminent`, `GlassEffectContainer` for grouped floating controls, native sheets with detents, `.searchable`, swipe actions, context menus, and `.refreshable`. Do not imitate Material.

## Shared state

- `Session.shared`: active account (`pubkey`, `privateKey`, `npub`), phase, account list, login/create/switch/logout.
- `SyncService.shared`: relay syncs (`syncFeed`, `syncProfile`, `syncProfileNotes`, `syncNotifications`, `syncHashtag`, `syncArticles`, `syncNote`, `syncInteractions`, `fetchEvents(filter)`, `publish(eventJson)`), plus realtime subscriptions.
- `DataBus.shared`: version counters (`feedVersion`, `profileVersion`, `notificationVersion`, `interactionVersion`, `dmVersion`, `listsVersion`). Reload with `.task(id: bus.feedVersion)`.
- `ProfileCache.shared`: `profile(pubkey)` and `load([pubkeys])`.
- `Router.shared`: `push(Route)`, `compose(ComposeContext)`, `sheet = .zap(note)`, `showSidebar`, and so on. Screens are reached through `Route` in `App/Route.swift`.
- `ToastCenter.shared.show(...)` and `.error(error)` show toasts.
- `SessionHooks` plus `App/ServiceRegistry.swift` load and reset services on login and account switch.

## Testing

Debug builds accept `-QIQ_LOGIN <nsec|hex|mnemonic>` as a launch argument to sign in automatically when no account is stored. Use generated test keys only. Never message, react to, or zap real users from test accounts.

## Adding strings

Feature strings go in their own table, `Qiqstr/Resources/{en,tr,de}.lproj/<Table>.strings`, where `<Table>` is one of `Auth`, `Feed`, `Profile`, `Explore`, `DM`, `Wallet`, `Settings`. `L(key)` searches every table. Reuse the existing `Localizable.strings` keys (ported from the Flutter ARB files) wherever one fits.
