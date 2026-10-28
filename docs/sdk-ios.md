# The iOS SDK

The Funnelbase iOS SDK: the same [event contract](event-contract.md) as the Android SDK, written
in Swift, with push. This document is what is specific to Apple devices; push itself is
[push.md](push.md), and the demo app is [demo-app.md](demo-app.md).

## The package

A Swift package with no dependencies, at the root of this repository, deployment target iOS 16.

| Product | Who links it | What is in it |
|---|---|---|
| `Funnelbase` | the app | the `Analytics` facade, the client, push registration and tap reporting |
| `FunnelbaseNotificationService` | the notification service extension | `AnalyticsNotificationService`, the base class that enriches an arriving push and reports the receipt |

Both are thin layers over an internal `FunnelbaseCore` target, which is Foundation only. That
split is what lets `swift test` run the whole of the contract on a Mac, with no simulator: the
queue, the identity rules, the session timeout, the upload classification, the push payload parsing
and the extension's decisions are all core.

```swift
import Funnelbase

Analytics.initialize(
    AnalyticsConfig(
        apiKey: key,
        endpoint: "https://ingest.example.com",
        appGroup: "group.com.example.app"   // needed for push; see below
    )
)
Analytics.track("instrument_viewed", properties: ["symbol": "AAPL"])
Analytics.identify(userId, traits: ["username": name])
```

The surface mirrors Android's method for method — `initialize`, `track`, `screen`, `identify`,
`flush`, `reset`, `push` and `topics` — so one contract describes both clients and a team moving
between them finds the same names. `AnalyticsConfig` carries the same defaults, with one field
Android has no use for: `appGroup`.

## Why an app group

A notification service extension is a **separate process** with its own container. When a push
arrives the app is usually not running, so the receipt is recorded by the extension — and for that
receipt to reach the app's queue, and to be recorded under the same identity the app is using, both
processes have to read and write the same files. On Apple platforms that means an app group.

The split matters, because **a group container survives the app being deleted**. Identity must not:
`device_id` names the install, and a reinstall is a new install. A push registration must not
either, because the SDK sends only what changed, so a remembered token is one it would never
register again — a reinstalled app would go silent, with no way to reach it.

So identity, sessions and the token registration live in the **app's own** container, which the
system deletes with the app. The queue and the credentials the extension needs live in the
**group**, and a copy of identity is mirrored there at startup and whenever it changes, so a
receipt is recorded under the same person. Without a group everything falls back to the app's own
container, and push still works: the extension sends the receipt itself and the app never sees it.
With one, the receipt is durable — queued first, uploaded straight away, and removed from the queue
only if that upload succeeded, so a failure costs nothing but a delay until the app is next opened.

The queue is therefore written by two processes. Appends are a single write to a file opened for
appending, which the kernel does not interleave; the whole-file rewrites (trimming, removing what
was uploaded) go through a temporary file and a replace, so a process death leaves the old queue
rather than half of a new one.

## Push, end to end on an Apple device

1. **The app asks for permission and registers for remote notifications.** The SDK offers
   `Analytics.push.requestAuthorization` as sugar, but an app that wants a considered prompt should
   ask for itself and call `refreshToken` after.
2. **The token.** `Analytics.push.setAPNSToken(_:)` from
   `didRegisterForRemoteNotificationsWithDeviceToken`, or `setToken(_:kind:)` for a Firebase or
   gateway token. The SDK reads the authorization status, which Apple only answers asynchronously,
   and sends `$push_token` with `status` `active` or `disabled` — but only when the token, its kind
   or its status differs from the last one sent, or a registration would be an event per launch.
3. **The push arrives.** Funnelbase sends an alert with `mutable-content`, which is what makes
   Apple run the extension before the banner appears. In its thirty seconds the extension records
   the receipt, registers a category for the message's buttons, sets the thread from the collapse
   key, and downloads the image into an attachment. Whatever fails, the notification is still
   delivered: a push with no picture is worth more than no push.
4. **The tap.** `Analytics.push.handle(response:)` from
   `userNotificationCenter(_:didReceive:withCompletionHandler:)` reports `$push_opened` with the
   button's `action_id`, then hands the payload back so the app can route it. A dismissal is
   reported as nothing.

The extension is one class:

```swift
import FunnelbaseNotificationService

class NotificationService: AnalyticsNotificationService {
    override var appGroup: String? { "group.com.example.app" }
}
```

Two Apple rules shape all of this. Buttons come from a category the app registered and the payload
can only name one, so per-message buttons are registered as the push arrives — the identifier is
derived from the buttons, so identical buttons share a category. And the extension runs only for a
`mutable-content` payload, so a message asking for `render: system` gets no image, no buttons and
no receipt.

## Language and time zone

The device context's `locale` is `Locale.preferredLanguages.first` as a tag, not
`Locale.current.identifier`: `Locale.current` only knows the languages the app is translated
into, so an English-only app on a Turkish iPhone would report `en` and a message's Turkish copy
would never be picked. A per-app language chosen in Settings is first in the list, so it wins, as
it should. Both it and `timezone` (`TimeZone.autoupdatingCurrent`) are read per event, and a
change to either re-registers the push token — at startup, and when the system posts
`NSLocale.currentLocaleDidChangeNotification` or `.NSSystemTimeZoneDidChange` — because the push
registration is what a send reads them from. The notification service extension reads the same
way, but in its own bundle, so its `$push_received` may carry the system language rather than a
per-app one; a receipt picks no copy, so nothing depends on it.

## Dates

A property or trait may be a `Date`, sent as an exact moment in UTC with `Z`, or an
`AnalyticsDay` — a calendar day with no zone, `AnalyticsDay(year:month:day:)` or the day a `Date`
falls on in a given zone — sent as `YYYY-MM-DD`. They are the text a catalog `date` type accepts,
and character for character what Android sends for an `Instant` and a `LocalDate`
([event-contract.md](event-contract.md#dates)). `AnalyticsDay` exists because Foundation has no
day type: a `Date` at local midnight would be sent as the previous evening in UTC east of
Greenwich, and `DateComponents` cannot be told apart from any other value that describes itself.

## Notification topics

`Analytics.topics` mirrors the Android SDK's. `set(_:subscribed:)` queues a passive
`$topic_preference` — no session, no `$first_open` — and uploads the queue at once rather than on
the next timer. `fetch` (a completion on the main queue, or `async throws`) reads `GET /v1/topics`
with the ingest key; a non-2xx answer is `TopicsError.http(status:)`, so a
`503 topics_unavailable` leaves the app to show what it has.

A choice the server may not hold yet wins over its answer. Each `set` is kept **pending** in the
app's own container (not the app group) and overrides the fetched value, marked `chosen`, until a
fetch shows the server holding the same choice as the person's own, the upload carrying it is
refused for good, a reset clears it, or the topic is no longer listed. It is not released when the
upload succeeds: the choice still has to be processed on the server, and the next fetch could be
older than it. Nothing expires it by time, so a choice lost to a full queue stays pending until
the server agrees or the person signs out.

iOS has nothing like Android's notification channels, so the token's `status` stays the
authorization alone.

## What a simulator can and cannot prove

`xcrun simctl push` delivers a payload to a booted simulator, which exercises the alert, the tap,
the open event and the app's routing. It **ignores `mutable-content`**, so it never runs the
extension: the image and the per-message buttons cannot be seen that way. That is why the
extension's decisions are unit tested directly — the category it registers, the attachment it
builds, the receipt it queues — and why the rich path is verified for real with a Firebase project
and an Apple key, on a simulator registered against Apple's sandbox or on a device.

## Left out

- **A notification content extension**, for a custom banner UI.
- **Provisional authorization** and **badge counts maintained by the server**.
- **Live Activities** and **time-sensitive interruption levels**.
- **CocoaPods.** The package is Swift Package Manager only, until an app that needs a podspec asks.
