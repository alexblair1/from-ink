# EDD — Dates, Calendars, and Timezones

| Field | Value |
|---|---|
| Status | Proposed |
| Owner | Solo |
| Last updated | 2026-05-13 |
| Implements ticket | F-13 (CalendarContext dependency + migration) |
| Companion docs | EDD — Data Model · EDD — Data Layer · EDD — Bootstrap |

---

## Table of contents

1. [Summary](#1-summary)
2. [Goals & non-goals](#2-goals--non-goals)
3. [Core invariants](#3-core-invariants)
4. [The three layers](#4-the-three-layers)
5. [CalendarContext — the dependency](#5-calendarcontext--the-dependency)
6. [Day-key semantics](#6-day-key-semantics)
7. [SwiftData + CloudKit](#7-swiftdata--cloudkit)
8. [Predicate patterns](#8-predicate-patterns)
9. [Date arithmetic and DST](#9-date-arithmetic-and-dst)
10. [Handwriting, OCR, and Foundation Models](#10-handwriting-ocr-and-foundation-models)
11. [EventKit and WeatherKit interop](#11-eventkit-and-weatherkit-interop)
12. [Testing strategy](#12-testing-strategy)
13. [Migration plan](#13-migration-plan)
14. [Anti-patterns](#14-anti-patterns)
15. [Open questions](#15-open-questions)
16. [Decision log](#16-decision-log)

---

## 1. Summary

Every date in From Ink resolves through a single TCA dependency — `CalendarContext`. The dependency owns "now", the user's calendar/timezone/locale, and the day-key formatter used for cache keys and predicates. No call site reads `Date()` directly. No call site allocates `DateFormatter` ad-hoc.

The goal is to make it **impossible** to write the next locale or DST bug. There is one place to be correct, and every other call site borrows correctness from it.

Storage is always absolute (`Date`). Cache keys are always Gregorian/POSIX-formatted strings computed in the user's timezone. Display is always `Date.formatted(.dateTime...)` so the system handles locale and calendar.

---

## 2. Goals & non-goals

### Goals

- Eliminate every direct `Date()` call outside `CalendarContext.liveValue`.
- Eliminate every `DateFormatter` instantiation outside `CalendarContext.liveValue` and one ISO-8601 parser for FM output.
- Make "is this today?", "what's today's cache key?", and "when does this Date fall in the user's day?" trivial one-liners.
- Make every reducer that uses dates testable with deterministic time travel.
- Make day-key strings stable across devices in the same timezone, regardless of preferred calendar (Buddhist, Japanese era, Hebrew, etc.).
- Make day-key strings *correctly differ* across devices in different timezones — a user in Tokyo and a user in NYC at the same UTC moment can be on different "today"s, and our cache must reflect that.

### Non-goals

- This EDD does not specify the SwiftData schema — see the data model EDD for which fields are `Date` vs `String`.
- This EDD does not cover server-side time anywhere — From Ink has no first-party backend. CloudKit's clock is treated as the device clock.
- This EDD does not solve repeating-event timezone handoffs (DST-crossing recurring meetings). That's an EventKit concern; we display whatever EventKit hands us.
- This EDD does not specify localized number/currency formatting — unrelated.

---

## 3. Core invariants

Five rules. If a line of date code doesn't satisfy all five, it's wrong.

1. **`Date` is the only persisted form for moments.** Never store `DateComponents`, never store a date as a `String` *unless* the string is a derived day-key whose source `Date` is also stored. CloudKit syncs `Date` losslessly.
2. **"Now" is a dependency.** Every "what time is it" call routes through `@Dependency(\.calendarContext).now()` — never `Date()`. This enables deterministic tests and the time-warp feature.
3. **User calendar, timezone, and locale are dependencies too.** Same reason — testability — plus the cache-key code must lock to Gregorian/POSIX regardless of user preference.
4. **Day-keys live in one helper.** `CalendarContext.dayKey(_:)` is the single producer of `"yyyy-MM-dd"` strings used in predicates and identifiers. No `DateFormatter` is allocated outside that helper (with one exception — §10, ISO-8601 parsing of FM output).
5. **Date arithmetic goes through `Calendar`.** `+ 86400` is a DST bug; `+ 60 * 60 * 24 * 7` is a weekly DST bug. Use `userCalendar.date(byAdding: .day, value: 1, to: x)`.

---

## 4. The three layers

Every date in the app sits in exactly one of three layers, and each layer has a single correct form:

| Layer | Form | Tool | Example |
|---|---|---|---|
| **Storage** | `Date` (absolute, no TZ) | SwiftData `@Model var x: Date` | `DailyBriefRecord.generatedAt` |
| **Cache key / predicate** | `"yyyy-MM-dd"` Gregorian + POSIX, in user's TZ | `CalendarContext.dayKey(_:)` | `DailyBriefRecord.dayKey` |
| **Display** | locale-aware projection | `Date.formatted(.dateTime...)` | `Date().formatted(.dateTime.hour().minute())` |

The lifecycle of a typical date:

```
EventKit hands us a Date (absolute) ──► stored as Date in SwiftData
                                  │
                                  ├──► dayKey(_:) computes "2026-05-13" for predicate match
                                  │
                                  └──► .formatted(.dateTime...) for UI rendering
```

The same `Date` flows through all three layers untransformed in storage. The other two forms are *derived projections* — never the source of truth, never persisted independently.

### Why three forms and not two?

You could imagine collapsing cache keys into display: just use `date.formatted(.iso8601.year().month().day())` everywhere. Two reasons not to:

1. The default `Date.ISO8601FormatStyle` uses GMT by default — wrong for user-local "today" semantics. Configuring it correctly is itself a five-parameter call you'd have to repeat.
2. `#Predicate` cannot call methods on the formatted output at query time; it can only compare stored values. So the cache-key string has to be *stored*, not computed at query time. That makes it a real data-layer concept, not a view-layer one.

---

## 5. CalendarContext — the dependency

### 5.1 Relationship to TCA's `@Dependency(\.date)` and `@Dependency(\.calendar)`

TCA ships `@Dependency(\.date)` (a `DateGenerator`) and infers `@Dependency(\.calendar)`. They are well-tested and idiomatic; we do **not** replace them. `CalendarContext` **composes** them and adds the facets they don't cover:

- The built-ins expose `now` and the user's `Calendar` — but not the user's `TimeZone` or `Locale` as first-class accessors, and not the day-key helper.
- The day-key helper must be a single function (one place to be correct) and must lock formatting to Gregorian + POSIX while floating the timezone. That doesn't belong on `\.date` or `\.calendar`.
- We want all date facets in one value so a reducer reads `@Dependency(\.calendarContext) var cal` once, not three separate dependency declarations.

Concretely, `CalendarContext.liveValue` reads its `now` and `userCalendar` from the TCA built-ins (§5.3), so `withDependencies { $0.date.now = { ... } }` still propagates correctly to anyone using the built-ins directly and to `CalendarContext` consumers.

### 5.2 Surface

```swift
import ComposableArchitecture
import Foundation

/// Single source of truth for date/time/calendar/timezone in the app.
///
/// All "what time is it" and "what day is this" calls route through here.
/// No call site reads `Date()` directly. No call site allocates DateFormatter.
///
struct CalendarContext: Sendable {
    /// The absolute current moment. The only producer of "now" in the app.
    var now: @Sendable () -> Date

    /// The user's preferred calendar (Gregorian, Buddhist, Japanese, …).
    /// Used for display and for "is this today" comparisons.
    var userCalendar: @Sendable () -> Calendar

    /// The user's current timezone.
    var userTimeZone: @Sendable () -> TimeZone

    /// The user's preferred locale for display formatting.
    var userLocale: @Sendable () -> Locale

    /// Stable day-key for cache keys and predicates.
    /// Always "yyyy-MM-dd", Gregorian, POSIX, in the user's timezone.
    /// Identical bytes for the same user-local day, regardless of user's
    /// preferred calendar.
    var dayKey: @Sendable (Date) -> String

    /// Start of the user's current local day (as an absolute Date).
    var startOfDay: @Sendable (Date) -> Date

    /// True if two Dates fall on the same user-local day.
    var isSameDay: @Sendable (Date, Date) -> Bool

    /// True if a Date falls on the user's current local day.
    var isToday: @Sendable (Date) -> Bool

    /// Add a calendar component to a Date — DST-safe.
    /// Traps via `preconditionFailure` if the underlying
    /// `Calendar.date(byAdding:value:to:)` returns nil — this only
    /// happens for non-standard components on non-Gregorian calendars
    /// and indicates a programmer error, not a runtime condition.
    var add: @Sendable (Calendar.Component, Int, Date) -> Date

    /// Parse a machine-readable date string (e.g. Foundation Models output).
    /// Expects ISO-8601 full-date form ("yyyy-MM-dd"). Returns nil on
    /// any other shape — the caller decides what to do with nil.
    var parseISO8601Date: @Sendable (String) -> Date?
}

extension DependencyValues {
    var calendarContext: CalendarContext {
        get { self[CalendarContext.self] }
        set { self[CalendarContext.self] = newValue }
    }
}
```

`parseISO8601Date` lives on `CalendarContext` rather than as a sibling dependency. ISO-8601 parsing is conceptually "machine-readable date input," symmetric with `dayKey`'s "machine-readable date output." Keeping them co-located prevents drift between the two.

### 5.3 liveValue

`liveValue` composes TCA's `\.date` and `\.calendar` built-ins so that overrides to those primitives propagate here automatically.

```swift
extension CalendarContext: DependencyKey {
    static var liveValue: CalendarContext {
        @Dependency(\.date) var date          // TCA's DateGenerator
        @Dependency(\.calendar) var calendar  // TCA's user Calendar

        return CalendarContext(
            now: { date.now },
            userCalendar: { calendar },
            userTimeZone: { .autoupdatingCurrent },
            userLocale: { .autoupdatingCurrent },
            dayKey: { d in
                var greg = Calendar(identifier: .gregorian)
                greg.timeZone = .autoupdatingCurrent
                let c = greg.dateComponents([.year, .month, .day], from: d)
                guard let y = c.year, let m = c.month, let day = c.day else {
                    preconditionFailure(
                        "dateComponents([.year,.month,.day]) returned partial result"
                    )
                }
                return String(format: "%04d-%02d-%02d", y, m, day)
            },
            startOfDay: { d in calendar.startOfDay(for: d) },
            isSameDay: { a, b in calendar.isDate(a, inSameDayAs: b) },
            isToday: { d in calendar.isDateInToday(d) },
            add: { component, value, d in
                guard let result = calendar.date(byAdding: component, value: value, to: d) else {
                    preconditionFailure(
                        "Calendar.date(byAdding: \(component), value: \(value)) returned nil. " +
                        "This indicates an unsupported component for the current calendar."
                    )
                }
                return result
            },
            parseISO8601Date: { string in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                formatter.timeZone = .autoupdatingCurrent
                return formatter.date(from: string)
            }
        )
    }
}
```

### 5.4 testValue and `.fixed(...)` factory

The default `testValue` must be **deterministic but real** — it uses actual `Calendar` and `TimeZone` operations against a frozen clock, so derived helpers like `add(.day, 1, x)` actually advance by one day and `isSameDay` actually compares.

```swift
extension CalendarContext {
    /// Build a fixed-clock context for tests. All helpers use real Calendar
    /// operations against the frozen `now`. Substitute via `withDependencies`.
    static func fixed(
        now: Date,
        timeZone: TimeZone = TimeZone(identifier: "America/New_York")!,
        calendar baseCalendar: Calendar = Calendar(identifier: .gregorian),
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> CalendarContext {
        var cal = baseCalendar
        cal.timeZone = timeZone
        cal.locale = locale

        return CalendarContext(
            now: { now },
            userCalendar: { cal },
            userTimeZone: { timeZone },
            userLocale: { locale },
            dayKey: { d in
                var greg = Calendar(identifier: .gregorian)
                greg.timeZone = timeZone
                let c = greg.dateComponents([.year, .month, .day], from: d)
                guard let y = c.year, let m = c.month, let day = c.day else {
                    preconditionFailure("partial date components")
                }
                return String(format: "%04d-%02d-%02d", y, m, day)
            },
            startOfDay: { d in cal.startOfDay(for: d) },
            isSameDay: { a, b in cal.isDate(a, inSameDayAs: b) },
            isToday: { d in cal.isDate(d, inSameDayAs: now) },
            add: { component, value, d in
                guard let result = cal.date(byAdding: component, value: value, to: d) else {
                    preconditionFailure("calendar add nil")
                }
                return result
            },
            parseISO8601Date: { string in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                formatter.timeZone = timeZone
                return formatter.date(from: string)
            }
        )
    }

    /// Default test context — 2026-05-13 00:00 UTC, America/New_York,
    /// Gregorian, en_US_POSIX. Override via `withDependencies` for boundary cases.
    static let testValue = CalendarContext.fixed(
        now: Date(timeIntervalSince1970: 1_778_630_400)  // 2026-05-13 00:00 UTC
    )
}
```

Tests that need a different clock build their own via `.fixed(now:)`. Tests that need to exercise locale or DST boundaries pass `timeZone` or `calendar` accordingly. The degenerate `{ _ in true }` stubs from the previous draft are gone — they masked bugs by always succeeding.

### 5.5 Construction and lifetime

`CalendarContext` is wired in `AppDependencyContainer` (per the bootstrap EDD §5). It has no construction-time dependencies and is one of the foundational lazies — every other dependency that takes a `Date` parameter receives it from `CalendarContext` rather than calling `Date()` itself.

### 5.6 `.autoupdatingCurrent` semantics

`liveValue` uses `Calendar.autoupdatingCurrent`, `TimeZone.autoupdatingCurrent`, and `Locale.autoupdatingCurrent`. These read through to the user's current preference at every property access, so the app stays in sync with mid-session preference changes (a user changing system timezone while the app is in the background, for instance).

Consequence for tests and capture: do **not** capture-and-hold values returned by `cal.userCalendar()` / `cal.userTimeZone()` across long-lived closures. Re-call the dependency at the point of use. In production this almost never matters because reducers are short-lived; the gotcha shows up in long-running `.run { send in ... }` effects.

If a feature genuinely needs a frozen snapshot of preferences (e.g. "render the brief in the timezone it was generated in"), capture into a `Sendable` local value and document the intent.

### 5.7 Rules of use

- **Inside reducers and dependency clients:** `@Dependency(\.calendarContext) var cal` at the top of `Reduce { state, action in ... }` or inside each `.run { send in ... }` block; then `cal.now()`, `cal.dayKey(...)`, `cal.isToday(...)`.
- **Inside feature views and component views:** **don't.** These tiers render `Date` values into strings via `Date.formatted(.dateTime...)` against the system's resolution. Any day-comparison logic comes through the `Model` from the wiring view's adapter.
- **Inside wiring views:** allowed, in the adapter that builds the `Model` from the `Store`. The wiring layer is the boundary where reducer-resolved state crosses into pixel-rendering territory.
- **Inside other `liveValue` closures:** allowed, but prefer passing resolved values in at construction time so the closure stays pure and synchronous.

---

## 6. Day-key semantics

A day-key is a `String` of the form `"yyyy-MM-dd"`. It exists to make predicates and dedup trivial. The format choice is deliberate and has consequences.

### 6.1 What it must do

- **Identical for the same user-local day on the same device.** Cache hits work.
- **Identical across devices in the same timezone.** CloudKit sync works.
- **Different for the same UTC moment when two devices are in different timezones.** A user in Tokyo and a user in Honolulu can simultaneously be on different "today"s; their cached briefs must not collide.
- **Independent of the user's preferred calendar.** A user who sets their device to Buddhist calendar still has a "2026-05-13" day-key, not "2569-05-13".

### 6.2 How it works

```swift
dayKey: { date in
    var greg = Calendar(identifier: .gregorian)  // calendar locked
    greg.timeZone = .autoupdatingCurrent          // TZ floats with user
    let c = greg.dateComponents([.year, .month, .day], from: date)
    guard let y = c.year, let m = c.month, let d = c.day else {
        preconditionFailure(
            "dateComponents([.year,.month,.day]) returned partial result"
        )
    }
    return String(format: "%04d-%02d-%02d", y, m, d)
}
```

Two locks (Gregorian) and one float (timezone) yield the four properties above. `String(format:)` avoids `DateFormatter` allocation entirely — day-keys are produced in hot paths (predicates, cache lookups) and shouldn't pay for formatter setup. The `preconditionFailure` is unreachable in practice (we asked for those three components and `Calendar` always returns them), but satisfies the project's no-force-unwrap rule and makes the assumption explicit.

### 6.3 Why not UTC

Computing the day-key from UTC alone — e.g. `formatter.timeZone = .gmt` — produces wrong results for users near the date line. A Honolulu user at 11pm local on May 13 is at 09:00 UTC on May 14. A UTC-anchored day-key calls that "May 14", but the user's lived "today" is still May 13. The brief they wrote, the events they're looking at, the reminders they're processing — all framed by their local day.

### 6.4 Why not user calendar

Computing in the user's preferred calendar — e.g. Buddhist — produces day-keys like `"2569-05-13"`. These don't collide with Gregorian keys on the same device, but they don't sync semantically: a Gregorian-device user and a Buddhist-device user in the same timezone are on the same day but get different keys. They should hit the same cache entry on shared records.

### 6.5 Format stability

`"yyyy-MM-dd"` is also the shape of an ISO-8601 date. We don't claim full ISO-8601 conformance (no `T`, no time-of-day) — we just borrow the prefix. This makes day-keys human-readable in CloudKit Dashboard and Console logs.

---

## 7. SwiftData + CloudKit

### 7.1 Date is a first-class CloudKit type

`CKRecord` supports `Date` as a built-in value type, stored internally as a `Double` (timeIntervalSinceReferenceDate). SwiftData + CloudKit bridges `@Model var x: Date` to a CloudKit `Date` field with no custom transformer.

### 7.2 The CloudKit defaults rule applies

Per the data model EDD, every `@Model` property must have a default or be optional. Two valid patterns for `Date`:

```swift
var generatedAt: Date = Date()   // captures "now" at init
var lastOpenedAt: Date? = nil    // optional; nil = never
```

Pick by semantics:

- "When was this created/generated/last touched" → non-optional with `Date()` default.
- "When was this last opened/read/dismissed" → optional, `nil` means "never".

### 7.3 No `@Attribute(.unique)` on Date

Same rule as every other property. CloudKit doesn't support unique constraints.

### 7.4 Day-key stored alongside Date

When a record is uniquely identified by user-local day (one row per day), store both:

```swift
@Model final class DailyBriefRecord {
    var id: UUID = UUID()
    var generatedAt: Date = Date()
    var dayKey: String = ""   // produced by CalendarContext.dayKey(_:)
    // ...
}
```

The `Date` is the source of truth. The `dayKey` is a derived predicate-friendly index. Both sync.

**Frozen-at-write semantics.** The `dayKey` is set once at insertion and never recomputed. It represents the user-local day at the moment of creation. Consequence: a user who creates a brief at 11pm Pacific on May 13, then opens the app in Tokyo on May 14 local, sees *no brief for today* and the client regenerates one. The original May 13 record becomes a "past day" entry visible only through time-warp / history UI.

This is a deliberate product choice. The alternative — recompute `dayKey` on read against current TZ — would make "yesterday's brief" follow the user around the date line, which loses the journal-like semantics of `DailyBriefRecord`. See §15 for the open question on whether this changes for non-bucketed records.

### 7.5 No timezone on Date

`Date` has no timezone — it's an absolute moment. If a record needs to remember the timezone *in which it was created* (rare — only for "this meeting was scheduled in PT" UX), store the IANA identifier:

```swift
var sourceTimeZoneID: String? = nil   // e.g. "America/Los_Angeles"
```

Most records don't need this. EventKit events carry their own timezone metadata via `EKEvent.timeZone`; we don't duplicate it.

### 7.6 Don't equality-compare synced `Date` values

`Date` is internally `Double` (timeIntervalSinceReferenceDate), and CloudKit's wire format is `Double`-based. Whether the round trip actually loses precision in current SwiftData + CloudKit implementations is undocumented and may vary by platform version; treat it as if it might.

**Rule:** never `==`-compare two `Date` values that have both passed through CloudKit. Use `cal.isSameDay(a, b)`, range predicates, or `abs(a.timeIntervalSince(b)) < tolerance`. From Ink doesn't currently do equality comparison on synced `Date` fields, so this is a forward-looking guard rather than a known regression.

If a feature emerges that requires exact equality (e.g. event deduplication by timestamp), capture a test that round-trips a `Date` through SwiftData + CloudKit to verify behavior under the current OS, and tighten or relax the rule accordingly.

---

## 8. Predicate patterns

SwiftData `#Predicate` macros cannot call `Calendar` methods. This does **not** compile:

```swift
#Predicate<DailyBriefRecord> {
    Calendar.current.isDateInToday($0.generatedAt)
}
// ❌ Calendar methods are not predicate-expressible
```

Two correct patterns:

### 8.1 Range predicate on Date

When you have only a `Date` and want "today":

```swift
@Dependency(\.calendarContext) var cal
let start = cal.startOfDay(cal.now())
let end = cal.add(.day, 1, start)
let descriptor = FetchDescriptor<NotePage>(
    predicate: #Predicate { $0.modifiedAt >= start && $0.modifiedAt < end }
)
```

Two captured `Date` constants; the predicate is trivially expressible.

### 8.2 Equality predicate on dayKey

When the record carries a `dayKey: String`:

```swift
@Dependency(\.calendarContext) var cal
let today = cal.dayKey(cal.now())
let descriptor = FetchDescriptor<DailyBriefRecord>(
    predicate: #Predicate { $0.dayKey == today }
)
```

### 8.3 When to use which

The deciding factor is **model identity**, not query frequency:

- **Use `dayKey` equality** when the model's identity is per-day — one row per user-local day is a hard invariant. Examples: `DailyBriefRecord`, a future `DailyWeatherForecast`, a daily streak counter. These records *are* their day; the day-key belongs on the record because it's part of identity, not just an index.
- **Use range predicates on `Date`** when the model has its own identity and "by day" is just one of many ways you query it. Examples: `NotePage` (identified by UUID; querying "notes touched today" is one of many queries), `NoteHistoryEntry` (identified by UUID + timestamp), `Highlight` (identified by source event).

Both fields together are valid only when the day-key is genuinely part of identity. Adding `dayKey` to a UUID-identified record purely for query convenience is a smell — the predicate-range pattern is already ergonomic and avoids the dual-write coordination cost (anti-pattern in §14).

---

## 9. Date arithmetic and DST

The rule depends on what you're offsetting by.

### 9.1 Day-shaped units — always through Calendar

Adding days, weeks, months, or years must go through `Calendar.date(byAdding:value:to:)` (exposed as `cal.add`). On DST boundaries, "1 day" is sometimes 23 hours and sometimes 25 hours, and only `Calendar` knows.

```swift
// ❌ Wrong — silently 1 hour off on DST boundaries
let tomorrow = today.addingTimeInterval(86_400)
let nextWeek = today.addingTimeInterval(7 * 86_400)

// ✅ Right
@Dependency(\.calendarContext) var cal
let tomorrow = cal.add(.day, 1, today)
let nextWeek = cal.add(.weekOfYear, 1, today)
```

The downstream consequence of a wrong `addingTimeInterval` here is subtle: the resulting `Date` is one hour off the user's intended moment, which breaks every "is today" comparison on the DST boundary day.

### 9.2 Sub-day precision — `addingTimeInterval` is correct

Adding seconds, minutes, or hours where the goal is **exactly N seconds**, with no calendar semantics, should use `addingTimeInterval`:

```swift
// ✅ Right — a 5-second cooldown should be exactly 5 seconds,
//    not "5 seconds with DST adjustment"
let unlockAt = lockedAt.addingTimeInterval(5)

// ✅ Right — token expires 1 hour from issuance, period
let expiresAt = issuedAt.addingTimeInterval(3600)
```

For these cases, the calendar would not adjust anyway (it has no concept of "DST-adjusted seconds"), and `addingTimeInterval` is the clearer, faster expression.

### 9.3 Midnight rollover

For "regenerate at the user's local midnight" effects:

```swift
let nextMidnight = cal.add(.day, 1, cal.startOfDay(cal.now()))
let secondsUntilMidnight = nextMidnight.timeIntervalSince(cal.now())
```

The `timeIntervalSince` math is fine — it produces an absolute `TimeInterval` between two `Date` values whose DST handling is already baked in by `cal.add` and `cal.startOfDay`.

---

## 10. Handwriting, OCR, and Foundation Models

The OCR pipeline produces text. Foundation Models extracts structured task data from that text. When a deadline is involved, two layers must agree on what "Friday" means.

### 10.1 Prompt the model in user-local terms

When constructing the FM prompt for task extraction, include the user's "today" in their locale:

```swift
@Dependency(\.calendarContext) var cal
let today = cal.now().formatted(
    .dateTime.weekday(.wide).month(.wide).day().year()
        .locale(cal.userLocale())
)
let prompt = "Today is \(today). Extract tasks from: ..."
```

This is the **one place** display-style formatting (`Date.formatted(.dateTime...)`) appears outside a view. The model reasons about dates the way the user thinks about them.

### 10.2 Constraining the model's output — two options

`@Generable` schemas constrain types but **not string formats**. A `@Generable struct { let deadline: String? }` lets the model write `"Friday"`, `"2026/05/13"`, `"May 13"`, or `"2026-05-13"` — only the prompt nudges it toward ISO-8601, and at temperature 0 the model is *likely* to comply but not guaranteed.

There are two structural choices, and From Ink picks the second:

**Option A — schema-enforced enum (preferred when expressible):**

```swift
@Generable enum ExtractedDeadline {
    case absolute(year: Int, month: Int, day: Int)
    case relative(RelativeDay)
    case none

    @Generable enum RelativeDay {
        case today, tomorrow, thisFriday, nextFriday, endOfWeek, endOfMonth
    }
}
```

The schema does the work — there is no string-parsing failure mode because there is no string. The downside: enumerating relative-day cases is brittle; the next user-handwritten phrase ("after the long weekend") doesn't fit.

**Option B — string + structured parser (the default for From Ink):**

```swift
@Generable struct ExtractedTask {
    let title: String
    /// ISO-8601 date "yyyy-MM-dd" in the user's local timezone, or nil.
    let deadline: String?
}
```

Prompt: *"deadline must be in the format YYYY-MM-DD or null. Resolve relative dates (Friday, next week) against today's date provided above."* Combined with temperature 0 and greedy decoding, FM output is stable in practice. The parser must still gracefully handle drift — that's §10.3.

We pick option B because relative-day variety from handwritten notes exceeds what an enum can usefully enumerate, and option A's brittleness hurts more than option B's parser cost.

### 10.3 Parse the model's output via `CalendarContext`

ISO-8601 parsing is exposed on `CalendarContext` as `parseISO8601Date(_:)` (see §5.2). Conceptually it is "machine-readable date input" — symmetric with `dayKey`'s "machine-readable date output." Keeping them co-located prevents drift between the two.

```swift
@Dependency(\.calendarContext) var cal

guard let deadlineString = extracted.deadline,
      let deadline = cal.parseISO8601Date(deadlineString)
else {
    // Drop the deadline, log once for telemetry, continue with the task.
    log.warning("FM produced invalid deadline string: \(extracted.deadline ?? "nil")")
    return ExtractedTaskState(title: extracted.title, deadline: nil)
}
```

The parsed `Date` is then stored in SwiftData as a `Date` (per §3). The original string is not stored — only the resolved absolute moment.

**Fallback behavior when parsing returns nil:** drop the deadline silently from the structured task, log once at `.warning` level for telemetry (so we can measure FM drift over time), and let the user re-state the deadline if it mattered. Do **not** re-prompt the model — that path leads to retry loops and prompt-injection surface.

### 10.4 NSDataDetector for free-form text

If a feature lets the user enter free-form date strings outside the FM pipeline (e.g. a quick-add field), `NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)` resolves common patterns against the user's locale. This is **not** in the FM extraction path — only for explicit free-text date entry. Treat it as input parsing, not as a fallback for the structured FM pipeline.

---

## 11. EventKit and WeatherKit interop

### 11.1 EventKit

`EKEvent.startDate` and `EKEvent.endDate` are `Date` values — absolute moments. Treat them as such. Don't read `EKEvent.timeZone` for display (display uses `Date.formatted(.dateTime.hour().minute())`, which resolves to user's TZ correctly).

The one case `EKEvent.timeZone` matters: a meeting that crosses a DST boundary in its original TZ. EventKit handles this correctly internally; we don't intervene.

### 11.2 WeatherKit

WeatherKit forecasts are timestamped `Date` values (absolute moments), but they describe **conditions at a location**. The natural reference frame for "the 10am forecast" is the **location's** timezone, not the device's.

Default: display weather times in the **forecast location's** timezone. A user checking Tokyo weather should see "10:00 AM" (when Tokyo is hot), not "10:00 PM" (when Tokyo is asleep but the user's device is in NYC).

```swift
// Forecast for a remote location — use that location's TZ
let formatter = DateFormatter()
formatter.locale = cal.userLocale()
formatter.timeZone = forecastLocation.timeZone
formatter.dateFormat = "h:mm a"
let label = formatter.string(from: forecast.time)
```

The user-TZ-default `.formatted(.dateTime.hour().minute())` is only correct when the forecast location *is* the user's current location — in which case both timezones are the same and you can use either.

This is the **only** allowed `DateFormatter` site outside `CalendarContext`. It lives behind a dedicated dependency (`LocationDateFormatter` or similar) if and when we ship a "weather for arbitrary location" feature, so the `timeZone` parameter is explicit at every call site.

---

## 12. Testing strategy

### 12.1 TestStore with `CalendarContext.fixed(...)`

The standard pattern: substitute `calendarContext` via `.fixed(now:timeZone:calendar:locale:)` so every helper is a real operation against a frozen clock.

```swift
func test_dailyBrief_regenerates_whenDayKeyChanges() async {
    let midnight = Date(timeIntervalSince1970: 1_778_630_400)  // 2026-05-13 00:00 UTC

    let store = TestStore(initialState: DailyBriefFeature.State()) {
        DailyBriefFeature()
    } withDependencies: {
        $0.calendarContext = .fixed(
            now: midnight,
            timeZone: TimeZone(identifier: "America/New_York")!
        )
    }

    await store.send(.appeared) { /* ... */ }
    // cal.dayKey(midnight) is "2026-05-12" in NYC (still May 12 at 8pm)
    // so we expect a regeneration if today's cached record is for "2026-05-12"
}
```

### 12.2 Locale stress tests for `dayKey`

The day-key must be `"2026-05-13"` for the same UTC `Date` regardless of the user's preferred calendar. This test would have caught the `DailyBriefRecord.todayString()` bug:

```swift
func test_dayKey_isCalendarIndependent() {
    let utcNoon = Date(timeIntervalSince1970: 1_778_673_600)  // 2026-05-13 12:00 UTC

    let contexts: [(String, CalendarContext)] = [
        ("en_US Gregorian", .fixed(
            now: utcNoon,
            timeZone: TimeZone(identifier: "UTC")!,
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US")
        )),
        ("th_TH Buddhist", .fixed(
            now: utcNoon,
            timeZone: TimeZone(identifier: "UTC")!,
            calendar: Calendar(identifier: .buddhist),
            locale: Locale(identifier: "th_TH")
        )),
        ("ja_JP Japanese", .fixed(
            now: utcNoon,
            timeZone: TimeZone(identifier: "UTC")!,
            calendar: Calendar(identifier: .japanese),
            locale: Locale(identifier: "ja_JP")
        ))
    ]

    for (label, cal) in contexts {
        XCTAssertEqual(
            cal.dayKey(utcNoon), "2026-05-13",
            "dayKey must be Gregorian regardless of user calendar — \(label)"
        )
    }
}
```

If any of these produce `"2569-05-13"` or `"R8-05-13"`, the day-key formatter is reading the user's calendar instead of the locked Gregorian one.

### 12.3 Date-line tests for `dayKey`

The same UTC moment must produce different day-keys when devices are in different timezones:

```swift
func test_dayKey_reflectsUserTimezone() {
    let moment = Date(timeIntervalSince1970: 1_778_708_700)  // 2026-05-13 21:45 UTC

    let nyc = CalendarContext.fixed(
        now: moment, timeZone: TimeZone(identifier: "America/New_York")!
    )
    let tokyo = CalendarContext.fixed(
        now: moment, timeZone: TimeZone(identifier: "Asia/Tokyo")!
    )

    XCTAssertEqual(nyc.dayKey(moment), "2026-05-13")   // 5:45 PM local
    XCTAssertEqual(tokyo.dayKey(moment), "2026-05-14") // 6:45 AM local next day
}
```

### 12.4 DST stress tests for `add`

Spring-forward in `America/New_York`, 2026: clocks jump from 02:00 → 03:00 on March 8.

```swift
func test_add_handlesSpringForward() {
    let beforeDST = Date(timeIntervalSince1970: 1_772_951_400)  // 2026-03-08 06:30 UTC = 01:30 EST
    let cal = CalendarContext.fixed(
        now: beforeDST,
        timeZone: TimeZone(identifier: "America/New_York")!
    )

    let oneDayLater = cal.add(.day, 1, beforeDST)

    // "1 day later" should land at the SAME local time (01:30 EDT, not 02:30)
    // — that means 23 hours of wall-clock elapsed, because DST ate an hour.
    let elapsed = oneDayLater.timeIntervalSince(beforeDST)
    XCTAssertEqual(elapsed, 23 * 3600, accuracy: 1)
}
```

If this fails, the production code probably uses `addingTimeInterval(86_400)` somewhere.

### 12.5 Round-trip equivalence

When (and if) we add a feature that needs `Date` equality across CloudKit sync, a targeted integration test must round-trip a `Date` through the SwiftData + CloudKit boundary and assert `cal.isSameDay(original, restored)`. Until then, no test required — but `==` comparisons on synced `Date` fields stay forbidden.

---

## 13. Migration plan

### 13.1 Current state (as of 2026-05-13)

Direct `Date()` and ad-hoc formatter calls in the codebase:

- [DailyBriefRecord.swift:67](FromInk/FromInk/App/Dependencies/DailyBrief/Models/DailyBriefRecord.swift:67) — `static func todayString()` uses bare `DateFormatter` with no POSIX locale. **Locale bug.**
- [DailyBriefClient.swift](FromInk/FromInk/App/Dependencies/DailyBriefClient.swift) — multiple `Date()` calls for "now", multiple `.formatted(.dateTime...)` calls for prompt construction.
- [HomeFeatureView.swift](FromInk/FromInk/rewrite/Home%20(needs%20work)/HomeFeatureView.swift:122) — `Date().formatted(...)` in view body.
- [DailyBriefFeature.swift](FromInk/FromInk/Library/DailyBriefFeature.swift), [DailyBriefCard.swift](FromInk/FromInk/Library/DailyBriefCard.swift), [DailyBrief.swift](FromInk/FromInk/Library/DailyBrief.swift) — legacy/POC, will be deleted per the migration markers in CLAUDE.md.
- [PageAnalyzer.swift:155](FromInk/FromInk/Canvas/PageAnalyzer.swift:155) — `ISO8601DateFormatter` allocation. Should move to `cal.parseISO8601Date(_:)` on `CalendarContext`.

### 13.2 Steps

1. **Land `CalendarContext`** in `App/Dependencies/CalendarContext.swift`. Wire into `AppDependencyContainer` (per bootstrap EDD §5). Include the `.fixed(...)` factory used by tests.
2. **Replace `DailyBriefRecord.date: String` with `generatedAt: Date` + `dayKey: String`.** Populate both at insertion from `cal.now()` and `cal.dayKey(cal.now())`. Delete `static func todayString()`.
3. **Migrate `DailyBriefClient`** to `@Dependency(\.calendarContext)`. Replace every `Date()` call in `DailyBriefClient.swift` with `cal.now()`. Replace the `DailyBriefRecord.todayString()` caller with `cal.dayKey(cal.now())`.
4. **Replace `ISO8601DateFormatter` in `PageAnalyzer.swift:155`** with `cal.parseISO8601Date(_:)`.
5. **Add the locale-stress and date-line test suite** (§12.2, §12.3) for `CalendarContext.dayKey`.
6. **Audit display-side `Date()` calls.** UI displays of "now" (e.g. the masthead in `HomeFeatureView`) should route through the reducer/wiring view rather than calling `Date()` in the view body. This unlocks time-warp testability.
7. **Migrate the brief-related references in `LibraryScreen.swift`, `DailyBriefCard.swift`, and `ToolbarFeature.swift`** off `DailyBriefFeature` and onto the new `DailyBriefClient` + snapshot flow. Once no references remain, **then** delete `Library/DailyBrief*.swift`. Note: this final step is owned by the bootstrap EDD's "delete parallel implementations" cleanup — it is not strictly a date concern, and bundling the deletion with the date migration would needlessly couple two unrelated changes. Track it as a follow-up.

Migration is fully behind `@Dependency`-substitution boundaries — no feature flag, no rollback complexity. Each step is testable in isolation, and steps 1–5 can ship without touching the legacy `Library/DailyBrief*` files at all.

---

## 14. Anti-patterns

- **Bare `Date()`** anywhere outside `CalendarContext.liveValue` and `@Model` property defaults (see exception below). Use `@Dependency(\.calendarContext) var cal; cal.now()`.
- **Ad-hoc `DateFormatter`** outside `CalendarContext` and the explicit weather-location formatter (§11.2). Allocating a formatter at the call site means you'll forget `locale = "en_US_POSIX"` once.
- **`Date.addingTimeInterval(N * 86400)` for day-shaped offsets.** DST will bite you twice a year. Use `cal.add(.day, N, date)`. (Sub-day precision offsets in seconds/minutes/hours are fine — see §9.2.)
- **Day-keys computed from UTC** (`formatter.timeZone = .gmt`). Honolulu and Auckland users get wrong days.
- **Day-keys computed in the user's preferred calendar.** Buddhist-calendar users get `"2569-05-13"` and miss CloudKit-synced cache entries.
- **Storing localized date strings in SwiftData** (e.g. `"May 13, 2026"`). Locale change breaks predicates; non-Latin scripts break dedup.
- **Comparing `Date` for equality after CloudKit round-trip.** Use `cal.isSameDay` or epsilon comparison — see §7.6.
- **Storing both `Date` and a derived `dayKey` but updating only one.** They must be set together at the same write site, never independently.
- **Reading `Date()` inside a reducer.** Breaks tests. Always `cal.now()`.
- **Reading `Calendar.current` directly.** Same reason. Always `cal.userCalendar()`.
- **Adding a `dayKey: String` to a UUID-identified record purely for query convenience.** Range predicates on `Date` are already ergonomic — see §8.3. `dayKey` belongs only on records where the day *is* the identity.

### The `@Model` property default exception

SwiftData `@Model` property defaults are evaluated at instance init and cannot read `@Dependency`. Bare `Date()` as a property default is therefore unavoidable in two patterns:

```swift
var generatedAt: Date = Date()    // "now" at creation
var createdAt: Date = Date()      // immutable timestamp
```

This is allowed. The compiler-evaluated `Date()` in a model default sets the property to the moment of *instance construction*, which is generally what you want for "when was this created."

What is **still** required: callers that explicitly *set* these fields (re-assigning `generatedAt` during a regenerate flow, for instance) must use `cal.now()` from `CalendarContext` — never `Date()`. The property default is the only allowed `Date()` site in `@Model` types.

If you need the model to capture a controllable "now" (for time-warp tests of model creation), accept it as an init parameter instead of relying on the default:

```swift
init(id: UUID = UUID(), generatedAt: Date, /* ... */) {
    self.id = id
    self.generatedAt = generatedAt
}
// Caller: DailyBriefRecord(generatedAt: cal.now(), ...)
```

---

## 15. Open questions

1. **Frozen-at-write `dayKey` vs read-time recomputation.** §7.4 chose frozen — a brief generated in PT carries `dayKey = "2026-05-13"` even when read later in Tokyo. The alternative (recompute on read against current TZ) makes "yesterday's brief" follow the user around the date line, sacrificing the journal-like semantics of `DailyBriefRecord`. Default: frozen. Reconsider if users complain about briefs "disappearing" after travel.
2. **Should we cache the day-key on `DailyBriefSnapshot`** so the view doesn't re-derive it? Marginal — derivation is allocation-free (`String(format:)`) and runs once per snapshot. Defer until profiling shows a hot path.
3. **Time-warp UI ("show me yesterday's brief").** Initial design: substitute `calendarContext` with `.fixed(now: pastDate)` via a `WarpFeature` reducer. Open question whether `WarpFeature` should own its own date dependency or override `\.calendarContext` globally.
4. **Repeating events crossing DST.** Punted — EventKit handles internally; surface only if users report issues.
5. **Multi-timezone collaboration.** If a shared notebook has highlights tied to "today," and two collaborators are in different timezones, whose "today" wins? Default: each collaborator's local day; the `dayKey` differs per device. Reconsider if it produces confusing UI.
6. **`parseISO8601Date` on `CalendarContext` vs its own dependency.** Folded onto `CalendarContext` for now (one dependency, easier substitution). If a second non-ISO parser appears (e.g. RFC 822 for email), promote both to a separate `DateParsing` dependency.

---

## 16. Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-13 | Single `CalendarContext` TCA dependency owns all date/time/calendar/timezone access. | One place to be correct beats N call sites that each remember to set POSIX locale. |
| 2026-05-13 | `CalendarContext` composes TCA's `\.date` and `\.calendar` built-ins rather than replacing them. | Built-ins are well-tested; substituting `\.date.now` still propagates to `CalendarContext` consumers. `CalendarContext` adds timezone/locale/day-key facets the built-ins don't cover, co-located in one value. |
| 2026-05-13 | `Date` is the only persisted moment form. Day-keys are derived strings, never the source of truth. | CloudKit syncs `Date` losslessly; absolute moments are timezone-invariant. |
| 2026-05-13 | Day-keys formatted as Gregorian + POSIX, in user's timezone. | Locks format independent of user's calendar preference; correctly differs across timezones for the same UTC moment. |
| 2026-05-13 | `String(format: "%04d-%02d-%02d", ...)` not `DateFormatter` for day-keys, with `preconditionFailure` on the unreachable nil branch. | Allocation-free, called in hot paths, no formatter-config drift surface, no force unwraps. |
| 2026-05-13 | `dayKey` is frozen at write time, never recomputed on read. | Preserves journal-like semantics for `DailyBriefRecord`; the alternative (recompute on read) would make briefs "move" across the date line with the user. |
| 2026-05-13 | `dayKey: String` belongs only on records where the day **is** the identity, not on UUID-identified records with day-bucketed queries. | Range predicates on `Date` are already ergonomic; dual-write coordination cost only pays off for one-row-per-day models. |
| 2026-05-13 | All day-shaped date arithmetic via `Calendar.date(byAdding:value:to:)`; sub-day precision offsets via `addingTimeInterval` are fine. | DST-safe where it matters; `addingTimeInterval` is the natural expression for exact-N-seconds offsets that should not shift. |
| 2026-05-13 | `cal.add` traps via `preconditionFailure` on nil rather than silently returning the input. | Silent fallback to input would cause infinite loops in step-by-step iteration. |
| 2026-05-13 | FM output for dates is ISO-8601 `"yyyy-MM-dd"`, parsed via `cal.parseISO8601Date(_:)` co-located on `CalendarContext`. | Output produced by `dayKey` and input consumed by `parseISO8601Date` share format; co-location prevents drift. `@Generable enum` rejected because relative-day variety from handwriting exceeds what an enum can usefully enumerate. |
| 2026-05-13 | `testValue` is a real, deterministic context built via `.fixed(now:...)` — not a stub of constant-returning closures. | Stub `testValue` masks bugs by always succeeding; tests then have to fully substitute via `withDependencies` at every call site, defeating the point of `testValue`. |
| 2026-05-13 | `@Model` property defaults may use bare `Date()` — the only allowed exception to the no-bare-`Date()` rule. | SwiftData property defaults can't read `@Dependency`; callers re-assigning these fields still go through `cal.now()`. |
| 2026-05-13 | Feature views and component views never read `CalendarContext` directly. Wiring views may read it in the adapter that builds the `Model`. | Views render Date → String via `.formatted(.dateTime...)`; day-comparison logic stays in adapters/reducers. The wiring layer is the legal boundary. |
| 2026-05-13 | WeatherKit display defaults to the **location's** timezone, not the device's. | A weather forecast describes conditions at a place; the "10am forecast" is meaningful in that place's wall clock, not the viewer's. |
