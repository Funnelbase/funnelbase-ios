# Changelog

## Unreleased

- A push token registration counts as sent only once an upload carrying its `$push_token` is
  answered with a 2xx. If the upload is refused for good (any 4xx but a 429, such as the backend's
  `403 plan_limit`), the registration is sent again at the next recheck (`setToken`, or
  `refreshToken` at startup, on a language or time zone change, or after asking for permission),
  unless its event is still queued. An install updated from 0.2.0 registers once more after the
  update, which heals a registration lost before.
- A topic choice whose upload is refused for good is no longer released: it stays pending and is
  sent again at the next startup or registration recheck. A choice the server accepted stays
  pending, as before, until a fetch shows the server holding it.
- `TopicPreferenceStore.release(droppedLines:)` is deprecated (it still builds, and now keeps the
  choice to resend) in favour of `requeue(droppedLines:)`, with
  `accept(acceptedLines:)` and `toResend(isQueued:)` beside it; `TopicPreferenceStore.Pending` gains
  `accepted`. `PushTokenStore` gains `eventId`, `isConfirmed`, `confirm(acceptedLines:)`,
  `unconfirm(droppedLines:)` and `needsResend(isQueued:)`; `AnalyticsClient` gains `pushTokens`,
  `registerPushToken`, `forgetPushRegistration` and `resendPendingTopicChoices`; `EventQueue` gains
  `contains(eventId:)`. Nothing on the wire changed.

## 0.2.0

The first public release, as the `Funnelbase` Swift package.

- Events with typed properties, automatic sessions, screen views, `$first_open` with the install
  time, identity by `identify` / `reset` (no alias call), and an offline queue.
- Dates: `Date` as a moment in UTC, `AnalyticsDay` as a calendar day.
- Push: `Analytics.push` (APNs, Firebase or opaque tokens; the permission as the token's status),
  and `AnalyticsNotificationService` in `FunnelbaseNotificationService` for the receipt, per-message
  buttons, threads and images. A reinstall registers its token again.
- The device's language and time zone on every event, re-registering the push token when either
  changes.
- Notification topics: `Analytics.topics.set` and `fetch`.
