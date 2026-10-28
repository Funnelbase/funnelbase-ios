# Push

How a Funnelbase push reaches an Apple device and what the SDK does with it. The SDK depends on no
push library: whoever holds a token hands it over, so an app on APNs directly, on Firebase, or on a
gateway of its own all work the same way. The flow on the device, step by step, is in
[sdk-ios.md](sdk-ios.md#push-end-to-end-on-an-apple-device).

## Tokens

| Call | Kind sent | When |
|---|---|---|
| `Analytics.push.setAPNSToken(deviceToken)` | `apns` | The app talks to Apple directly: pass the `Data` from `didRegisterForRemoteNotificationsWithDeviceToken` as it is. |
| `Analytics.push.setToken(token, kind: TokenKinds.fcm)` | `fcm` | The app is on Firebase Cloud Messaging: pass the FCM registration token. |
| `Analytics.push.setToken(token, kind: TokenKinds.opaque)` | `opaque` | The app's own gateway, or a test token typed by hand. |

Each sends a passive `$push_token` ([event-contract.md](event-contract.md#passive-events)) with
the notification permission as its `status`, and only when the token, its kind or its status
changed. `refreshToken()` re-reads the permission after the app has asked for it.

## The payload

On Apple devices the push's data keys arrive as top-level keys of the payload, beside `aps`
(which is also what Firebase does with a data block), so an app on either transport is read the
same way:

| Key | Meaning |
|---|---|
| `delivery_id`, `run_id` | Which delivery and which send this is. A push without both is not Funnelbase's, and the SDK leaves it alone. |
| `title`, `body` | The text. `aps.alert` carries it for Apple to draw; these are the fallback. |
| `image_url` | An image the extension downloads and attaches. |
| `deep_link` | Where a tap leads. Handed back to the app, which routes it. |
| `collapse_key` | Becomes the notification's thread, so later pushes group with earlier ones. |
| `buttons` | A JSON list of `{id, title, deep_link?}`, up to four. A tap on one reports `$push_opened` with `action_id` = its `id`. |
| `aps.category` | The category the buttons are registered under, derived from the buttons themselves. |

Every other key is the message's own and is handed to the app in `PushPayload.data`.

## Rendering

Funnelbase sends an iOS push as an alert with `mutable-content: 1`, which makes Apple run the app's
notification service extension before the banner shows. A subclass of
`AnalyticsNotificationService` (product `FunnelbaseNotificationService`) is the whole extension: it
records `$push_received`, registers the buttons' category, sets the thread and attaches the image.
A message may instead ask to be rendered by the system (`render: system`): Apple shows it as sent,
a tap still reports `$push_opened`, but there is no receipt, no image and no per-message buttons.

## The tap

```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
) {
    defer { completionHandler() }
    guard let payload = Analytics.push.handle(response: response),
          response.actionIdentifier != UNNotificationDismissActionIdentifier
    else { return }

    let actionId = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        ? nil
        : response.actionIdentifier
    router.open(payload.link(forActionId: actionId))
}
```

`handle(response:)` reports `$push_opened` (with the button's `action_id` when a button was
tapped, and nothing for a dismissal) and returns the payload, or `nil` for a notification that is
not Funnelbase's. Navigation is the app's: only the app knows its own screens.

## Trying push without a provider

The demo app's Notifications screen has simulate buttons that post a local notification carrying
the same keys a real push arrives with, so the text, the buttons, the tap and the routing can all be
seen on a simulator with no APNs key at all. What a local notification cannot do is run the
extension, so the image and the `$push_received` receipt need a real push.

`xcrun simctl push booted <bundle id> payload.apns` delivers a real payload to a booted simulator,
but it **ignores `mutable-content`**, so the extension does not run there either. The rich path is
verified with a real push: APNs directly, or a Firebase project with the app's Apple key uploaded,
on a simulator registered with Apple's sandbox or on a device.

The demo's sample image is fetched from `http://localhost:9099/media/sample.png`: any local HTTP
server on that port serving a PNG at that path will do. The extension's `allowInsecureImages`
override is what lets it load over plain http, and belongs in a debug build only.
