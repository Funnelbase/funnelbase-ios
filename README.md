# Funnelbase iOS SDK

Product analytics and push for iOS apps, sending to [Funnelbase](https://funnel-base.com).
A Swift package with no dependencies: events with typed properties, automatic sessions, screen
views, identity, an offline queue, and push — rendered by a notification service extension, with
receipts and opens reported — over APNs, Firebase or a gateway of your own.

- iOS 16+, Swift 5.9+
- Swift Package Manager
- Apache 2.0

Also available: [Android](https://github.com/Funnelbase/funnelbase-android) and
[Flutter](https://github.com/Funnelbase/funnelbase-flutter).

## Install

In Xcode, **File → Add Package Dependencies…** and enter:

```
https://github.com/Funnelbase/funnelbase-ios.git
```

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Funnelbase/funnelbase-ios.git", from: "0.2.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "Funnelbase", package: "funnelbase-ios")]),
]
```

Link `Funnelbase` to the app, and `FunnelbaseNotificationService` to a notification service
extension if you send push.

## Quick start

Create an app in the Funnelbase dashboard, enable its iOS platform and generate an ingest key.
Then, as early as the app starts:

```swift
import Funnelbase

Analytics.initialize(
    AnalyticsConfig(
        apiKey: "ana_ios_…",
        endpoint: "https://ingest.example.com",
        appGroup: "group.com.example.app"   // only needed for push
    )
)
```

```swift
Analytics.screen("markets")
Analytics.track("instrument_viewed", properties: ["symbol": "AAPL"])

// At sign-in and sign-up, and on each launch while signed in:
Analytics.identify(userId, traits: ["plan": "pro", "renews_on": AnalyticsDay(year: 2026, month: 12, day: 1)])

// At sign-out:
Analytics.reset()
```

Every custom event and its properties must be declared in the app's event catalog in the
dashboard first; an undeclared one is refused. Sessions, `$first_open` and the identity rules are
the SDK's: see [the event contract](docs/event-contract.md).

## Push

```swift
// AppDelegate
func application(_ application: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Analytics.push.setAPNSToken(deviceToken)        // or setToken(fcmToken, kind: TokenKinds.fcm)
}
```

```swift
// The notification service extension: this is all of it.
import FunnelbaseNotificationService

class NotificationService: AnalyticsNotificationService {
    override var appGroup: String? { "group.com.example.app" }
}
```

Report taps with `Analytics.push.handle(response:)` and route the payload it returns. The app and
the extension share an app group so a receipt recorded while the app is not running reaches its
queue. Details: [docs/push.md](docs/push.md), [docs/sdk-ios.md](docs/sdk-ios.md).

## Notification topics

```swift
let topics = try await Analytics.topics.fetch()   // the app's topics and this person's choices
Analytics.topics.set("price_alerts", subscribed: false)
```

## Documentation

- [docs/sdk-ios.md](docs/sdk-ios.md) — the package, the app group, push end to end, dates, topics
- [docs/push.md](docs/push.md) — tokens, the payload, rendering, taps, testing without a provider
- [docs/event-contract.md](docs/event-contract.md) — what every Funnelbase client sends
- [docs/demo-app.md](docs/demo-app.md) — the demo app

## The demo app

`demo-ios/` is a SwiftUI trading app that uses the SDK from this repository by path. Copy
`demo-ios/Config.example.xcconfig` to `Config.xcconfig`, add an ingest key, and open
`demo-ios/TradeDemo.xcodeproj`. See [docs/demo-app.md](docs/demo-app.md).

## Development

```bash
swift test    # the SDK's tests, on a Mac, no simulator needed
```

Releases: [RELEASING.md](RELEASING.md). Changes: [CHANGELOG.md](CHANGELOG.md).

## License

Apache License 2.0 — see [LICENSE](LICENSE).
