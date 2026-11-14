# qiqstr for macOS (Swift)

Native macOS SwiftUI app. It compiles the iOS app's sources in `../qiqstr_swift/Qiqstr` (models, services, view models and screens) and adds a Mac shell and a small compatibility layer of its own. It uses the same Rust core through the same UniFFI package (`../qiqstr_swift/QiqstrCore`), so behavior, string keys and services stay identical to iOS. Read `../qiqstr_swift/AGENTS.md` for the app's layering, state and rules; they apply here too.

## Build

```sh
../qiqstr_swift/scripts/build-rust.sh   # XCFramework with iOS, iOS simulator and macOS slices
xcodegen generate                       # QiqstrMac.xcodeproj is generated from project.yml
xcodebuild -project QiqstrMac.xcodeproj -scheme Qiqstr -destination 'platform=macOS' -derivedDataPath build/dd build
open build/dd/Build/Products/Debug/qiqstr.app
```

`QiqstrMac.xcodeproj` and `build/` are not committed. Run `xcodegen generate` after adding or removing Swift files here or in `../qiqstr_swift/Qiqstr`.

The app is not sandboxed: LMDB's POSIX semaphores are blocked in the App Sandbox unless their names carry a team-signed app group prefix. Its data lives in `~/Library/Application Support/me.untreu.qiqstrmac` (`AppDirectories.support` adds the bundle id on macOS). Sign builds with your team (`DEVELOPMENT_TEAM=<team> CODE_SIGN_IDENTITY="Apple Development"` on the `xcodebuild` line, or the Signing pane in Xcode); an ad-hoc signature changes on every build, so macOS asks for the login keychain password each time the app reads its stored keys. Keys are stored under the same keychain service as iOS, `me.untreu.qiqstrswift`.

## Layout

| Path | Responsibility |
|---|---|
| `Mac/App` | `QiqstrMacApp` (window, File and Go menu commands, app delegate that gives SwiftUI sheets a minimum size) and the Mac `HomeView`: a `NavigationSplitView` sidebar (main sections plus a Library section) whose items are `AppTab`s. The detail is one `NavigationStack` bound to `Router.paths[selectedTab]`; only the visible section may write its path, so a section keeps its pushed pages while you are elsewhere. `HomeView` owns the `FeedViewModel` so Home keeps its notes when you switch sections. Also `AppSheetView` |
| `Mac/Compat` | Shims for iOS-only API the shared code calls: `UIImage`/`UIColor` as `NSImage`/`NSColor`, `UIPasteboard`, `UIApplication.open`, feedback generators, `BGTaskScheduler`, and no-op SwiftUI modifiers such as `navigationBarTitleDisplayMode`, `textInputAutocapitalization`, `keyboardType`, `.topBarTrailing`, `.insetGrouped`, `fullScreenCover` (a large sheet), and a `Form` wrapper that always uses `.formStyle(.grouped)`. `.tabBar` maps to an unused accessory bar so hiding it does nothing; `.navigationBar` maps to the window toolbar |
| `Mac/Platform` | Mac versions of views the iOS app builds on UIKit: `QRScannerView` (paste or pick an image), `AuthQRScannerSheet`, `ProfileQRScannerView`, `NoteZoomableImage`, `NotePlayerLayerView`, `NoteFullScreenVideo` (a player window), `SelectableTextView`, and `MacPager` for photo viewers |
| `Mac/Resources` | `Info.plist`, entitlements, and `<lang>.lproj/Mac.strings`, which `L()` searches first on macOS: Mac wording for strings that mention iOS, plus Mac-only keys (`macGoMenu`, `macLibrary`). Add new keys to all three languages |

The target excludes `App/QiqstrApp.swift` and `App/HomeView.swift` (the iOS entry point and tab bar) and the UIKit-only scanner and Safari files from the shared sources.

## Changing shared code

- Prefer a shim in `Mac/Compat` or a view in `Mac/Platform` over `#if` in shared files. Use `#if os(iOS)` in `../qiqstr_swift/Qiqstr` only for code that cannot compile on macOS (UIKit view controllers, `UIViewRepresentable`, `EditMode`, page-style `TabView`), and keep the iOS branch unchanged.
- After changing `../qiqstr_swift/Qiqstr`, build both apps.
- Sidebar sections `profile`, `reads`, `live`, `lists`, `bookmarks` and `settings` are `AppTab` cases used only by the Mac shell. Every `AppTab` has an entry in `Router.paths` from the start.
- Don't use the sidebar `TabView` style (`.sidebarAdaptable`) for the shell: on macOS its tabs share one navigation context, so `Router.push` shows pages in the wrong section.
- Hide iOS keyboard-only behavior on macOS (for example the onboarding Continue button hiding while a field is focused). Text in pinned bars that uses `.fixedSize(horizontal: false, vertical: true)` needs a `lineLimit`, or the split view's minimum-size pass can stretch the window.

## Testing

Debug builds accept `-QIQ_LOGIN <nsec|hex|mnemonic>` and other `UserDefaults` overrides as launch arguments, for example `open build/dd/Build/Products/Debug/qiqstr.app --args -QIQ_LOGIN <key> -theme_preference light -local_notifications_prompted YES`. ⌘1–⌘7 switch sections and ⌘, opens Settings. Test in light mode. Use generated test keys only. Never message, react to, or zap real users from test accounts.
