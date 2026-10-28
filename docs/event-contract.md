# The event contract

What a Funnelbase client sends, and what the backend relies on it for. The Android SDK
([funnelbase-android](https://github.com/Funnelbase/funnelbase-android)), this iOS SDK and the
Flutter plugin over both ([funnelbase-flutter](https://github.com/Funnelbase/funnelbase-flutter))
all implement it, character for character. Where a client does something else, the numbers go
wrong in the ways each section describes.

## The event

`POST /v1/events` takes a batch: `{sdk_name, sdk_version, sent_at, events: [...]}`, authenticated
by the app's ingest key in an `X-Api-Key` header. Each event:

| Field | Sent | Meaning |
|---|---|---|
| `event_id` | always | A UUID made on the device. It is how a replayed delivery is recognised. |
| `event_name` | always | A name declared in the app's event catalog, or a reserved `$` name (below). |
| `occurred_at` | always | Device time, ISO-8601, to the millisecond. |
| `session_id` | always, except a [passive event](#passive-events), which sends `""` | Made on the device; a new one after 30 minutes without an event, and at every reset. |
| `anonymous_id` | always | See [Identity](#identity). Sent signed in or not. |
| `device_id` | always | See [Identity](#identity). |
| `user_id` | while signed in | See [Identity](#identity). |
| `properties` | when there are any | Typed by their JSON type; checked against the catalog. A date is a string — [Dates](#dates). |
| `traits` | on `$identify` | The person's attributes, typed as properties are, dates included. The newest `$identify` replaces the person's traits as a whole. |
| `device` | always | `platform` and the device context (`os_version`, `app_version`, `device_model`, …). `locale` (a language tag, `tr-TR`) and `timezone` (IANA) are read per event, not at startup: they pick a message's language and clock. |

The workspace and the app are not fields: the backend takes them from the ingest key, so a client
can never write into an app it holds no key for. Country, region and city are not fields either:
the backend resolves them from the upload's address and never stores the address itself.

Every event must be declared in the app's catalog in the dashboard before it is sent, with its
properties and their types. An undeclared event, an undeclared property, a missing required
property or a value of the wrong type is refused and kept aside, never silently stored.

### Dates

JSON has no date, so a date travels as ISO-8601 text, a string, in a property or a trait. The
catalog's `date` type is what makes it one: a value declared `date` that does not parse is refused,
as any wrong type is. Two shapes, and nothing else:

| Shape | Example | Meaning |
|---|---|---|
| A calendar day | `"2026-11-03"` | No time, no zone: the day is read in whichever zone asks — a person's own for a campaign's wait, UTC for a segment. A renewal day, a birthday. |
| An exact moment | `"2026-11-03T09:00:00Z"`, `"2026-11-03T12:00:00+03:00"` | A point in time, with `Z` or an offset. |

A date-time without an offset (`"2026-11-03T09:00:00"`) is not a date: nobody can tell which moment
it means. The SDKs take their platform's date types and write the text themselves, character for
character the same:

| Value | Android | iOS | Sent as |
|---|---|---|---|
| A calendar day | `java.time.LocalDate` | `AnalyticsDay(year:month:day:)`, or `AnalyticsDay(date, timeZone:)` | `2026-11-03` |
| A moment | `java.time.Instant`, `java.util.Date` | `Date` | UTC with `Z`, to the millisecond, no fraction when it is whole: `2026-11-03T09:00:00Z`, `2026-11-03T09:00:00.123Z` |

A string is sent as it is, so a caller who already has ISO text may pass it. Anything else that is
not a string, number or boolean is sent as its description, which for a local date-time is a
date-time without an offset, and refused if the property is declared `date`.

## Identity

Three ids, each with one job.

| Id | Made | Changes | Job |
|---|---|---|---|
| `device_id` | on the app's first launch | never — a reinstall makes a new one | One install. |
| `anonymous_id` | on the app's first launch | at every reset: a sign-out, or a different account signing in | One stretch of use between resets. |
| `user_id` | by the app, at sign-in or sign-up | cleared at every reset | The account. |

Three rules follow, and the backend depends on each of them:

1. **The link is the first event that carries both ids.** Normally that is the `$identify` a sign-in
   or sign-up sends. From then on, everything sent under that anonymous id belongs to the account,
   the anonymous stretch before the sign-in included. There is no `alias` call: a separate call
   announcing the link would be a second record of the same fact, and one a client could forget.
2. **An anonymous id belongs to the first account seen with it.** That is why `anonymous_id` restarts
   at every reset. The next person on a shared phone starts with a fresh one, which links to them
   when they sign in, and never to the account that signed out.
3. **A reset also starts a new session.** One visit never spans two people.

After a sign-out, the anonymous stretch on the welcome screen gets a fresh anonymous id. If nobody
signs in again on that device, it stays a person of its own.

## Reserved events

| Event | Sent | Properties |
|---|---|---|
| `$session_start` | In front of the first event of every session, at that event's instant and with its identity. | none |
| `$first_open` | Once per install, in front of its first event (after that session's `$session_start`), at the same instant and with that event's identity. | `installed_at_ms` — number, Unix epoch milliseconds: when the operating system says the app was installed (Android's `PackageInfo.firstInstallTime`). Optional, for a platform that has none. |
| `$screen_view` | A screen was shown. | `screen_name` — string, required. |
| `$identify` | At sign-in and sign-up, and on each launch while signed in. | Its `traits` are the person's attributes. |
| `$push_token` | When the push token is issued or refreshed, at every identify and reset, and when the notification permission changes. Passive. | `token` — string, required. `token_kind` — `fcm`, `apns` or `opaque`, required. `status` — `active`, or `disabled` while the OS permission is off (on Android also while the SDK's own notification channel is switched off), required. |
| `$push_received` | A push reached the device and the SDK rendered it. Passive. | `delivery_id`, `run_id` — strings, required, from the push payload. |
| `$push_opened` | The person tapped a push, or one of its action buttons. | `delivery_id`, `run_id` — strings, required, from the push payload. `action_id` — string, optional: the button tapped, by the id the message gave it, absent when the notification itself was tapped. |
| `$topic_preference` | The person switched one of the app's notification topics on or off. Passive. | `topic` — string, required: the topic's key, which must be one of the app's topics. `subscribed` — boolean, required. |

Every app starts with a built-in catalog definition for each of these, and they are checked
leniently, so automatic tracking never waits on a catalog edit.

### Passive events

`$push_token` and `$push_received` happen with nobody acting: the token is refreshed and the push
arrives while the app is in the background. So they are **passive**: the SDK sends them outside any
session, with `session_id` set to `""`, and they start none. The backend records them against the
device's push registration and the delivery they answer, so they count as no one's activity,
extend no session and appear in no flow. `$topic_preference` is passive for the other half of that
reason: it is a setting, not behaviour, and each topic's choice is kept on its own, so one choice
never erases another.

`$push_opened` is a tap, so it is behaviour like any other event: sent inside a session, counted
as activity, and recorded on the delivery too.

**A button tap is an open.** Tapping "View order" and tapping the notification are the same fact
about the same delivery — the person came back — so both are `$push_opened`, and the button is a
property of it. A separate event would split one funnel in two and make "opened the push" a
question with two answers. A dismissal is reported by neither.

**Why `$first_open` carries the install time.** The day an app adopts the SDK, every existing user
opens it with the SDK for the first time. Without the install time, all of them would count as new
that day. A person is first seen at the earlier of their first event and the install time it
reports, so someone who installed last year is not a new person this week.

**Why it carries its first event's identity.** An app that restores a signed-in user on launch
identifies before its first event. The `$first_open` is then sent signed in, the account's first
sighting moves back to the install too, and an existing account is not counted as a new one on the
day the SDK arrives. An app that signs in later sends it anonymous; the link then carries the
install time to the account.

## Topics

`GET /v1/topics?anonymous_id=…&user_id=…`, with the same `X-Api-Key` header, reads back the app's notification
topics and the person's choice for each, so an app can draw a settings screen without hard-coding
any topic. A `503 topics_unavailable` means the server cannot answer right now; show what you have.

## Older clients

- **No `device_id`:** the event is accepted and stored with an empty device id.
- **`$alias`:** refused with `reserved_name`. The link it meant to make is already made by the
  `$identify` that follows it.
- **A `$first_open` without `installed_at_ms`:** accepted. Its own time is its first sighting.
