# funnelbase-ios

The Funnelbase iOS SDK, a Swift package at the repository root (Swift Package Manager installs a
package only from a repository whose root holds `Package.swift`): `FunnelbaseCore` (Foundation
only), `Funnelbase` (what an app links) and `FunnelbaseNotificationService` (what a notification
service extension links), plus `demo-ios`, a SwiftUI trading app that proves them on a device.
Released by git tag. Public repository, Apache 2.0.

Read before changing an area: [docs/event-contract.md](docs/event-contract.md) (what goes on the
wire), [docs/sdk-ios.md](docs/sdk-ios.md) (the targets, the app group, push end to end, what a
simulator cannot prove), [docs/push.md](docs/push.md), [docs/demo-app.md](docs/demo-app.md),
[RELEASING.md](RELEASING.md).

## Rules

- **The wire and the device are a contract.** Never change `Sdk.name`, the JSON field names, the
  reserved `$` events, UserDefaults keys or the app-group layout as a side effect: a renamed stored
  key forgets every install's ids. A deliberate wire change ships in the backend first, which must
  keep accepting what released SDKs send, then here and in funnelbase-android together, then in
  funnelbase-flutter if a native method changed. The Android SDK mirrors this one method for
  method.
- **Public names stay.** `Analytics`, `AnalyticsConfig`, `AnalyticsDay`,
  `AnalyticsNotificationService`… are API. Renaming one is a breaking release.
- **No dependencies, and the core stays Foundation only**, so `swift test` runs the contract on a
  Mac without a simulator. Platform code belongs in `Funnelbase` or
  `FunnelbaseNotificationService`.
- **Two Apple rules shape push:** buttons come from a category registered by the extension, and
  the extension runs only for a `mutable-content` payload. `xcrun simctl push` ignores
  `mutable-content`, so the extension's work is proven only on a device.
- **The demo's project is generated.** Edit `demo-ios/project.yml`, then `xcodegen generate` in
  `demo-ios/`, and commit the regenerated `.xcodeproj` too.
- **No secrets in the repo.** `demo-ios/Config.xcconfig` (the ingest key) and
  `GoogleService-Info.plist` are gitignored; `Config.example.xcconfig` is the template. No
  `DEVELOPMENT_TEAM` in the project either.

## Checks

```bash
swift test
xcodebuild -project demo-ios/TradeDemo.xcodeproj -scheme TradeDemo \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Working here

- Every change on its own branch (`feature/`, `fix/`, `change-request/`, `refactor/`, `chore/`,
  `docs/` + a slug) cut from `origin/main`, through a pull request. Nothing is committed until
  the maintainer approves opening the PR, and nothing merged until they approve that separately.
- Ask before pushing anything to GitHub: this repository is public.
- **A release is a plain semver tag** (`0.3.0`, no `v`) and apps resolve it at once. Never tag
  without being asked; `Sdk.version` and CHANGELOG must agree with it (RELEASING.md). A tag apps
  have resolved must never be moved: SwiftPM records each version's commit and refuses a changed
  one.
- Commits are authored as `Funnelbase <349443583+Funnelbase@users.noreply.github.com>`.
