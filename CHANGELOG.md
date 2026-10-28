# Changelog

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
