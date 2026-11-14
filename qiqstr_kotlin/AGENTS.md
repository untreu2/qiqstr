# qiqstr for Android (Kotlin)

Native Android client written in Kotlin and Jetpack Compose. It is a port of the SwiftUI app in `../qiqstr_swift` and uses the same Rust core (`../qiqstr_rust`) through the same UniFFI bridge (`../qiqstr_rust/uniffi`, crate `qiqstr_core`). When porting a screen or service, read the matching Swift file and keep its behavior, string keys, and names.

## Build

```sh
scripts/build-rust.sh                       # release .so for arm64-v8a + x86_64, then Kotlin bindings
PROFILE=dev ABIS=x86_64 scripts/build-rust.sh
export JAVA_HOME=<JDK 17>
./gradlew :app:compileDebugKotlin           # fast check
./gradlew :app:assembleDebug
```

`app/src/main/jniLibs/` and the generated bindings in `app/src/main/java/com/qiqstr/core/` are build products and are not committed. Debug builds accept `--es QIQ_LOGIN <nsec|hex|mnemonic>` as a launch extra to sign in automatically when no account is stored. Use generated test keys only. Never message, react to, or zap real users from test accounts.

## Rust ↔ Kotlin

- `import com.qiqstr.core.*` exposes every core function in camelCase (`dbGetHydratedFeedNotes`, `createSignedEvent`, `sendEvent`, ...). Most are `suspend`. Integer arguments are unsigned Kotlin types (`10u`, `x.toUInt()`, `kind.toUShort()`).
- Errors are `QiqException.Failed(reason)`. Show them with `coreErrorMessage(error)` or `ToastCenter.error(error)`.
- Streams take an `EventSink`. Use `EventStream.make { sink -> someStreamingFn(..., sink) }` to get a `Flow<String>`.
- JSON comes back as strings. Use `Json.obj/array/string` and the `JSONObject.str/int/long/bool/strings/tags/objects` helpers in `core/Json.kt`. Build filters as Kotlin maps: `Json.string(mapOf("kinds" to listOf(1), "authors" to listOf(pk)))`.

## Layout

| Package | Responsibility |
|---|---|
| `app` | `Router` (per-tab stacks, sheets, compose, links), `Route`, `RouteDestination`, `HomeScreen`, `RootScreen` |
| `core` | `Json`, `L()` localization, `Prefs` (UserDefaults), `SecureStore` (Keychain), theme (`AppColors`, `AppFont`), `TimeFormat`, `NostrLink` |
| `core/components` | Shared composables: `ProfileAvatar`, `RemoteImage`, `PrimaryButton`, `SecondaryButton`, `PillButton`, `IconTile`, `EmptyStateView`, `LoadingView`, `QiqTextField`, `SectionHeader`, `BackTopBar`, `RelativeTimeText`, `TextAction` |
| `domain` | `Note`, `Profile`, `Article`, `NotificationItem`, `ParsedContent` |
| `data/accounts` | `AccountStore`, `Ncryptsec`, `Nip05Resolver`, `AccountData` |
| `data/sync` | `Session`, `SessionHooks`, `SyncService`, `DataBus`, `ProfileCache`, `NotificationBadge`, `FeatureRegistry` |
| `data/services` | `RelayConfig`, `FollowService`, `MuteService`, `HiddenNotesStore`, `ReadOnlyGate`, `ListConfirmation`, `ToastCenter` |
| `ui/<feature>` | Screens, a ViewModel per screen, and the feature's own services |

## State

- Swift `@Observable` singletons are Kotlin `object`s holding Compose state (`var x by mutableStateOf(...)`, `mutableStateMapOf`). Composables read them directly.
- Screens get an `androidx.lifecycle.ViewModel` via `viewModel()`. Each navigation entry has its own `ViewModelStore`, cleared when popped. ViewModels use `viewModelScope`; app-wide work uses `App.scope`.
- Reload on data changes with `LaunchedEffect(DataBus.feedVersion) { ... }` (same as Swift's `.task(id: bus.feedVersion)`).
- Each feature registers reset/load work in its `XFeature` object (`SessionHooks.onTeardown`, `SessionHooks.onBootstrap`), listed in `data/sync/FeatureRegistry.kt`.
- Views never call `com.qiqstr.core` directly. They use a ViewModel, which uses services.

## Strings

- `L("key")` / `L("key", "count" to 3)`. Keys and tables come from the Swift `.strings` files, converted to `app/src/main/assets/i18n/<lang>/<Table>.json` by `scripts/strings_to_json.py`. Reuse existing keys.
- A new string goes into the feature's table (`Auth`, `Feed`, `Profile`, `Explore`, `DM`, `Wallet`, `Settings`, `Reader`) in **all three** languages (en, tr, de).

## Design

qiqstr is monochrome: `AppColors` (black/white, `#0A0A0A` dark background), orange `accent` only for unread dots, Poppins Bold (`AppFont.brand`) for the wordmark and big headings, capsule primary buttons, rounded icon tiles (`IconTile`). Interaction colors: `reaction` red, `reply` blue, `repost` green, `zap` yellow.

It should feel like a native Material 3 Android app: `Scaffold` + `TopAppBar`/`LargeTopAppBar` with scroll behavior, `NavigationBar`, `ModalBottomSheet`, `PullToRefreshBox`, `DropdownMenu` for overflow, `AlertDialog` for confirmations, `SearchBar`, `ListItem`, `Switch`, `SegmentedButton`/`PrimaryTabRow` for in-screen tabs, swipe-to-dismiss where Swift uses swipe actions, Material icons (`Icons.Outlined.*`). Use `MaterialTheme.typography` styles, not hard-coded font sizes, except the wordmark and wallet balance. Keep Swift's `accessibilityIdentifier`s as `Modifier.testTag`.

## Rules

- Avoid comments. Code should read clearly on its own.
- Replaceable lists (kind 0, 3, 10000, 10001, 30001, 10015) are edited as a merge onto the newest event fetched from relays (`SyncService.latestEditableEvent`), never built from an empty or cached local copy.
