# The demo app

`demo-ios` is a SwiftUI trading app that uses the SDK the way a customer's app would. It is the
iOS twin of the [Android demo](https://github.com/Funnelbase/funnelbase-android), screen for screen:
the same four tabs, the same dark violet theme, the same number formatting and the same taxonomy,
so both platforms can be read as one product in the dashboard.

## Configuration

The app needs an ingest key. In the Funnelbase dashboard:

1. **Manage → Apps → New app.** Any name.
2. Enable the **iOS** platform and generate its key. The plaintext is shown **once**.
3. Copy `demo-ios/Config.example.xcconfig` to `demo-ios/Config.xcconfig` (gitignored) and fill in
   `ANALYTICS_API_KEY`, and `ANALYTICS_ENDPOINT` if your ingestion endpoint is not
   `http://localhost:8080`.

`Build.xcconfig` includes `Config.xcconfig` only when it is there, so a fresh clone builds as it
is. **With no key configured the app runs normally and initialises no SDK**: it logs one line and
carries on. A demo that crashes on a fresh clone is worse than one that quietly collects nothing.

## Running it

```bash
open demo-ios/TradeDemo.xcodeproj
# or, from the command line, for the simulator:
xcodebuild -project demo-ios/TradeDemo.xcodeproj -scheme TradeDemo \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The project depends on the SDK at the repository root by path, so an edit to the SDK is picked up
by the next build. It is generated with [xcodegen](https://github.com/yonaskolb/XcodeGen) from the
committed `project.yml`; the generated `.xcodeproj` is committed too, so you do not need xcodegen
to build. After changing `project.yml`, run `xcodegen generate` in `demo-ios/`.

A device build needs your own developer team: the app group and `aps-environment` are entitlements.
A simulator build needs neither.

## What it sends

**`$screen_view`, and one custom event.** Screen views carry `screen_name` and nothing else — they
say where the user is. What the user is looking at is a custom event: the instrument page sends
`instrument_viewed` with the ticker in `symbol`. `Analytics/Events.swift` lists the custom events,
as `Analytics/Screens.swift` lists the screens.

The reserved events need no catalog entry: every app has built-in definitions for them. The custom
event does. Declare it in the dashboard's event catalog before running the demo against a fresh
app, or every one of them is refused with `unknown_event`:

| Event | Properties | Fires |
|---|---|---|
| `instrument_viewed` | `symbol` — string, required | when an instrument's detail page is shown |

| Screen | `screen_name` |
|---|---|
| Welcome | `welcome` |
| Sign in | `sign_in` |
| Sign-up intro, pages 1–3 | `signup_intro_1`, `signup_intro_2`, `signup_intro_3` |
| Sign-up username step | `signup_username` |
| The four tabs | `dashboard`, `markets`, `orders`, `news` |
| Instrument detail | `instrument_detail` |
| Notifications, from the dashboard's bell | `push_settings` |
| Notification topics, from the Notifications screen | `notification_settings` |

Screen names are kept apart from the navigation's own identifiers on purpose: routes are addresses,
screen names are a dashboard dimension, and sharing one string means a navigation refactor silently
renames a chart's series. The Orders chips (Pending / Cancelled / Filled) filter within a screen and
emit nothing.

The app also sends the push events the SDK owns — `$push_token`, `$push_received` and
`$push_opened` — and `$topic_preference` from its topics screen, none of which need declaring.

## Identity

There is no auth backend — any username and any password sign you in. The username is not
throwaway though: `Identity/UserId.swift` hashes it into the `user_id` every later event carries:
the first 64 bits of the SHA-256 of the trimmed, lowercased name, as `u_` and 16 hex characters.
Same name, same id, on every launch and every device, and the same id the Android demo derives —
pinned by a test on both — because one person has to be one person across both platforms.

The demo follows the [event contract](event-contract.md#identity), and `AppState` is the one place
it touches identity:

- **Sign-in** → `identify`, with the traits `username` and `plan`. The sign-in screen's **Pro plan**
  switch says which plan the account is on, and a pro sign-in also sends `plan_renews_on`, an
  `AnalyticsDay` 30 days ahead.
- **Sign-up** → the same `identify`, and nothing before it. That one event is the link: the welcome
  and intro screens viewed before the account existed become the account's.
- **Sign-in as a different account** → the SDK resets first, on its own.
- **Sign-out** → `reset`: a new anonymous id and a new session.
- **Every launch while signed in** → `identify` again, so it is the launch's first event.

Declare `username`, `plan` and `plan_renews_on` (type `date`) on the built-in `$identify` in the
catalog to see them as traits in the dashboard.

## Push

The dashboard tab's bell opens a Notifications screen, which shows the parts of push that usually
need a provider: whether notifications are allowed, which token this install registered, a way to
register a token of your own as kind `opaque`, and simulate buttons that post the same payload a
real push carries ([push.md](push.md#trying-push-without-a-provider)). A "Choose topics" card opens
the topics screen: the app's topics as `Analytics.topics.fetch()` reads them, none hard-coded, with
a switch each calling `Analytics.topics.set`.

**No Firebase.** The demo registers the APNs device token exactly as Apple hands it over. An app on
Firebase registers the token Firebase gives it instead, with the same one-line call.

A tap is routed by `Push/PushRouting.swift`: `trade://instrument/AAPL` and the four tab links are
understood, and anything else leaves the app where it is, because a campaign is written long after
a build ships.

## The data

Fifty S&P 500 constituents, priced randomly at every launch within a per-ticker band, generated once
and shared by every screen so AAPL has one price whichever tab you are on. Money is formatted
`en-US`/USD throughout, and colour never carries meaning alone: every green or red move is paired
with a ▲ or ▼.

## Tests

The `TradeDemoTests` target: the user id derivation, money formatting, market data and push routing.

```bash
xcodebuild -project demo-ios/TradeDemo.xcodeproj -scheme TradeDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test
```
