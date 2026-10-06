# WODwire for iPhone and Apple Watch

This folder is a native SwiftUI port of the Android **phone** app and **Wear OS** app. It talks to the same Koyeb backend and the same Clerk instance as Android, so logs, sessions, social posts and profiles are shared across Android, iOS and the web dashboard.

| Android | Apple |
|---|---|
| Jetpack Compose phone app | `WODwire/` (SwiftUI, iOS 17+) |
| Wear OS app | `WODwireWatch/` (SwiftUI, watchOS 10+) |
| `shared` module (PlateType, BarbellState) | `Shared/` (compiled into both targets) |
| Health Connect | **HealthKit** (`Health/HealthKitManager.swift`) |
| Wearable Data Layer | **WatchConnectivity** (`Connectivity/PhoneConnectivity.swift`, `WODwireWatch/WatchViewModel.swift`) |
| Retrofit | `URLSession` (`API/APIClient.swift`) |
| Clerk Android SDK | Clerk iOS SDK: ClerkKit + ClerkKitUI (`Auth/AuthBridge.swift`) |
| SharedPreferences | `UserDefaults` + JSON files in Documents |

Screens: HOME (goal rings, heart, energy, week strip), BARBELL (plate loader that stays in sync with the watch), SOCIAL (feed, friends, groups, notifications, posts, lift-progress cards, profiles, ⚔ Versus), TRAINING (logs with edit sheet, sessions with an interactive HR graph) and ACCOUNT (sign-in, profile editor, sync, Apple Health, progress overview, settings).

---

## 1. Requirements
- A Mac with **Xcode 26** or newer. The current Clerk iOS SDK needs it.
- An Apple Developer account. A free account can run the app on your own devices, but HealthKit and Associated Domains need a paid account for full use.
- An iPhone on iOS 17+ paired with an Apple Watch on watchOS 10+. The simulator works too, but it has no real health data.

## 2. Generate the Xcode project
The project is described in `project.yml` ([XcodeGen](https://github.com/yonaskolb/XcodeGen)), so there's no hand-edited `.pbxproj` to break.

```bash
brew install xcodegen
cd apple
xcodegen generate
open WODwire.xcodeproj
```

Xcode then downloads the Clerk Swift package automatically (File ▸ Packages ▸ Resolve if it doesn't).

## 3. Signing
1. Select the **WODwire** project ▸ target **WODwire** ▸ *Signing & Capabilities*.
2. Tick *Automatically manage signing* and pick your **Team**. Do the same for the **WODwireWatch** target.
3. If `com.gravweight.wodwire` is already taken, change the bundle IDs in `project.yml`:
   - iOS: `com.yourname.wodwire`
   - Watch: `com.yourname.wodwire.watchkitapp`
   - Also update `WKCompanionAppBundleIdentifier` to match the iOS ID.
   - Then run `xcodegen generate` again.
4. The capabilities (HealthKit, Associated Domains) are already in `WODwire/WODwire.entitlements`. Xcode registers them when it signs.

> Tip: put your Team ID in `DEVELOPMENT_TEAM` in `project.yml` so regenerating keeps it.

## 4. Clerk dashboard (one time)
Use the same Clerk application the Android and web apps use (`aware-mayfly-5498`).
1. **Configure ▸ Native applications**: enable the **Native API**.
2. Add an **iOS application** with your **Team ID** and **bundle ID** (for example `ABCDE12345.com.gravweight.wodwire`).
3. Make sure **Google** is enabled under *SSO connections*. It already is for Android.
4. The Associated Domain `webcredentials:aware-mayfly-5498.clerk.accounts.dev` is already in the entitlements.

The publishable key is in `WODwire/Auth/AuthBridge.swift` (`AppConfig.clerkPublishableKey`).

## 5. Run
1. Choose the **WODwire** scheme and your iPhone, then press ▶. The watch app is embedded and installs on the paired watch automatically. Or open the Watch app on the iPhone ▸ WODwire ▸ Install.
2. On first launch, allow Apple Health access. Then go to ACCOUNT ▸ **Sign in with Google**.
3. To debug the watch on its own, choose the **WODwireWatch** scheme and your watch.

### How the watch link works
- Phone ⇄ watch barbell state goes through `updateApplicationContext`, plus a live `sendMessage` when the watch is reachable.
- The watch's **LOG WEIGHT** sends a `log_trigger` with weight (lbs), timestamp and a nonce. It uses `sendMessage` when reachable and falls back to queued `transferUserInfo`. The phone de-duplicates by nonce, adds the log offline-first and uploads it when signed in.
- The keys and payloads match the Android Data Layer (`/gravweight/state`, `/gravweight/log_trigger`, plate case names, `isMetric`).

## 6. Folder layout
```
apple/
├─ project.yml                 XcodeGen spec (targets, packages, Info.plist, entitlements)
├─ Shared/                     PlateType, BarbellState, WatchKeys, Brand colours
├─ WODwire/                    iPhone app
│  ├─ WODwireApp.swift         @main, theme, 5-tab layout
│  ├─ PhoneViewModel.swift     state, offline-first logs, sync, social
│  ├─ API/                     Flex (lenient Codable), DTOs, APIClient
│  ├─ Auth/AuthBridge.swift    every Clerk call lives here
│  ├─ Health/                  HealthKit reader
│  ├─ Connectivity/            WatchConnectivity (phone side)
│  ├─ Theme/                   palette, formatting, shared components
│  ├─ Views/                   Home, Companion, Social, Profile, Versus, Training, Sessions, Account
│  └─ Assets.xcassets
└─ WODwireWatch/               Apple Watch app (main view, plate row, view model)
```

## 7. Troubleshooting
- **Clerk compile errors** (the API renamed in a newer SDK): only `Auth/AuthBridge.swift`, plus `AuthView()` in `AccountView.swift` and `Clerk.shared` / `@Environment(Clerk.self)` in `WODwireApp.swift`, use the Clerk SDK. Adjust those calls to the current [Clerk iOS docs](https://clerk.com/docs/quickstarts/ios). You can also pin an exact version in `project.yml`.
- **Swift 6 concurrency errors**: the project uses the Swift 5 language mode (`SWIFT_VERSION: 5.0`). Keep it unless you want to migrate.
- **"Sign in with Google" opens nothing**: check the Clerk Native API setting and the iOS app entry (Team ID + bundle ID). Use **More sign-in options** to sign in through Clerk's built-in AuthView.
- **No health data**: Settings ▸ Health ▸ Data Access & Devices ▸ WODwire ▸ turn everything on. Then tap ACCOUNT ▸ **SYNC HEALTH DATA**.
- **Watch shows "not connected"**: the watch app must be installed, and both devices must be unlocked the first time. The phone pill uses `isPaired && isWatchAppInstalled`.
- **Without XcodeGen**:
  1. In Xcode, create *iOS App* "WODwire" (SwiftUI), then add a *watchOS App* target "WODwireWatch" (companion to the iOS app).
  2. Delete the template Swift files.
  3. Drag `WODwire/` + `Shared/` into the iOS target and `WODwireWatch/` + `Shared/` into the watch target.
  4. Add the package `https://github.com/clerk/clerk-ios` (ClerkKit, ClerkKitUI) to the iOS target.
  5. Add the HealthKit and Associated Domains capabilities, plus the two `NSHealth…UsageDescription` Info keys from `project.yml`.
