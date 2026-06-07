# From Ink — Subscription Engineering Design

> **Status:** Active. V1 commercial architecture ratified at the 2026-06 design pass. Three product SKUs (Lifetime, Yearly, Monthly), 7-day in-app trial without payment commitment, day-8 hard paywall, no freemium tier, 14-day "we won't push back" lifetime refund guarantee. StoreKit integration is the remaining engineering blocker; the paywall UI ships first with display-only product strings.

---

## 1. Goals

- **Ship a paywall that tells the brand story.** The paywall is the first time most users encounter From Ink's commercial posture. Its visual hierarchy, headline, and tier framing should communicate the values position — *we believe writers should own their tools* — before they communicate any individual price.
- **Default to ownership at the moment of first commitment.** Lifetime is the canonical purchase, available until the user makes their first commercial commitment — starting a subscription, or engaging with lifetime (purchase or refund). After that commitment is made, lifetime is permanently closed for that user. The brand position respects the deliberateness of their first decision.
- **No freemium tier.** From Ink is a premium tool. Users get a 7-day full-featured trial after onboarding without entering Apple ID payment information; on day 8 the app locks until they pick a plan. The trial *is* the try-before-you-buy; there is no permanent free state.
- **A 14-day "we won't push back" refund window on lifetime.** Users who buy lifetime can request a refund through Apple within 14 days and From Ink will not contest it. This is the brand promise that makes the cold-purchase commitment acceptable.
- **Bound complexity to three SKUs on one screen.** No tier ladder, no upsell modals, no feature gating between tiers. Every paid customer gets the same From Ink, only the payment cadence differs.
- **No recurring infrastructure cost commitment.** The pricing model is sustainable because operating cost per user is near zero — no servers, no per-user AI inference billing (Foundation Models runs on the user's device), no per-user storage billing (data lives in the user's own iCloud account). The subscription tiers fund development; the lifetime tier funds development at launch and accepts no further revenue.
- **Procreate as the comparable, not Notion.** The closest analog is Procreate's one-time iPad purchase: a tool sold once, supported with free updates forever, no rent. From Ink's three-tier shape extends this by offering subscriptions for users who specifically want them, while keeping the one-time-purchase as the brand position. The 7-day in-app trial gives From Ink a softer onboarding than Procreate's cold paywall.

## 2. Tiers

Three SKUs. One paywall. Lifetime is the default-selected option at the moment a user is making their first commitment decision (when `canSeeLifetimeOffer` is true — see §2.2).

| Tier | Price | Type | Trial | Default? | Family Sharing |
|---|---|---|---|---|---|
| **From Ink Plus — Lifetime** | $19.99 | Non-consumable IAP | 14-day refund window (not a trial in the StoreKit sense) | **Yes — default-selected when shown** | ✅ Enabled |
| **From Ink Plus — Yearly** | $14.99 / year | Auto-renewable subscription | 7 days | No | ✅ Enabled |
| **From Ink Plus — Monthly** | $2.99 / month | Auto-renewable subscription | 7 days | No | ✅ Enabled |

**Why $19.99 lifetime.** The conventional indie ratio of lifetime to annual is 4–6×, on the assumption that lifetime sales replace future subscription revenue from the same customer. That ratio is appropriate for apps with ongoing per-user costs and recurring-revenue investor expectations. From Ink has neither. The brand's pricing model is closer to iTunes's rent-vs-buy ratio: $14.99/year rents the app; $19.99 owns it. A user who would have stayed two years on annual pays $29.98 — they save $9.99 by owning. A user who would have churned at month 7 pays $14.99 — they spend $5 more to own. The math favors lifetime conversion in both common retention scenarios while removing all subscription anxiety. Higher conversion × marginally lower per-customer revenue is the deliberate trade.

**Why $14.99/year.** Matches Bear's Bear Pro annual price exactly. Bear is the closest direct comparable in brand-positioning terms (editorial typography, indie maker, premium-but-accessible). Matching the price aligns From Ink with the category Bear occupies in user mental models without re-anchoring expectations.

**Why $2.99/month.** Mathematical: $2.99 × 12 = $35.88, making the yearly tier 58% cheaper than monthly. That ratio is the right rhetorical strength — clearly anchors yearly as the value choice without making monthly feel deliberately punitive ($1.99/mo would make yearly only 37% cheaper, weakening the anchor; $3.99/mo at 65% would feel manipulative).

### 2.1 Family Sharing policy

**Family Sharing is enabled on all three tiers.**

Apple supports Family Sharing for both auto-renewable subscriptions AND non-consumable IAPs — [Apple confirms](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases/): *"Family Sharing for In-App Purchases lets people share their auto-renewable subscriptions and non-consumables with up to five additional family members."* This means a single $19.99 lifetime purchase grants permanent access to up to 6 family members in the purchaser's Apple Family Sharing group, with no additional cost.

**Why all three, including lifetime.** From Ink's positioning ("we don't want to rent you software — we want to give it to you") naturally extends to "we don't want to rent your family software either." Refusing Family Sharing on the lifetime tier would be saying "you own your software, but not enough to share with your spouse" — reads as a brand contradiction. The realistic per-purchase revenue dilution from Family Sharing is bounded (most family groups use 2–3 of the available 6 slots, not all 6), and the marketing value of "Family Sharing supported" is a passively-discovered conversion signal users specifically filter for in the App Store.

**Mechanical differences between subscription and non-consumable family sharing:**

| Aspect | Subscription (Yearly, Monthly) | Non-Consumable (Lifetime) |
|---|---|---|
| **Revocability** | Organizer cancels or payment fails → entitlement expires at period boundary → all family members lose access at the same time | Organizer cannot "cancel" a permanent purchase. Family members keep access indefinitely while they remain in the family group. |
| **Lifecycle** | Conditional on continued payment; re-evaluated every billing period | Unconditional from the moment of purchase forward |
| **Family member leaves family group** | Loses access at the period boundary (entitlement re-evaluates) | Loses access immediately when removed from the family group |
| **Refund within Apple's refund window** | Access revoked at period boundary | Access revoked immediately for both organizer and family |
| **"Manage Subscription" UI** | Family members see read-only state ("Subscribed via Family Sharing — manage on organizer's device") | No "manage" UI exists; the IAP is permanent |
| **StoreKit API surface** | `Transaction.currentEntitlements`; `Transaction.ownershipType` returns `.familyShared` for non-purchasers | Identical — same `Transaction.currentEntitlements` enumeration, same `.familyShared` ownership type |

**One-way-door rule.** Per Apple's docs: *"Once you select Confirm, your product will be family shareable for all your customers, new and existing, within a few hours. Once enabled for a given product, this cannot be reverted."* This is a deliberate constraint — disabling Family Sharing after launch would orphan family members who relied on the entitlement. **Once a product is enabled for Family Sharing in App Store Connect, the team commits to that policy permanently.**

**Retroactive applicability.** When Family Sharing is enabled on a product, *existing* purchases of that product become family-shareable too, not just new purchases. This means: if From Ink ships V1 with Family Sharing toggled on from day one, every lifetime purchase from day one onward is family-shareable. There is no "early adopters get the single-user version" footnote.

**StoreKit implementation cost: zero.** Per Apple: *"Your application will likely already handle family transactions without making any changes, because automatically these purchases are available to all family members."* The integration code reads `Transaction.currentEntitlements` and grants access regardless of whether the transaction is `.purchased` or `.familyShared`. The only optional UI surface is differentiating the two in the user's Plan screen (e.g., "Shared by your family") via `Transaction.ownershipType`. See §6 and §7 for the canonical patterns.

**Revocation handling.** When a non-consumable lifetime IAP is family-shared and a family member later leaves the family group, Apple's StoreKit emits a transaction with `Transaction.revocationDate` set. The app must handle this — same handler as subscription expiry. Per Apple's [Supporting Family Sharing in your app](https://developer.apple.com/documentation/storekit/supporting-family-sharing-in-your-app) doc: *"It is critical to listen for transactions at launch and to continue to do so throughout the lifetime of the app to ensure your app never misses a transaction."* See §6.2 for the implementation pattern.

**Region constraint.** Family Sharing requires all family members to be in the same App Store country/region. Users in mixed-region families cannot share From Ink purchases. This is an Apple platform constraint, not something the app implements.

### 2.2 The lifetime gate

Lifetime is not always available. It is offered until the user makes their first commercial commitment, which is one of two events:

- **Starting a personal subscription** (yearly or monthly, including a 7-day Apple-mediated trial start — the trial start itself creates the transaction)
- **Engaging with lifetime** (purchasing lifetime, whether or not they later refund within the 14-day window)

Once either event occurs, the lifetime card disappears permanently from every paywall surface for that user — onboarding paywall, day-8 hard paywall, Settings → Plan upgrade affordance, all paywall triggers.

**Detection** — these are async functions because `Transaction.all` is an `AsyncSequence`:

```swift
func hasEverPersonallySubscribed() async -> Bool {
    for await result in Transaction.all {
        guard case .verified(let txn) = result else { continue }
        guard txn.productType == .autoRenewable else { continue }
        guard txn.ownershipType == .purchased else { continue }
        return true
    }
    return false
}

func hasEverEngagedWithLifetime() async -> Bool {
    for await result in Transaction.all {
        guard case .verified(let txn) = result else { continue }
        guard txn.productType == .nonConsumable else { continue }
        guard txn.ownershipType == .purchased else { continue }
        return true
    }
    return false
}

func canSeeLifetimeOffer() async -> Bool {
    !(await hasEverEngagedWithLifetime()) && !(await hasEverPersonallySubscribed())
}
```

Returning early on the first match is intentional and correct — we don't need to enumerate the full history, only confirm at least one matching transaction exists. The iteration is cancelled when the function returns.

The result is cached at the call site (typically inside `SubscriptionService.liveValue` — see §6.2) and invalidated by `Transaction.updates` so the gate doesn't re-traverse `Transaction.all` on every UI render.

The two gates use the same `.purchased` ownership filter so that family-shared past transactions never count toward "this user committed." Beneficiaries who lose family access (the organizer cancels, they're removed from the family group, etc.) are treated as fresh users — they never spent their own money on the product, so their option to buy lifetime remains open. See §7.3 for the beneficiary upgrade path that explicitly serves this scenario.

The combined `canSeeLifetimeOffer` check is the single source of truth for "show the lifetime card?" across the app. Used by:

- The onboarding paywall (when shown to users with no current entitlement)
- The day-8 hard paywall
- Settings → Plan beneficiary upgrade affordance (§7.3)
- Settings → Plan "See Plans →" route for lapsed users

### 2.3 The 7-day in-app trial mechanic

From Ink has no permanent free tier. Users who decline the onboarding paywall enter a 7-day full-featured trial; on day 8 the app presents a hard paywall that cannot be dismissed until they choose a plan.

**The trial does not require Apple ID payment information.** It is enforced in-app by a `TrialService` dependency reading the start date from iCloud Key-Value Storage. The user gets the full Plus experience — Daily Brief, unlimited notebooks, Quick Notes, Calendar/Reminders linking, PDF import, smart search, the complete feature set — for 7 days before being asked to commit.

**Trial state:**

```swift
struct TrialState: Equatable, Sendable {
    var startedAt: Date  // set once on first onboarding completion, immutable
}

extension TrialState {
    func daysRemaining(now: Date) -> Int {
        let elapsed = now.timeIntervalSince(startedAt)
        return max(0, 7 - Int(elapsed / 86400))
    }

    func hasExpired(now: Date) -> Bool {
        daysRemaining(now: now) == 0
    }
}
```

All date math routes through `CalendarContext.now()` per the dates EDD — bare `Date()` is banned outside `CalendarContext.liveValue`.

**No clock-tampering protection — accepted risk.** A user who sets their device clock back can extend the trial. This is deliberate:

- Defending against clock tampering would require tracking `maxObservedDate` and rejecting clock rollbacks. This complicates manual QA: verifying the day-8 hard paywall would require waiting a real week or building test-only code paths that diverge from production behavior.
- The cheater segment is small and the LTV of a cheater is zero — if they were going to convert, the friction of clock manipulation wouldn't have stopped them; if they weren't, defeating their workaround doesn't recover lost revenue.
- The accepted loophole has the same shape as the "uninstall to game it" loophole, which is structurally accepted via the iCloud KVS strategy.
- `CalendarContext.now()` is the production date source; `CalendarContext.fixed(...)` is the unit-test date source; manual QA changes the device clock directly. Trial expiration behavior is testable in all three modes without any guarding code.

**iCloud KVS persistence.** Trial state stores in `NSUbiquitousKeyValueStore` under a fixed key, syncing across the user's devices on the same Apple ID. A user installing on iPad + iPhone gets one combined 7-day trial, not two. Signing out of iCloud falls back to local UserDefaults state (per-device trial) — accepted edge case for that small segment.

**iCloud KVS sync delay.** `NSUbiquitousKeyValueStore` syncs through iCloud and can have noticeable propagation latency — typically seconds, occasionally minutes. Scenario: user dismisses the paywall on iPhone (trial starts), immediately opens iPad before KVS has propagated. iPad reads `trialState == .notStarted`, routes to the soft paywall again. Mitigation: writes go to BOTH `NSUbiquitousKeyValueStore` AND local `UserDefaults`; reads prefer the *earlier* `startedAt` value between the two (most conservative — the user gets the earlier-starting trial, not a fresh one). When KVS catches up via `NSUbiquitousKeyValueStoreDidChangeExternallyNotification`, the local copy is reconciled. The brief race window where the paywall might re-render on a second device is acceptable; double-trial issuance is not.

**In-app trial countdown surfacing.** During the active trial the user needs visible context so day 8 doesn't feel like an ambush. The schedule:

- **Days 1–4:** No surfacing. The user is exploring; we don't haunt them with a countdown.
- **Day 5:** A passive line in the Home screen's existing day chrome — "Trial · 3 days left." Same typography as the date/weather line, no separate banner.
- **Day 6:** Same line. Plus: the Settings → Plan screen highlights the trial state (see §7.2 row 9).
- **Day 7:** The Home chrome line shifts to "Trial ends tomorrow." Slightly louder, still passive.
- **Day 8 launch:** Hard paywall presents (see §8.4).

The Plan screen's trial-active state (§7.2 row 9) shows the same countdown regardless of which day the user navigates to it. The Home chrome only surfaces from day 5 forward.

If push notification permission has been granted (per `OnboardingPermissionsView`), a local notification fires once on day 7 morning: "Your From Ink trial ends tomorrow." No remote push, no Apple ID involvement — just `UNUserNotificationCenter` with a `UNCalendarNotificationTrigger`. If permission was not granted, the in-app surfacing is the only signal.

**Family-shared users skip the trial entirely.** A user whose first launch detects a `.familyShared` entitlement is already entitled to the full app; the trial state is never initialized for them. If their family entitlement later revokes (organizer leaves, removed from family), they become a fresh trial user at that moment — their iCloud KVS trial state is still `.notStarted` because they never started one.

## 3. The "Pay once. Yours, forever." commitment

This is the load-bearing commitment under the lifetime tier. It is not a marketing tagline. It is a binding promise that shapes every subsequent product decision.

> **Lifetime customers receive the full From Ink Plus feature set, including every update we ever ship, for as long as the app remains available on the App Store.**

The Procreate parallel is intentional: Procreate sold at $4.99 in 2011, raised to $12.99 over a decade as the app matured, has shipped over 50 free major updates to all customers regardless of when they bought, and remains a category leader. The "yours forever" promise IS the brand; once stated, it cannot be retracted without destroying that brand.

**What this means in practice for future development decisions:**

- New features added to From Ink Plus must ship to lifetime customers at no additional cost.
- Feature retirement that affects lifetime customers (e.g., dropping support for a deprecated iOS version, sunsetting an integration) must be communicated transparently and well in advance.
- Server-side capabilities (if any are ever added — currently none planned) must not be the gate behind which lifetime customers' previously-paid-for features stop working. The app must remain functional on the user's device even if the cloud component disappears.
- Pricing for new customers may rise (e.g., $19.99 lifetime → $29.99 in 2028 to match inflation and feature accumulation). Existing lifetime customers are grandfathered at their purchase price; their access does not lapse, their feature set does not shrink.

### 3.1 Future Pro tier disclosure

A separate **Pro** tier may be introduced in the future (likely 12–24 months post-launch, when a meaningful differentiator exists — multi-device collaboration, enterprise integrations, advanced AI capabilities, etc.). To preempt the customer-relations problem where lifetime users feel betrayed by a future paid tier, the lifetime purchase flow must include this disclosure at purchase time:

> **Lifetime includes all current and future From Ink Plus features. A separate Pro tier (if added) may include additional functionality at additional cost. Pro is not currently planned and would only be introduced if a substantive new capability warrants its own tier.**

This disclosure:
- Lives in the lifetime tier's purchase confirmation or fine-print area, not the paywall hero card (which sells, not disclaims).
- Is rendered before the StoreKit purchase sheet, so the user has an opportunity to read it before tapping through.
- Must be localized in all nine launch languages per the localization EDD.
- Is the contract reference for any future customer-relations dispute. Future-Pro feature decisions must be tested against it.

**The line:** features that *extend* what From Ink Plus already does (better OCR, more integrations, more file formats, more AI capability in existing surfaces) belong in Plus, included for lifetime customers. Features that introduce *fundamentally different surfaces* (real-time collaboration with other users, server-side AI model fine-tuning, team workspaces, enterprise SSO) could justify Pro. The Plus/Pro split is "deeper" vs "wider," not "old" vs "new."

### 3.2 The 14-day "we won't push back" refund guarantee

The lifetime tier carries a brand commitment that distinguishes it from the subscription tiers: **a 14-day window after purchase during which From Ink commits to honoring refund requests via Apple's standard mechanism, with no friction.**

The brand promise, in user-facing copy:

> Buy lifetime. Try it for 14 days. If it's not for you, request a refund through Apple. We won't push back.

What this means in practice:

- **Apple is the actual arbiter of refunds.** We cannot programmatically issue them; the decision is always Apple's. Our promise is procedural: we will not flag the request as fraudulent, will not respond to Apple's developer-feedback process negatively, and will not contest a legitimate refund request inside the 14-day window. In practice Apple approves nearly all first-window refund requests for non-flagged users when the developer doesn't object.
- **In-app refund affordance.** A "Request Refund ↗" button in Settings → Plan opens Apple's native refund sheet (`AppStore.refundRequestSheet(for:in:)`). The button is visible only while the user is within the 14-day window. After day 14, it disappears.
- **After 14 days.** Users can still go through Apple's standard refund process (Apple's overall window is technically up to 90 days). We make no in-app surface for it — they're outside our brand commitment window.
- **The refund counts as engagement with lifetime.** Once a user has bought lifetime (refunded or not), `hasEverEngagedWithLifetime` returns true permanently. They will never see the lifetime offer again. They had their 14 days to decide; the decision they made was to refund. The lifetime door closes either way. See §2.2.

**Why 14 days, not 7.** Subscription tiers get Apple's 7-day free trial. Lifetime customers can't get a StoreKit-mediated trial because non-consumable IAPs don't support introductory offers. The 14-day refund guarantee is the lifetime tier's parallel — twice as long to compensate for the upfront commitment, and framed as a refund (which the user must actively request) rather than an automatic billing trigger.

**Why "we won't push back" instead of "guaranteed refund."** Apple owns the refund decision; we cannot legally promise a guaranteed outcome. "We won't push back" is the exact procedural promise we can keep, and the brand voice register accepts it as honest rather than weaselly.

**Where the promise lives on the legal surface.** The 14-day "we won't push back" commitment is brand copy in the paywall and Plan screen — but it also needs a durable legal home so support staff, Apple's review team, and any future customer-relations dispute can cite it. The commitment is documented in:

1. **The Terms of Service** — a clause naming the 14-day window and our procedural commitment to not contest legitimate first-window refund requests. Authoritative text.
2. **The pre-purchase Pro tier disclosure** (§3.1 sibling) — rendered before the StoreKit lifetime purchase sheet, alongside the future-Pro disclosure. Same fine-print surface; the user sees both before tapping through.
3. **The lifetime card body line 4** ("14 days to change your mind.") — marketing surface, references the underlying commitment without spelling it out.

The Terms of Service entry is the legally binding text; the in-app surfaces are user-facing summaries of it. When the Terms URL is published (Open Question #2), this clause is what goes there.

## 4. Trial mechanics and the refund window

From Ink has three distinct "try before you buy" mechanisms, each serving a different user posture. Distinguishing them is important for both the marketing surface and the implementation.

| Mechanism | Duration | When it applies | Payment commitment required |
|---|---|---|---|
| **In-app onboarding trial** | 7 days | User dismisses the paywall at onboarding | No |
| **Apple subscription trial** | 7 days | User starts yearly or monthly via StoreKit | Yes (Apple ID + billing method) |
| **Lifetime refund guarantee** | 14 days | User buys lifetime | Yes (upfront purchase) |

### 4.1 In-app onboarding trial

The user encounters the 3-card paywall at the end of onboarding, dismisses it without buying, and enters the app as a full-featured user for 7 days. No payment method is entered, no Apple ID prompt fires. The trial is enforced by `TrialService` reading state from iCloud KVS (§2.3).

This is the lowest-friction try-before-you-buy. It exists because Apple's subscription trial requires the user to commit to a billing relationship upfront, which is a meaningful psychological barrier even for users who would convert. The in-app trial removes that barrier.

### 4.2 Apple subscription trial

The user picks yearly or monthly on the paywall, taps the CTA, completes Apple's StoreKit purchase flow. Apple starts a 7-day free trial; billing begins on day 8 unless the user cancels via `AppStore.showManageSubscriptions(in:)` before then.

This is the standard Apple subscription trial, fully managed by StoreKit. Apple's day-6 trial-ending push notification fires as part of the conversion mechanic.

**Starting an Apple subscription trial triggers the lifetime gate.** `hasEverPersonallySubscribed` becomes true at the moment of trial start (the trial creates a `Transaction.all` entry with `.purchased` ownership), and the lifetime card disappears for that user permanently — even if they cancel before billing starts.

### 4.3 Lifetime refund guarantee

The user buys lifetime cold (no trial — non-consumable IAPs don't trial via StoreKit). For 14 days after the purchase date, From Ink commits to not contest a refund request via Apple's standard mechanism.

In-app refund affordance: a button in Settings → Plan that opens `AppStore.refundRequestSheet(for:in:)`. Visible only while within the 14-day window. Disappears after.

After refund: the user's lifetime entitlement revokes via `Transaction.updates`; `hasEverEngagedWithLifetime` remains true forever (the engagement happened); the user is routed to the day-8 hard paywall on next launch (no trial restart — they consumed their try-period in the form of the 14 days of ownership).

### 4.4 No overlap, no chaining

A user gets one shot at each mechanism. They cannot:

- Start the in-app trial, then refund a lifetime to get another in-app trial
- Cancel an Apple subscription trial, then start a fresh in-app trial
- Refund a lifetime then get a fresh in-app trial

Each of these is blocked by gate detection: `hasEverEngagedWithLifetime`, `hasEverPersonallySubscribed`, and `TrialState.startedAt` is set once and never reset. The brand position: every user gets one fair window to evaluate the product. After they've consumed their window — by either committing, dismissing-then-letting-trial-expire, or refunding lifetime — they're at the hard paywall.

## 5. Paywall layout architecture

The paywall is `OnboardingSubscriptionView`, the fourth screen of the onboarding flow. It is also presented as the day-8 hard paywall after trial expiration and as the "See Plans →" route from Settings → Plan when the user has no active entitlement.

The Model can render in two visibility modes depending on `canSeeLifetimeOffer`:

- **3-card mode** — lifetime card + paired subscription cards (default when `canSeeLifetimeOffer` is true)
- **2-card mode** — paired subscription cards only (when the user has already engaged with lifetime or subscribed personally)

When rendered as the day-8 hard paywall, the dismiss affordance (X close button) is suppressed; the user cannot exit the screen without choosing a plan.

### 5.1 Visual hierarchy (3-card mode)

```
                       FROM INK PLUS                    ← Kicker (mono uppercase)

                Pay once. Yours, forever.               ← Two-tone headline
                                                          "Pay once." in ink
                                                          "Yours, forever." italic ink-2

         Pay once for From Ink. Every update we ever    ← Body copy
         ship — yours too. Subscriptions are also          (3 sentences)
         available.

       ── ── ── ── ── ── ── ── ── ── ── ── ── ──        ← Rule

       ┌──────────────────────────────────────────┐    ← Lifetime hero card
       │            LIFETIME    ●                 │      (selected by default
       │                                          │       in 3-card mode)
       │              $19.99                      │
       │           pay once                       │
       │                                          │
       │   From Ink, and every update we'll       │
       │   ever ship. Yours, on every device      │
       │   you'll ever own. No subscription.      │
       │   14 days to change your mind.           │
       └──────────────────────────────────────────┘

         This offer ends the moment you subscribe.     ← Constraint line
                                                          (small mono caption)

                  or, try free for 7 days             ← Connector copy

         ┌──────────────────┐  ┌──────────────────┐   ← Subscription cards
         │      YEARLY      │  │     MONTHLY      │     (paired, equal weight,
         │    $14.99/yr     │  │    $2.99/mo      │      visually smaller than
         │  about $1.25/mo  │  │                  │      the lifetime hero)
         └──────────────────┘  └──────────────────┘

       ── ── ── ── ── ── ── ── ── ── ── ── ── ──        ← Rule

         ✓ Unlimited notebooks and pages                 ← Feature list
         ✓ A canvas for ink and text                       (9 rows, identical
         ✓ Handwriting becomes searchable                  for all tiers — the
         ✓ Daily brief and smart search                    tiers differ in
         ✓ Calendar and reminder linking                   payment cadence,
         ✓ Tasks routed to your apps                       not feature set)
         ✓ Searchable PDF import
         ✓ iCloud sync across devices
         ✓ Family Sharing for up to 6

         ┌──────────────────────────────────────┐       ← CTA (varies by
         │                Buy →                 │         selected tier;
         └──────────────────────────────────────┘         see §5.4)

                  RESTORE  PRIVACY  TERMS                ← Legal chrome
```

### 5.2 Visual hierarchy (2-card mode)

When `canSeeLifetimeOffer` is false, the lifetime card and its constraint line disappear. The paired subscription cards become the only options, the connector "or, try free for 7 days" becomes the lead-in (no longer a bridge), and the headline + body copy shift to subscription-leaning framing:

```
                       FROM INK PLUS

                Try free for 7 days,                    ← Two-tone headline
                then your pick of plan.                   "Try free for 7 days,"
                                                          in ink, "then your pick
                                                          of plan." italic ink-2

         The full From Ink, billed at your pace.        ← Body (1–2 sentences)
         Cancel anytime.

         ┌──────────────────┐  ┌──────────────────┐
         │      YEARLY      │  │     MONTHLY      │
         │    $14.99/yr     │  │    $2.99/mo      │
         │  about $1.25/mo  │  │                  │
         └──────────────────┘  └──────────────────┘

       ── ── ── ── ── ── ── ── ── ── ── ── ── ──

         [ feature list — same 9 rows ]

         ┌──────────────────────────────────────┐
         │           Start free trial →         │
         └──────────────────────────────────────┘

                  RESTORE  PRIVACY  TERMS
```

No "this used to be here" placeholder for the missing lifetime card, no "you're missing out" pressure. The lifetime card simply isn't part of this user's world anymore.

### 5.3 Why this hierarchy

**Lifetime as visual hero, subscriptions as paired secondary.** A three-equal-card grid would communicate "here are three options; pick one." That is the standard subscription paywall and it does not say what From Ink believes. The hero-plus-pair hierarchy communicates "this is what we recommend; these are alternatives if you prefer." The visual language matches industry conventions for highlighting "Most popular" tiers, so the user recognizes the pattern instantly — but the *meaning* is inverted: instead of "most popular subscription," it's "the way we want you to buy this."

**The connector "or, try free for 7 days"** does two things in one line: it bridges the visual transition from hero to paired cards, and it tells the user that the 7-day Apple-mediated trial is a subscription-only thing. Without this line, a user looking at the lifetime card would reasonably wonder where the trial went. With it, the trial offer is clearly associated with the right tiers.

**Feature list identical for all three tiers.** Because the tiers differ in payment cadence, not feature access, there is no "Lifetime gets X, Yearly gets Y, Monthly gets Z" matrix to render. Every paid customer receives the same From Ink. The feature list reflects this — nine rows, identical regardless of which tier is selected.

### 5.4 The Lifetime card body copy

Four lines, each doing one job:

> **From Ink, and every update we'll ever ship.**
> **Yours, on every device you'll ever own.**
> **No subscription.**
> **14 days to change your mind.**

Line 1 — the lifetime *update* promise (the Procreate commitment).
Line 2 — the lifetime *device* promise (clarifies the practical scope; iCloud sync means lifetime access follows the user across devices they own now and devices they buy in the future).
Line 3 — the *negative space* punch. "No subscription." is the one sentence on the entire paywall that defines what From Ink is *against*. It does not appear anywhere else on the paywall. Do not soften it. Do not bury it.
Line 4 — the *safety net*. The 14-day refund guarantee, stated declaratively without scarcity drama. Pairs with the brand promise in §3.2.

### 5.5 The constraint line below the lifetime card

> *This offer ends the moment you subscribe.*

Small mono italic caption rendered below the lifetime card. Tells the user the structure of the offer before they make any decision: the lifetime card disappears for them permanently if they commit to a subscription. Honest, declarative, no scarcity language.

This caption is visible only when the lifetime card is rendered (3-card mode). When the lifetime card is gone, the caption is too.

### 5.6 CTA label per selected tier

The primary CTA's label varies based on which tier is currently selected:

| Selected tier | CTA label |
|---|---|
| Lifetime | **Buy →** |
| Yearly | **Start free trial →** |
| Monthly | **Start free trial →** |

The CTA does double duty as both action affordance and brand reinforcement. "Buy →" is intentionally minimal — one word in English that translates as a single word or 2-character cluster in every target language (`Acheter`, `Kaufen`, `Acquista`, `Comprar`, `购买`, `購入`, `구매`), with no length-expansion risk on the button at AX5 Dynamic Type sizes. It also matches Apple's standard button label for non-consumable IAPs across all 175 App Store storefronts, conforming with platform convention at the moment of conversion.

The brand commitment is carried by the headline, the lifetime card's four lines, and the body copy — not by the button. The button confirms the action the user is about to take, and does it briefly.

The subscription CTAs ("Start free trial →") match user expectations from every other subscription paywall they've seen and accurately describe what tapping the button triggers (a 7-day Apple-mediated trial before billing begins).

The CTA's position, color, typography, and width are constant. Only the label string varies. This preserves the persistent-button view identity established in `OnboardingContainerView`.

### 5.7 Default selection

**Lifetime is selected by default in 3-card mode. Yearly is selected by default in 2-card mode.**

The reasoning is dual: it captures the indifferent middle of users (the ones who don't manually change the default) for the brand's preferred outcome, AND it communicates the brand position. Users who specifically want a subscription will manually switch; users who don't care will land where the product steers them.

In 2-card mode (no lifetime), yearly is the brand's preferred subscription tier (better per-month value, signals a longer commitment, lower churn than monthly). The same defaulting logic applies — push the indifferent middle toward the option that aligns with the brand.

This is a deliberate departure from conventional paywall design, which typically defaults to whichever tier converts highest by revenue — usually annual. Default-to-lifetime is a brand decision that accepts slightly lower revenue per converted user in exchange for the brand statement being lived, not just stated.

## 6. StoreKit product configuration

Three products in App Store Connect under the `com.fromink.app` bundle ID. Product IDs follow Apple's reverse-DNS convention with a category segment for clarity.

| SKU | Product ID | Type | StoreKit class |
|---|---|---|---|
| Lifetime | `com.fromink.app.plus.lifetime` | Non-consumable IAP | `Product` (StoreKit 2) |
| Yearly | `com.fromink.app.plus.yearly` | Auto-renewable subscription | `Product` with `subscription` field |
| Monthly | `com.fromink.app.plus.monthly` | Auto-renewable subscription | `Product` with `subscription` field |

**Subscription group.** Yearly and monthly belong to a single subscription group named `plus`. This is required for App Store-mediated upgrade/downgrade between the two cadences. Lifetime is *not* in the subscription group — it is a separate non-consumable.

**Trial offer.** Configured in App Store Connect on each subscription product as a 7-day free trial introductory offer. Each user gets the trial on their first subscription to the group (yearly or monthly); switching between yearly and monthly mid-trial does not reset the trial clock.

**StoreKit class to use.** This project ships on iOS 26+, which supports the modern StoreKit 2 `Product` and `Transaction` APIs exclusively. There is no legacy `SKProduct` path to maintain. The StoreKit integration uses `Product.products(for: [...])` to fetch all three products in one call, then renders the paywall with `product.displayPrice` for each tier so currency formatting is correct per locale.

**Pricing in non-USD currencies.** App Store Connect's "Pricing matrix" maps the $19.99 / $14.99 / $2.99 USD tiers to approximate-equivalent prices in each storefront's local currency. The matrix is set once per product; updates ripple to all 175 storefronts.

**Restoring purchases.** `AppStore.sync()` plus `Transaction.currentEntitlements` is the StoreKit 2 pattern. The Restore button on the paywall footer and the Settings → Plan screen both call `AppStore.sync()` and then re-evaluate entitlements; if any are restored, the user is granted access and any paywall surface dismisses.

### 6.1 App Store Connect configuration steps

The following sequence configures all three products + Family Sharing in App Store Connect. Performed once before V1 submission; subsequent changes (price updates, new locales) are isolated edits within the same products.

#### Step 1 — Create the subscription group

The yearly + monthly subscriptions must belong to a single subscription group; this is what enables Apple-mediated upgrade/downgrade between them.

1. App Store Connect → **My Apps** → From Ink → **Monetization** → **Subscriptions**.
2. Click **Create** next to **Subscription Groups**.
3. Reference name: `Plus` (internal-only; not user-facing).
4. Save.

The subscription group is what users see in their iOS Settings → Apple ID → Subscriptions list. Both yearly and monthly will appear under the same group entry there.

#### Step 2 — Create the Yearly subscription

1. From the **Plus** subscription group, click **Create Subscription**.
2. Reference name: `From Ink Plus Yearly`.
3. Product ID: `com.fromink.app.plus.yearly`.
4. Click **Create**.
5. In the subscription detail screen:
   - **Subscription Duration**: 1 Year.
   - **Subscription Prices**: tap **Add Price**, select base price tier corresponding to $14.99 USD. Apple will auto-map equivalent prices for all 175 storefronts; review and adjust if needed.
   - **Localizations**: add a display name and description for each of the nine launch languages (en, fr, de, it, pt-BR, es, zh-Hans, ja, ko). Display name is shown in iOS Settings; description is internal.
   - **App Store Promotion** image: optional, used if the subscription is promoted on the App Store.
   - **Review Information**: screenshot and notes for Apple's review team.
6. **Introductory Offer**: click **Create Introductory Offer**.
   - Type: **Free**.
   - Duration: **1 Week**.
   - Eligibility: **New subscribers** (default; first-time subscribers to this group).
7. **Family Sharing**: scroll to the **Family Sharing** section. Click **Turn On**. Confirm. (See §2.1 — this is a one-way door.)

#### Step 3 — Create the Monthly subscription

Repeat Step 2 with:
- Reference name: `From Ink Plus Monthly`.
- Product ID: `com.fromink.app.plus.monthly`.
- Subscription Duration: **1 Month**.
- Subscription Prices: $2.99 USD base tier.
- Introductory Offer: same as yearly (1 week free).
- Family Sharing: Turn On. Confirm.

#### Step 4 — Create the Lifetime non-consumable IAP

Non-consumable IAPs live in a separate App Store Connect section from subscriptions.

1. App Store Connect → **My Apps** → From Ink → **Monetization** → **In-App Purchases**.
2. Click **Create**.
3. **Type**: **Non-Consumable**.
4. Reference name: `From Ink Plus Lifetime`.
5. Product ID: `com.fromink.app.plus.lifetime`.
6. Click **Create**.
7. In the IAP detail screen:
   - **Price**: $19.99 USD base tier; Apple auto-maps equivalents.
   - **Localizations**: nine languages, same as subscriptions.
   - **Review Information**: screenshot and notes.
8. **Family Sharing**: scroll to the **Family Sharing** section. Click **Turn On**. Confirm. (Same one-way door.)

The official Apple instructions for this toggle live at [Turn on Family Sharing for In-App Purchases](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases/). Apple's UI may evolve; this EDD's step description reflects the structure as of June 2026.

#### Step 5 — Verify all three products are "Ready to Submit"

Each of the three products has a status indicator in App Store Connect:
- 🟡 **Missing Metadata** — required fields empty; fix before submit.
- 🟡 **Developer Action Needed** — usually a missing review screenshot.
- 🟢 **Ready to Submit** — product passes pre-flight; can be attached to a build.

All three products must be **Ready to Submit** before the app build that references them can be submitted for review. Apple reviews IAPs alongside the binary that introduces them; the first build referencing these products triggers their review.

#### Step 6 — StoreKit Configuration file for local development

Apple provides a `.storekit` Configuration file format that lets developers test purchase flows locally without hitting App Store Connect or the sandbox environment. This is the standard pre-integration validation tool.

1. In Xcode: File → New → File → **StoreKit Configuration File**.
2. Name: `FromInk.storekit`. Save at `FromInk/FromInk/` root alongside `Localizable.xcstrings`.
3. Add three products manually with the same product IDs, prices, durations, and trial offers as configured in App Store Connect.
4. Scheme → Edit Scheme → Run → Options → **StoreKit Configuration**: select `FromInk.storekit`.

With the configuration file active, debug builds use simulated StoreKit responses. Production builds (Release configuration) hit real App Store servers regardless of the configuration file setting.

### 6.2 The `SubscriptionService` TCA dependency

`SubscriptionService` is the canonical TCA dependency client following the project's `@DependencyKey` pattern (per CLAUDE.md and the `OCRService` reference example). All reducers that need entitlement information read from this dependency; no reducer touches StoreKit directly.

#### Public types

`Entitlement` is a struct, not an enum, because the same user can have multiple entitlement sources (personal subscription + family-shared lifetime; trial + nothing-else). Flattening into an enum forces a category error where "trial" gets mixed with "tier." The struct keeps tier-ness and ownership-ness separate from "is the user entitled" and "is the trial running":

```swift
struct Entitlement: Equatable, Sendable {
    /// The strongest active source of Plus access this user has right
    /// now. `nil` means no entitlement source is active — the user is
    /// either free (gated to the soft paywall) or trial-active (gated by
    /// TrialState, not by StoreKit). Trial state lives in TrialService,
    /// not here, because the trial is enforced outside StoreKit.
    var source: Source?

    /// If the user has a redundant secondary entitlement (e.g., a
    /// family-shared subscription while they own lifetime personally),
    /// it's recorded here so the Plan screen can surface the redundancy
    /// warning (§7.2). `nil` in the common case.
    var redundantSecondary: Source?

    var hasPlusAccess: Bool { source != nil }

    enum Source: Equatable, Sendable {
        case lifetime(ownership: Ownership, purchaseDate: Date)
        case yearly(ownership: Ownership, state: SubscriptionState)
        case monthly(ownership: Ownership, state: SubscriptionState)
    }
}

enum Ownership: Equatable, Sendable {
    case purchased
    case familyShared
}

enum SubscriptionState: Equatable, Sendable {
    case active(renewsAt: Date)
    case willNotRenew(endsAt: Date)
}

enum PurchaseResult: Equatable, Sendable {
    case success
    case userCancelled
    case pending  // Ask to Buy parental approval, SCA re-auth, etc.
                  // See §6.4 for the design.
}

enum ProductFetchState: Equatable, Sendable {
    case loaded([Product])
    case loading
    case failed(Error)
}

extension ProductFetchState: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.loaded(let l), .loaded(let r)): return l.map(\.id) == r.map(\.id)
        case (.loading, .loading): return true
        case (.failed, .failed): return true
        default: return false
        }
    }
}
```

#### The dependency client struct

```swift
import ComposableArchitecture
import StoreKit

struct SubscriptionService: Sendable {
    /// Current entitlement derived from `Transaction.currentEntitlements`.
    /// Throws on StoreKit errors so callers can distinguish "no entitlement"
    /// from "couldn't determine entitlement" (§6.5 — network failures).
    var currentEntitlement: @Sendable () async throws -> Entitlement

    /// The combined gate check from §2.2. Cached after first call,
    /// invalidated by `transactionUpdates`. Reads `Transaction.all`.
    var canSeeLifetimeOffer: @Sendable () async -> Bool

    /// Cached product list. Fetched once on bootstrap; re-fetched on
    /// network recovery. Paywall renders from this. See §6.5 for the
    /// failure design.
    var products: @Sendable () async -> ProductFetchState

    /// Initiate a purchase. Returns the StoreKit-reported outcome; the
    /// updated entitlement arrives via `transactionUpdates`, NOT via
    /// the return value here. Callers should NOT update their UI based
    /// on the return value's "success" alone — they should observe the
    /// stream.
    var purchase: @Sendable (Product.ID) async throws -> PurchaseResult

    /// Call AppStore.sync() then re-read currentEntitlement.
    var restore: @Sendable () async throws -> Entitlement

    /// AppStore.showManageSubscriptions(in:). Apple's native sheet.
    var manageSubscriptions: @Sendable () async -> Void

    /// Transaction.beginRefundRequest(in:) on the lifetime transaction.
    /// Throws on Apple-reported errors. Refund outcomes (success/failure)
    /// arrive via `transactionUpdates`, NOT via this call.
    var requestLifetimeRefund: @Sendable () async throws -> Void

    /// Long-running stream of entitlement updates. Started at app
    /// launch, never cancelled. Wraps Transaction.updates internally,
    /// re-derives the Entitlement value type, and emits.
    var transactionUpdates: @Sendable () -> AsyncStream<Entitlement>
}

extension SubscriptionService: DependencyKey {
    static let liveValue: SubscriptionService = .live
    static let testValue: SubscriptionService = .test
    static let previewValue: SubscriptionService = .previewLifetime
}

extension DependencyValues {
    var subscriptionService: SubscriptionService {
        get { self[SubscriptionService.self] }
        set { self[SubscriptionService.self] = newValue }
    }
}
```

The `liveValue` reads from `Transaction.currentEntitlements` for the current state and from `Transaction.all` for the gate checks. The `testValue` returns fixture entitlements deterministically so reducer tests can assert state transitions without a real StoreKit harness. The `previewValue` is for SwiftUI previews — multiple flavors (`previewLifetime`, `previewTrial`, `previewFamilyBeneficiary`, `previewNoEntitlement`) can be created as `static let` constants for FeaturePreview conformances.

#### Key invariants

- `Transaction.currentEntitlements` enumerates BOTH the user's own purchases AND family-shared entitlements. The app does not need separate code paths for granting access.
- `Transaction.ownershipType` is the only place the app differentiates `.purchased` from `.familyShared`. Used for the lifetime gate (only `.purchased` counts toward commitment) and for the Plan screen status line ("Yours, forever." vs "Shared by your family.").
- `Transaction.revocationDate` must be checked. When a family member leaves the family group (or any other revocation event), Apple sends a transaction with `revocationDate` set; the app must respect this and revoke access. See §7.6 for the Apple-initiated refund handling that uses the same path.
- `Transaction.updates` is the long-running listener for transactions arriving while the app is running. **Per Apple, this listener must be started at launch and remain active for the app's lifetime.** It catches family members joining mid-session, purchases completing on another device, refunds being processed, and revocations.
- **Refund API name (load-bearing).** The correct StoreKit 2 API is `Transaction.beginRefundRequest(in:)` — an instance method called on a Transaction value, taking a `UIWindowScene`. There is also a static form `Transaction.beginRefundRequest(for:in:)` taking a `Transaction.ID` (a `UInt64` typealias). Neither has the form `AppStore.refundRequestSheet(...)` — that is not a real API. `liveValue.requestLifetimeRefund` resolves the user's current lifetime transaction from `Transaction.currentEntitlements`, then calls `transaction.beginRefundRequest(in: scene)`.

#### Why the `currentEntitlement` derivation is non-trivial

Reading `Transaction.currentEntitlements` returns an `AsyncSequence` of `VerificationResult<Transaction>`. The derivation:

1. Iterate, filtering on `case .verified`.
2. Skip any transaction with `revocationDate != nil`.
3. Group remaining transactions by tier (lifetime / yearly / monthly).
4. Within each group, prefer `.purchased` over `.familyShared` (personal entitlement wins over family-shared if both exist).
5. **Pick the strongest tier as `source`** — lifetime > yearly > monthly. If the user has both a personal subscription AND a family-shared lifetime, lifetime wins.
6. **If there's a secondary tier from a different ownership source**, record it as `redundantSecondary`. This is what the §7.2 mixed-entitlement panel surfaces.

Concretely: a user with personal yearly + family-shared lifetime gets `source = .lifetime(.familyShared, ...)` and `redundantSecondary = .yearly(.purchased, ...)`. The Plan screen knows to render the "your subscription is redundant" warning. See §7.2 and §7.3 for the UI implications.

### 6.3 Pending transactions (Ask to Buy, SCA, parental approval)

`PurchaseResult.pending` fires when StoreKit reports the purchase needs out-of-band approval before the entitlement is granted. The two common causes:

- **Ask to Buy.** A child account on a Family Sharing plan attempts a purchase; the family organizer must approve it via push notification on their own device. Approval can take minutes to days.
- **SCA / payment re-authorization (EU PSD2).** The user's bank requires additional verification before the charge can complete. Usually resolves in seconds via a banking app prompt, but can fail or be abandoned.

**The flow:**

1. User taps Buy / Start free trial. The StoreKit purchase sheet presents.
2. User completes the sheet. StoreKit reports `.pending`.
3. The app dismisses the purchase sheet, returns the user to the surface they came from (paywall, Plan screen, or focused beneficiary upgrade view).
4. A non-blocking toast appears: *"Waiting for approval. We'll let you know."*
5. The `transactionUpdates` AsyncStream continues to fire as it always does. When the eventual entitlement arrives:
   - If the app is foreground: the Plan screen / Home updates silently, a brief confirmation toast appears ("Welcome to Plus.").
   - If the app is background or closed: a local `UNUserNotificationCenter` notification fires with the same copy. This requires no remote push infrastructure; it's a local notification scheduled when `.pending` is received and cancelled when `transactionUpdates` confirms the entitlement.

**Edge case: the pending purchase is rejected.** Ask to Buy organizer declines, SCA fails. StoreKit emits a transaction with no entitlement granted. The `transactionUpdates` stream emits the unchanged entitlement. The app should detect "we were waiting for approval, no approval came" — implemented as a `pendingPurchaseExpectedSince: Date?` field on the relevant feature state, cleared when entitlement arrives or after a 7-day timeout. If the timeout fires without resolution, the in-app toast shifts to *"Your purchase didn't go through. Try again from the paywall."*

**Edge case: the user uninstalls during pending.** The local notification fires regardless of app install state (Apple's notification system holds it). On reinstall, the entitlement arrives via `Transaction.currentEntitlements` at first launch; the welcome-to-Plus toast fires.

For V1, the pending state is rare (Ask to Buy is the realistic case). Implementing the minimum — toast on pending, silent entitlement arrival, local notification fallback — is sufficient. Multi-day timeout handling is V2.

### 6.4 Network failures and product fetch

`Product.products(for: [...])` is a network call. The paywall renders prices from these fetched products; without them, the paywall can't show "$19.99" or "$14.99/yr" at all.

**The failure modes:**

1. **Offline at first launch.** Bootstrap can't fetch products. Paywall has no prices to render.
2. **Apple's StoreKit servers degraded.** Same outcome as #1.
3. **User on metered cellular with data restrictions.** Fetch may stall indefinitely.
4. **Sandbox vs production mismatch during testing.** Easy to mistake for a real failure.

**The design:**

- **`SubscriptionService.products()` returns `ProductFetchState`** — `.loaded([Product])`, `.loading`, or `.failed(Error)`.
- **Bootstrap kicks off the fetch eagerly but does not block routing on it.** The user can complete welcome / value / permissions screens while the fetch is in flight.
- **The paywall renders three states:**
  - `.loaded`: normal display with real prices.
  - `.loading` (still in-flight when paywall renders): a quiet loading state — feature list visible, tier cards show "—" instead of prices, CTA disabled. Auto-resolves when the fetch completes.
  - `.failed`: an inline error message above the tier cards ("Couldn't reach the App Store. [ Try again ]") with a retry button. The CTA stays disabled. No timeout, no panic — the user can dismiss the paywall and revisit later.
- **Day-8 hard paywall with failed product fetch.** This is the worst case: user is locked out, can't render prices. Mitigation: the *gate* (whether the user is entitled) reads from local `Transaction.currentEntitlements` and works offline. Only product *display* requires network. The hard paywall renders the retry affordance and disables the CTA until products arrive; the user is not "bricked" — they can wait, retry, or dismiss the entire app and try later. We do NOT route a user with no entitlement to Home just because StoreKit is unreachable.
- **Stale product cache as a fallback.** On a successful fetch, the product display strings (id, displayName, displayPrice) are cached in `UserDefaults` (small, plain values; not full Product objects). On a failed fetch with no live products, the paywall can render from the cache as a soft fallback — flagging the prices as "may not be current" via a small caption. V2 polish; V1 ships with cleaner "retry needed" behavior.

`Transaction.currentEntitlements` does not require network — it reads the on-device receipt cache. So entitlement evaluation is always available, even when the App Store is unreachable. This is the key invariant: **the app's gating logic never depends on a successful Product fetch**.

### 6.5 Testing Family Sharing in sandbox

Apple's [Testing Family Sharing](https://developer.apple.com/documentation/storekit/testing-family-sharing) doc covers the sandbox setup. Summary:

- Create a **Sandbox Apple ID** at App Store Connect → **Users and Access** → **Sandbox Testers**. Repeat for each family member you want to test with.
- On the test device, sign into iOS Settings → **Developer** → **Sandbox Apple Account** with the organizer's sandbox ID.
- Create a Family group in **Settings → [Sandbox Apple ID] → Family Sharing**, invite the other sandbox testers as family members.
- Run From Ink, purchase the lifetime IAP as the organizer. Verify the purchase succeeds.
- Sign out and sign in on a second device with a family member's sandbox ID. Launch From Ink. The app should detect the family-shared entitlement via `Transaction.currentEntitlements` and unlock access automatically.
- Test revocation: remove the family member from the family group. The next time the app reads entitlements (next launch or next `Transaction.updates` tick), the entitlement should disappear.
- Test the role-flip: as a family member who entered as a beneficiary (their family entitlement still active), navigate to Settings → Plan and use the "Own it yourself for $19.99 →" affordance (§7.3) to buy their own lifetime. The order matters — the beneficiary must upgrade *while still entitled*, because the affordance is only visible to currently-entitled beneficiaries (`canSeeLifetimeOffer && currentEntitlement.source.ownership == .familyShared`). Then have the original organizer cancel their subscription. Verify both users continue to have access — the original organizer is now a beneficiary of the family-shared lifetime that the upgrading family member purchased.
- Test pending-purchase delivery: configure the StoreKit configuration file's `askToBuyEnabled = true`, attempt a purchase, verify the app shows the "Waiting for approval" toast (§6.3) without dismissing the purchase context. Approve via the StoreKit Transaction Manager in Xcode, verify the entitlement arrives via `Transaction.updates` and the welcome toast fires.
- Test network failure on product fetch: enable Network Link Conditioner with 100% packet loss, launch the app, verify the paywall shows the "Couldn't reach the App Store" inline error (§6.4) with retry affordance — and verify that `Transaction.currentEntitlements` still resolves locally without network.
- Test Apple-initiated revocation: in the StoreKit Transaction Manager, manually issue a refund without going through the in-app affordance. Verify `Transaction.updates` fires, the Plan screen reflects the revocation, and the surface explains what happened ("Your purchase was refunded.") per §7.6.

The sandbox doesn't simulate the production "few hours" delay for retroactive Family Sharing activation; sandbox is immediate.

## 7. Plan management surface (Settings → Plan)

Plan management lives in `SettingsFeature → SettingsPlanFeature` as a top-level Settings section. The label is **Plan** (not "Subscription") because lifetime owners and family-shared users are not subscribers — Plan is the neutral umbrella term.

The detail screen renders as a branded overlay per the project's preference for overlays over system sheets (CLAUDE.md / MEMORY.md design rules).

### 7.1 What Apple owns vs what we own

Architecture principle: **we own the launching pad; Apple owns the action UI**. Users almost never leave the app — Apple's StoreKit 2 sheets render inside our scene context.

| Action | Where it happens | API |
|---|---|---|
| Cancel subscription | **Inside our app** via Apple's native sheet | `AppStore.showManageSubscriptions(in:)` |
| Change subscription plan (yearly ↔ monthly) | **Inside our app** via Apple's native sheet | Same as above — Apple's sheet exposes the switch |
| Request lifetime refund | **Inside our app** via Apple's native sheet | `transaction.beginRefundRequest(in:)` (StoreKit 2 instance method) |
| Restore purchases | **Inside our app**, no UI | `AppStore.sync()` + re-read `Transaction.currentEntitlements` |
| View renewal date, billing history | Read from `SubscriptionService`, **rendered by us** | `Transaction.expirationDate`, `Transaction.purchaseDate` |
| Manage Family Sharing membership | **System Settings trip** (no in-app alternative exists) | `UIApplication.shared.open(URL(string: "prefs:root=APPLE_ACCOUNT&path=FAMILY_SHARING"))` |

**What we don't build.** Per the CLAUDE.md "no third-party deps when Apple frameworks cover it" rule applied to UI: we never reimplement Apple's subscription chrome. No custom cancel-subscription form, no custom "are you sure?" confirmation before cancel, no custom refund reason picker, no custom plan-switcher, no custom receipt-history view, no custom "your subscription renews on..." warning modal.

**Subscription upgrade and downgrade asymmetry.** Apple's `showManageSubscriptions` sheet exposes upgrade (monthly → yearly) and downgrade (yearly → monthly) switches within the same subscription group. The user experience differs by direction:

- **Upgrade (monthly → yearly):** Apple charges the prorated difference immediately and the new tier becomes active immediately. `Transaction.updates` fires with the new tier within seconds. The Plan screen reflects the new tier on next tick.
- **Downgrade (yearly → monthly):** Deferred to end of current period. No proration, no immediate charge. The user keeps yearly access through their paid period. `Product.SubscriptionInfo.RenewalState == .willNotRenew` is set with the *current* yearly tier, and `Product.SubscriptionInfo.RenewalInfo.willAutoRenew` reflects the pending switch to monthly. The Plan screen's status line shows "Yearly · Ends [date] → Monthly thereafter."

Both directions must render correctly. The state matrix (§7.2) treats the downgrade-pending state as a variant of "cancellation scheduled" with a follow-on tier rather than a true cancellation.

### 7.2 The Plan screen states

The Plan screen's plan name, status line, and action buttons are derived from the `Entitlement` value (see §6.2). The complete matrix has nine reachable states. State numbering corresponds to `Entitlement.source` plus trial state plus the gate check (§2.2).

| # | Condition | Plan name | Status line | Buttons shown |
|---|---|---|---|---|
| 1 | **Lifetime, purchased, within 14-day refund window** | Lifetime | "Yours, forever." + transparency line "Purchased [date] · N days left to change your mind" | Restore Purchases, Request Refund ↗ |
| 2 | **Lifetime, purchased, beyond 14-day window** | Lifetime | "Yours, forever." | Restore Purchases |
| 3 | **Lifetime, family-shared** | Lifetime | "Shared by your family." | Manage Family Sharing ↗, Restore Purchases; conditionally **Own it yourself for $19.99 →** if `canSeeLifetimeOffer` is true |
| 4 | **Yearly, active, auto-renewing** | Yearly | "Renews [date] for $14.99." | Manage Subscription ↗, Restore Purchases |
| 5 | **Yearly, cancellation scheduled** | Yearly | "Ends [date]." (or "Ends [date] → Monthly thereafter." if a downgrade is pending per §7.1) | Manage Subscription ↗, Restore Purchases |
| 6 | **Monthly, active or cancelling** | Monthly | "Renews [date] for $2.99." / "Ends [date]." | Manage Subscription ↗, Restore Purchases |
| 7 | **Subscription, family-shared** | Yearly / Monthly | "Shared by your family. Renews [date]." | Manage Family Sharing ↗, Restore Purchases; conditionally **Own it yourself for $19.99 →** if `canSeeLifetimeOffer` is true |
| 8 | **Lapsed, post-refund, or Apple-revoked** (no entitlement, accessed via §8 routing that doesn't immediately route to hard paywall — e.g. the post-revocation explanation flow in §7.6) | Free | "Your subscription ended [date]." / "Your purchase was refunded [date]." / "Your access was revoked." | See Plans → (routes to paywall — 3-card or 2-card based on `canSeeLifetimeOffer`), Restore Purchases |
| 9 | **In-app trial active** | Free trial | "[N] days left in your trial." | See Plans → (routes to soft paywall), Restore Purchases |

Renewal and end dates are sourced from `Transaction.expirationDate` for auto-renewable subscriptions. Cancellation-scheduled state is detected via `Product.SubscriptionInfo.RenewalState == .willNotRenew`. The downgrade-pending variant on state 5 is detected when `RenewalInfo.willAutoRenew` is true but for a different product than the current tier.

**State 8 reachability.** State 8 is only reachable when the routing in §8.2 has explicitly chosen to present the Plan screen rather than the hard paywall — e.g. immediately after an Apple-initiated revocation (§7.6) where the app surfaces an explanation before routing the user to the next decision moment. The hard paywall flow itself does NOT permit Settings access; users are not stranded on a free Plan screen with no entitlement. State 8 exists for the brief explanatory moment, not as a permanent free-tier state.

**State 9 (trial-active) replaces what a permanent free tier would have been.** The in-app trial is the only "no entitlement, but full Plus access" state. Once the trial expires, the user routes to the hard paywall (§8.4), not to a degraded Plan screen.

#### Mixed entitlement (overlay variant)

When `Entitlement.redundantSecondary != nil` — the user has both a primary entitlement source AND a redundant secondary source from a different ownership path — the Plan screen renders a redundancy warning above the standard action list. The warning copy and CTA depend on *which side is the user's bill*:

**Case A: personal subscription + family-shared lifetime.** The user is paying for the subscription; the lifetime is a freebie via family. Their subscription is now redundant — the family-shared lifetime would cover them. Surface on this user's Plan screen:

```
┌────────────────────────────────────┐
│  YOUR PLAN                         │
│                                    │
│  Lifetime                          │
│  Shared by your family.            │
│                                    │
│  ─────────────                     │
│                                    │
│  ⚠ You're also paying for a        │
│    yearly subscription. Since      │
│    your family now has lifetime,   │
│    your subscription is redundant. │
│    Cancel it so you're not         │
│    double-billed.                  │
│    [ Cancel subscription ↗ ]       │
│                                    │
│  ─────────────                     │
│                                    │
│  [ Manage Subscription ↗ ]         │
│  [ Manage Family Sharing ↗ ]       │
│  [ Restore Purchases ]             │
│                                    │
│  ─────────────                     │
│  Privacy   Terms                   │
└────────────────────────────────────┘
```

**Case B: personal lifetime + family-shared subscription.** The user purchased lifetime; they're also a beneficiary of someone else's subscription (e.g., they did the beneficiary upgrade per §7.3 before the original payer cancelled). Their personal lifetime is the strongest source; the family-shared subscription is "free" to them. **No redundancy warning is shown** — the user isn't double-paying anything; their lifetime is their bill, the subscription is someone else's bill. The Plan screen renders state 1 or 2 normally with a small informational line noting "Your family also has a yearly subscription" — no warning chrome, no CTA. The original payer (whose Plan screen is Case A) sees the warning on their side.

The decision rule: **the redundancy warning appears only on the side that's actively paying for the redundant product.** Implementation: check `redundantSecondary?.ownership == .purchased` — only render the warning if the redundant secondary source is the user's personal purchase.

The warning auto-dismisses once the user cancels the redundant subscription and `Transaction.updates` reports it. The user is never billed silently for both products without seeing this warning.

### 7.3 Beneficiary upgrade path

Family-shared beneficiaries — users currently entitled via `.familyShared` ownership — can upgrade to their own lifetime via an in-app focused purchase view. This serves two scenarios:

- **"I love this so much I want to own it myself."** Beneficiary commits to their own lifetime while still receiving family-shared access. After purchase, their personal lifetime is now family-shareable too; if the original payer ever cancels their subscription, the family group retains access via the beneficiary's lifetime.
- **Defensive ownership.** Beneficiary worried the organizer might cancel, leave the family, etc. Buying their own lifetime locks in access independent of the organizer's decisions.

**Visibility logic:**

```swift
func showBeneficiaryUpgrade(entitlement: Entitlement, canSeeLifetime: Bool) -> Bool {
    // The user must currently be entitled via family sharing (not their
    // own purchase), and they must pass the lifetime gate (have never
    // personally committed to anything).
    guard let source = entitlement.source else { return false }
    switch source {
    case .lifetime(.familyShared, _),
         .yearly(.familyShared, _),
         .monthly(.familyShared, _):
        return canSeeLifetime
    case .lifetime(.purchased, _),
         .yearly(.purchased, _),
         .monthly(.purchased, _):
        return false
    }
}
```

**Layout:** an additional "Own it yourself for $19.99 →" button appears in the Plan screen action list for states 3 and 7 when `showBeneficiaryUpgrade` returns true.

**Focused purchase view:** tapping the button opens a single-card lifetime purchase view (not the full 3-card paywall — the user is already entitled, they don't need the comparison shopping). Body copy specifically for this surface:

> Make From Ink yours.
> A one-time purchase. Yours, on every device you own — and your family stays covered too.
> $19.99 · 14 days to change your mind.

The "your family stays covered too" line is the specific value proposition: the beneficiary isn't abandoning their family by buying their own; their purchase becomes a family entitlement source. The role flips, but no one in the family loses access.

**Post-upgrade state for the beneficiary.** Once the lifetime purchase completes, the beneficiary's `Transaction.currentEntitlements` returns both their newly-purchased personal lifetime AND the still-active family-shared subscription from the original payer. Per the §6.2 entitlement derivation, this resolves to:

- `source = .lifetime(.purchased, purchaseDate: <today>)` — the strongest source, their personal lifetime
- `redundantSecondary = .yearly(.familyShared, ...)` (or monthly, depending on the original payer's tier)

The Plan screen renders **state 1 or 2** (depending on whether they're inside the 14-day refund window). Per §7.2 Case B above, **no redundancy warning is shown to the beneficiary** — they aren't paying for the family-shared subscription; that's the original payer's bill. A small informational line ("Your family also has a yearly subscription.") appears below the status line but with no warning chrome and no CTA.

**Post-upgrade state for the original payer.** Their `Transaction.currentEntitlements` now includes their personal subscription AND the family-shared lifetime that the beneficiary just purchased. Per §6.2:

- `source = .lifetime(.familyShared, ...)` — lifetime beats subscription as the strongest source
- `redundantSecondary = .yearly(.purchased, ...)` (or monthly)

Their Plan screen renders **state 3** with the §7.2 Case A redundancy warning — they ARE paying for the redundant subscription, and they should cancel it to avoid double-billing.

**After the original payer cancels their subscription.** The yearly/monthly subscription expires at end of period. Both users' `Transaction.currentEntitlements` returns just the family-shared lifetime (for the original payer) or the personal lifetime (for the beneficiary). The redundancy warning auto-dismisses on the original payer's Plan screen. Both users continue to have access.

This is the role-flip mechanic working end-to-end: the beneficiary became the payer, the payer became the beneficiary, neither loses access at any moment in the transition.

### 7.4 In-app refund affordance (lifetime, 14-day window)

Visibility:

```swift
func showInAppRefundButton(entitlement: Entitlement, cal: CalendarContext) -> Bool {
    guard let source = entitlement.source else { return false }
    guard case .lifetime(let ownership, let purchaseDate) = source else { return false }
    guard case .purchased = ownership else { return false }
        // family-shared lifetime — they didn't pay, no refund affordance for them
    guard let cutoff = cal.calendar.date(byAdding: .day, value: 14, to: purchaseDate) else {
        return false
    }
    return cal.now() < cutoff
}
```

The cutoff is computed via `Calendar.date(byAdding: .day, value: 14, to:)` rather than `purchaseDate + 14 * 86400` — DST-safe and timezone-correct per the dates EDD. Bare seconds-per-day math is banned in this project; using it here would expire the refund window an hour early or late twice a year.

Three conditions must all hold:
1. The user's entitlement source is lifetime
2. They personally purchased it (not family-shared — they didn't pay, so they can't refund)
3. Today is before the 14-day cutoff date

When all three hold, the "Request Refund ↗" button appears in the Plan screen action list. Tap routes to `transaction.beginRefundRequest(in: scene)` — Apple's native refund sheet renders inside our scene context. `transaction` here is the lifetime transaction resolved from `Transaction.currentEntitlements`; `scene` is the active `UIWindowScene`. The function returns `RefundRequestStatus.success` (the user submitted the request) or `.userCancelled` (the user dismissed the sheet without submitting). Submission does not mean approval — Apple processes the request asynchronously.

> **API correctness note.** The refund API is `Transaction.beginRefundRequest(in:)` (instance method) or `Transaction.beginRefundRequest(for: UInt64, in: UIWindowScene)` (static method taking a transaction ID). There is NO API named `AppStore.refundRequestSheet(...)` — references to that name elsewhere should be considered errors.

After 14 days the button quietly disappears. No countdown panic, no "last chance" upsell-in-reverse. The window closed; the door is shut. Users beyond the 14-day window can still go through Apple's standard 90-day refund process via system Settings → Apple ID → Purchase History → Report a Problem, but we make no in-app surface for it — they're outside our brand commitment window.

After a successful refund: `Transaction.updates` fires with `revocationDate` set; `SubscriptionService` re-evaluates entitlements and reports the user is no longer entitled. `hasEverEngagedWithLifetime` remains true (the engagement happened). The user is routed to the day-8 hard paywall on next launch — but first sees the §7.6 explanation surface.

### 7.5 The "we won't push back" copy commitment

The Plan screen surfaces the 14-day window via a soft transparency line on the lifetime state (state 1):

> Purchased [date] · 9 days left to change your mind

The line uses the user-facing brand commitment vocabulary established in §3.2. No bold, no warning chrome — just a quiet status indicator. The user sees their window clearly without being pressured.

After day 14, the line disappears along with the Request Refund button. The Plan screen for a lifetime owner past the window is the most minimal state of all (just plan name, status line, and Restore Purchases).

### 7.6 Apple-initiated revocations (chargebacks, fraud, mass refunds)

Apple can revoke a transaction without the user pressing Request Refund. The common causes:

- **Chargeback.** The user disputes the charge with their credit card issuer; the bank reverses the charge; Apple revokes the entitlement.
- **Fraud detection.** Apple's fraud systems identify a suspicious purchase; the transaction is revoked regardless of the user's intent.
- **Mass refund event.** Apple processes a sweep (e.g. App Store outage compensation, regional regulatory action) that revokes a batch of transactions.
- **Family Sharing removal.** A family member is removed from the family group; their family-shared entitlement revokes. Handled via the same path even though it isn't strictly a "refund."

In all these cases, `Transaction.updates` fires with `revocationDate` set, and the `revocationReason` may indicate the cause:

- `.developerIssue` (1)
- `.other` (0)
- `nil` for non-revoking transactions

**The UX response:**

1. On `Transaction.updates` firing with a revocation, the `SubscriptionService` re-evaluates the entitlement (now likely `source = nil`).
2. The bootstrap routing (§8.2) detects the change. If the user is currently in the app, they are NOT immediately kicked to the hard paywall — that would feel like the app crashed at them.
3. Instead, the app navigates to **Plan screen state 8** with an explanatory status line:
   - For revocation from a personal lifetime purchase: "Your purchase was refunded [date]."
   - For revocation from a personal subscription: "Your subscription ended [date]."
   - For revocation from a family-shared entitlement: "Your family member's access ended [date]."
4. The user reads the explanation, has time to absorb the change. They have the option to **See Plans →** (which routes to the paywall, with lifetime visibility per `canSeeLifetimeOffer`) or **Restore Purchases** (which retries `AppStore.sync()` in case the revocation was a sync error).
5. If the user dismisses or navigates away from the Plan screen without resolving, the next app launch routes through the standard §8.2 logic — which will route them to the hard paywall if they're still un-entitled and out of trial.

This is the one path where state 8 (§7.2) is the right surface: a brief, explanatory pause between the Apple-initiated change and the user's next decision. It's not a permanent state; it's the "what just happened" moment.

**Local notification on backgrounded revocation.** If the revocation arrives while the app is in the background or closed, the user's next launch sees the Plan screen explanation surface as their first stop (instead of Home). No remote push needed — the routing logic detects "user was entitled at last launch, currently not entitled, last seen explanation was different" and prioritizes the explanation surface.

## 8. Onboarding decision tree

The bootstrap routing at app launch determines which surface the user sees. The decision is a pure function of: current entitlement, trial state, and the lifetime gate.

### 8.1 The five terminal states

```
                     App launch / onboarding entry
                                │
                                ▼
                  currentEntitlement?
                ┌───────────────┴───────────────┐
            active                            none
                │                               │
                ▼                               ▼
        Entitled —                        trialState?
        route to                  ┌────────────┼────────────┐
        Home as Plus              ▼            ▼            ▼
                             .notStarted   .active     .expired
                                  │            │            │
                                  ▼            ▼            ▼
                          Soft paywall    Trial-entitled  Hard paywall
                          (3 cards if     route to Home   (no dismiss)
                           canSee, else                   3 cards if canSee,
                           2 cards; can                   else 2 cards
                           dismiss → trial
                           starts)
```

The five terminal states are:

1. **Home as Plus (entitled).** User has an active `Transaction.currentEntitlements` result. Skip everything, go straight to Home.
2. **Home as Plus (trial-entitled).** Trial is active, no purchase yet. Full Plus features unlocked, trial countdown indicator visible in Settings → Plan.
3. **Soft paywall.** First-time user landing on the onboarding paywall. Dismissable; dismissing starts the 7-day trial.
4. **Hard paywall (day-8).** Trial expired without purchase. Modal cannot be dismissed. User must pick a plan.
5. **Welcome from family.** Family-shared beneficiary on first launch. Brief acknowledgment screen, then Home as Plus.

### 8.2 First-launch routing pseudocode

The routing logic must enforce §4.4's "no chaining" invariant: a user who has already consumed any try-before-buy window (started a subscription trial, bought lifetime, or finished the in-app trial) cannot get back to the soft paywall — they go straight to the hard paywall. The check `canSeeLifetimeOffer` doubles as "has the user made any commitment yet" (its inverse is `hasEverEngagedWithLifetime || hasEverPersonallySubscribed`, which captures both engagement paths).

```swift
func decideRoute() async throws -> Route {
    let entitlement = try await subscriptionService.currentEntitlement()

    // States 1 and 5 — entitled users (purchased or family-shared)
    if entitlement.hasPlusAccess {
        let isFirstLaunchAsFamilyBeneficiary =
            entitlement.isFamilyShared
            && !UserDefaults.standard.bool(forKey: "hasSeenFamilyWelcome")
        return isFirstLaunchAsFamilyBeneficiary
            ? .welcomeFromFamily
            : .home
    }

    // Apple-initiated revocation detection (§7.6): if the user was
    // entitled at last launch but isn't now, and we haven't yet shown
    // the explanation surface, route to Plan screen state 8 first.
    if shouldShowRevocationExplanation() {
        return .planScreenExplanation
    }

    let trialState = await trialService.state()
    let canSeeLifetime = await subscriptionService.canSeeLifetimeOffer()
    let hasCommittedBefore = !canSeeLifetime
        // canSeeLifetime is false iff the user has already engaged with
        // lifetime (purchase or refund) OR personally subscribed. Either
        // commitment closes the door on a "fresh" soft paywall.

    switch trialState {
    case .notStarted where hasCommittedBefore:
        // Loophole closure (§4.4): user cancelled an Apple subscription
        // trial before ever dismissing the soft paywall. They've
        // already had their try-before-buy window via Apple's trial.
        // Send them to the hard paywall, no fresh in-app trial.
        return .hardPaywall(includeLifetime: false)

    case .notStarted:
        // State 3 — fresh user, first time seeing the paywall.
        return .softPaywall(includeLifetime: canSeeLifetime)

    case .active:
        // State 2 — in-app trial in progress, full Plus access.
        return .home

    case .expired:
        // State 4 — day-8 hard paywall.
        return .hardPaywall(includeLifetime: canSeeLifetime)
    }
}
```

The `canSeeLifetimeOffer` check (§2.2) decides whether the paywall renders in 3-card or 2-card mode. The decision is per-user, persists across sessions via `Transaction.all`, and is independent of trial state.

`shouldShowRevocationExplanation()` is a transient flag set by `Transaction.updates` when a revocation arrives and cleared once the explanation surface is shown. Implemented as a single `UserDefaults` value: `pendingRevocationExplanationFor: Transaction.ID?`.

The `trialState == .notStarted && hasCommittedBefore` branch closes the §4.4 chaining loophole. Without it, a user who started a yearly trial and cancelled before billing would land on the soft paywall on next launch, dismiss it, and start a fresh 7-day in-app trial — effectively chaining a 7-day trial onto an Apple-mediated trial they already abandoned. With it, that user is routed straight to the hard paywall.

If the current `Entitlement` cannot be determined because `Product.products(for:)` failed or `Transaction.currentEntitlements` errored (§6.4 — network failure), the bootstrap fallback is **conservative**: treat the user as having no entitlement, render the soft paywall with the network-failure inline error from §6.4. Do NOT short-circuit to Home — that would grant entitlement on the basis of a failed read.

### 8.3 Trial state initialization

`TrialState.startedAt` is set exactly once, at a deliberate moment: **when the user dismisses the soft paywall.** Not at first app launch, not at onboarding start — at the explicit "I don't want to commit yet" decision.

```swift
case .paywallDismissed:
    return .run { _ in
        let state = TrialState(startedAt: calendarContext.now())
        try await trialService.start(state)
    }
```

This means a user who completes the full onboarding flow (welcome → value → permissions → paywall) and then dismisses the paywall has their trial start at that moment. Their 7 days begin from the dismissal, not from install.

A user who picks a plan at the paywall never starts the trial — their entitlement supersedes it.

### 8.4 The day-8 hard paywall

When the trial state is `.expired` and there's no active entitlement, the routing logic presents the hard paywall. Visually identical to the onboarding paywall (same `OnboardingSubscriptionView` Model), but with two important differences:

1. **No dismiss affordance.** The X close button is suppressed. The user cannot close the paywall without picking a plan.
2. **Background app state is locked.** No part of the app's content surface is accessible behind the paywall. Settings is reachable from the paywall footer for Restore Purchases only.

The headline shifts to acknowledge the trial transition:

> Your 7 days are up.
> Pick the way you want to keep going.

No drama, no "limited time offer" pressure. Just the menu.

### 8.5 The welcome-from-family screen

A user opening From Ink for the first time who has a `.familyShared` entitlement skips the paywall and trial entirely. Before landing on Home, they see a one-time acknowledgment screen:

```
                       FROM INK

         Welcome.
         Your family shared this with you.

                  [ Continue → ]
```

One screen, one tap, never shown again on this device (gated by `UserDefaults.bool(forKey: "hasSeenFamilyWelcome")`). It's not a paywall, not a pitch — a human moment that explains why they're seeing the full app without paying.

**Per-device, not per-account.** `UserDefaults` is device-scoped, so a family beneficiary installing on both iPad and iPhone sees the welcome on each device once. This is acceptable — the welcome moment is brief and explanatory, not an annoyance worth solving with iCloud KVS sync for this single flag. The trial state's iCloud KVS persistence (§2.3) is load-bearing because trial duration is a load-bearing entitlement decision; the welcome flag is cosmetic.

### 8.6 Returning user scenarios

Users who reinstall the app after a prior install hit different routes depending on their entitlement and gate history:

| Prior state | Current state on reinstall | Route |
|---|---|---|
| Subscribed and cancelled, sub expired | No active entitlement, `hasEverPersonallySubscribed == true` | 2-card hard paywall (lifetime gate closed) |
| Bought lifetime, refunded | No active entitlement, `hasEverEngagedWithLifetime == true` | 2-card hard paywall (lifetime gate closed) |
| Bought lifetime, never refunded | Active lifetime entitlement (restored via Apple ID) | Home as Plus |
| Never paid, never trialed (uninstalled before completing onboarding) | No active entitlement, `trialState == .notStarted` | Soft paywall (3-card if `canSeeLifetimeOffer`) — they get a fresh trial if they dismiss |
| Trial expired, never bought | No active entitlement, `trialState == .expired` | Hard paywall (3-card if `canSeeLifetimeOffer`, else 2-card) |
| Currently subscribed | Active subscription entitlement | Home as Plus |
| Family beneficiary (organizer hasn't cancelled) | Active family-shared entitlement | Home as Plus (welcome-from-family if first time on this device) |

The trial state persists via iCloud KVS so it survives uninstall. A user who started a trial on iPad, uninstalled, then reinstalled on iPhone sees the same trial state — they don't get a fresh trial just by switching devices.

## 9. Restore Purchases, Privacy, Terms — required affordances

Apple's App Store Review Guidelines require three affordances visible at the point of purchase:

1. **Restore Purchases** — for users who previously purchased on another device or under another Apple ID. Must be accessible without first creating an account or providing any other input.
2. **Privacy Policy** — link to the published privacy policy. Apple requires this for any app that handles user data; From Ink handles user data (notes, handwriting, calendar events) extensively.
3. **Terms of Service** — link to the published terms of service. Apple requires this for any app with subscriptions.

These three live in the paywall's legal-chrome footer row, rendered as small mono uppercase tap targets below the primary CTA. The component is `OnboardingLegalChrome`, also reused in Settings → Plan. Each tap target carries its own action — the wiring view routes Restore through `SubscriptionService.restore`, and Privacy / Terms through `UIApplication.shared.open(URL)` to the respective URLs.

**URLs are TBD.** Pre-V1 launch action item: publish the Privacy Policy and Terms of Service at stable URLs and wire them into the chrome's action handlers. The current code path has no-op actions in the placeholder configuration.

## 10. Apple guideline compliance

The pricing model and IAP configuration are evaluated against the relevant Apple guidelines.

| Guideline | How From Ink complies |
|---|---|
| **3.1.1 — In-App Purchase** | Non-consumable (lifetime) and auto-renewable subscriptions (yearly, monthly) are both standard IAP types. Apple has approved thousands of apps using exactly this combination. |
| **3.1.2 — Subscriptions** | The two subscription tiers provide ongoing value (full app access for the duration). Auto-renewal terms are clearly disclosed. Trial duration is clearly stated. Restore Purchases is provided. Privacy and Terms links are visible at the point of purchase. |
| **3.1.2(a) — Subscription Information** | The paywall includes: subscription length (yearly / monthly), price per period, auto-renewal disclosure, free trial length, link to Terms, link to Privacy Policy, Restore Purchases affordance. All of these must be visible before the user taps the primary CTA. |
| **3.1.3 — "Reader" Apps** | Not applicable. From Ink does not qualify as a "Reader" app. |
| **3.1.5(a) — Goods and Services Outside of the App** | Not applicable. From Ink's IAPs unlock features within the app itself, not external goods or services. |
| **Trial mechanic without Apple ID commitment** | Apple permits developer-managed trials that don't require StoreKit-mediated subscription intro offers. Pattern is well-precedented (Day One, Habitify, dozens of indie apps). The 7-day in-app trial is compliant. |

**Lifetime-specific copy compliance.** The word "subscription" must not appear in copy that describes the lifetime tier (lifetime is a one-time purchase, not a subscription). "Pay once," "yours forever," "lifetime access," and "one-time purchase" are all compliant. "Lifetime subscription" is non-compliant and confusing. The current copy uses "Pay once. Yours, forever." which is compliant.

**"Lifetime" definition for legal purposes.** Internally and in user-facing fine print, "lifetime" is defined as "for as long as the app remains available on the App Store under the same ownership." This bounded definition avoids ambiguity about whether "lifetime" means the user's lifetime, the device's lifetime, the company's lifetime, or some other timeline. The bounded definition is the industry norm and matches Apple's expectation for non-consumable IAPs.

**14-day refund commitment copy compliance.** The phrase "we won't push back" must be the user-facing language — not "guaranteed refund" or "money-back guarantee." Apple owns the refund decision; making a guarantee on Apple's behalf is non-compliant. "We won't push back" accurately describes our procedural commitment without overstating it.

## 11. Localization

The paywall is one of the most carefully localized surfaces in the app — its copy is load-bearing for both conversion and brand. All strings flow through the localization architecture described in `localization_edd.md`.

| String | Translation notes |
|---|---|
| Kicker: "From Ink Plus" | **Not translated.** Per glossary §3.2 of the localization EDD, "From Ink" and "From Ink Plus" pass through verbatim in all languages, in Latin script. |
| Headline: "Pay once. Yours, forever." | **Most carefully translated string on the paywall.** The two-tone effect (declarative + emotive) must survive the translation. The translator's brief explicitly calls out the rhythmic break between the two sentences. JP/KO contractions of the English structure are expected. |
| Lifetime card body, 4 lines | Translated. Lines 3 and 4 ("No subscription." / "14 days to change your mind.") must preserve their terseness even if the target language tends toward longer phrasing. |
| Constraint caption: "This offer ends the moment you subscribe." | Translated. Italic style on the cap; mono character family. |
| 2-card mode headline: "Try free for 7 days, then your pick of plan." | New for V1. Translated. |
| Day-8 hard paywall headline: "Your 7 days are up. Pick the way you want to keep going." | New for V1. Two sentences; preserve the calm, declarative register. |
| Connector: "or, try free for 7 days" | Translated. The lower-case "or" is intentional in English and may need locale-specific capitalization in target languages. |
| Subscription card prices and units | Currency formatting handled at runtime by `Product.displayPrice` per StoreKit 2; the surrounding chrome strings (yearly, monthly, "about $1.25/mo") are translated. |
| Feature list, 9 rows | Same translation budget as the rest of `AppStrings.Onboarding`. Per `localization_edd.md` §3.2, terms like "iCloud" and "PDF" pass through verbatim. |
| CTA labels (2 variants) | Translated. Each variant ("Buy →", "Start free trial →") is its own key. |
| Legal chrome ("Restore", "Privacy", "Terms") | Translated. These are short labels; the translator's brief calls out their function as legal-chrome affordances so the translation matches platform convention in the target language. |
| Settings → Plan status lines (8 variants) | New for V1. Translated. Date placeholders use `Date.FormatStyle` per the dates EDD; no hand-rolled formatters. |
| "We won't push back" refund copy | Translated. The specific procedural phrasing is brand-load-bearing; the translator's brief flags it. |
| "Own it yourself for $19.99 →" beneficiary upgrade CTA | New for V1. Translated. Currency formatting at runtime. |
| Welcome-from-family screen | New for V1. Two short sentences ("Welcome." / "Your family shared this with you."). Preserve the brevity. |
| Trial countdown lines: "N days left in your trial.", "Purchased [date] · N days left to change your mind", "[N] days left" Home chrome line | Pluralization-sensitive. English has two forms (1 day / N days); Russian and Polish have three (1, 2-4, 5+); Arabic has six. **All count-dependent strings must use `String.LocalizationValue` with `.stringsdict` plural rule entries** rather than a single `NSLocalizedString` key, so each locale resolves the right form. The localization EDD's tooling pass should generate stringsdict entries from each marked plural key. |

### 11.1 Plural rule generation

Strings that vary by count are NOT handled by simple `NSLocalizedString` — that mechanism does not pick a plural form based on a runtime number. The correct pattern in iOS 15+ is `String.LocalizationValue` with stringsdict-style plural rules. For each plural-sensitive string in the table above:

1. Author the English source as a `String.LocalizationValue` interpolation, e.g. `"\(daysLeft) day(s) left in your trial"` — the `(s)` is a translator hint, not output.
2. Generate a stringsdict entry per target language with the appropriate `NSStringPluralRuleType` mappings: `one`, `few`, `many`, `other` etc. per CLDR.
3. The translator's brief for each plural key includes a concrete example for `count = 1`, `count = 2`, and `count = 5` so the translator can verify their plural form rules.

The localization EDD `localization_edd.md` Batch 1 phase explicitly includes a stringsdict generation step for the subscription domain. Without this, the trial countdown copy is broken in every non-English locale at the moment of highest user attention (days 6 and 7).

Phase 1 of the localization rollout (`localization_edd.md` §12 Batch 1) ships the paywall in all nine launch languages alongside the rest of the onboarding domain.

## 12. Open questions

| # | Question | Impact |
|---|---|---|
| 1 | Privacy Policy URL — where will it be published, and when? | Blocks the paywall footer's `Privacy` action from doing real work. Pre-V1 must-have. |
| 2 | Terms of Service URL — where will it be published, and when? | Same as above. |
| 3 | When does StoreKit integration land? | The paywall is currently UI-only with placeholder display strings. StoreKit integration converts the placeholder display into actual product fetching, paywall tap → purchase flow, Restore Purchases wiring, transaction validation, gate detection (§2.2), trial state persistence (§2.3), and Plan management (§7). |
| 4 | Should the paywall be tested with `Configuration.storekit` files in the test target before the live App Store Connect SKUs are configured? | Yes — StoreKit testing in Xcode is the standard pre-integration validation. Should be set up alongside StoreKit integration work. |
| 5 | Will From Ink Plus offer a referral program (existing user invites friend, both get a discount or extended trial)? | Strategic. Not in the V1 launch scope. If yes later, the Pro tier disclosure (§3.1) and the StoreKit configuration need a referral SKU lane. |
| 6 | When a future Pro tier is introduced, what entitlement model gates Pro from Plus? | Open. Two patterns: (a) Pro is a separate auto-renewable subscription, lifetime Plus customers can additionally subscribe to Pro for the Pro features. (b) Pro features are a separate non-consumable that unlocks on top of Plus entitlement. Decision deferred; this EDD will be amended when Pro is on the roadmap. |
| 7 | StoreKit specialist code review before launch — yes/no? | Recommended (Option 2 from the V1 build discussion). 2–3 hours of senior contractor time, ~$500–$1500, reviewing the Plan state machine, Family Sharing handling, the lifetime gate detection (§2.2), and the §6.3/§6.4 edge case handling. Catches edge cases the internal team would miss. |
| 8 | Privacy Policy and Terms of Service authoring — who drafts the 14-day "we won't push back" clause (§3.2)? | The clause is brand-load-bearing legal text. Engineering can draft a first pass; legal review is required before the Terms URL goes live. The clause text needs to match the user-facing copy on the lifetime card and Plan screen. |
| 9 | Pre-expiration re-engagement notification for lapsing subscribers — V1 or V2? | The §7.4 of the old EDD mentioned a 7-day-before-expiration banner for subscribers. Currently V2 because the scheduling mechanism (background app refresh or local notification) is not in V1 scope. Decision needed: ship a simple local-notification reminder at V1, or defer. |
| 10 | Stale product cache fallback (§6.4) — V1 or V2? | Currently spec'd as V2 polish. The V1 paywall failure mode is "retry needed" with no cached prices. If the App Store has frequent regional outages during launch period, the cache fallback may become V1-required. Decision deferred until launch testing. |

Closed since the previous EDD version:

- ~~"Cancellation grace policy for users who tap Restore with no entitlements"~~ — resolved. Standard behavior: dismiss the surface that triggered Restore, present a non-blocking toast. Specified in §7.1 implicitly.
- ~~"Founder's pricing"~~ — rejected at this design pass; the $19.99 / $14.99 ratio is already compelling.
- ~~"Free tier floor"~~ — resolved by removing the free tier entirely (§1, §2.3).
- ~~"Family Sharing redundancy disambiguation"~~ — resolved with the §7.2 mixed-entitlement variant. Both Case A (warning shown) and Case B (no warning, informational only) are spec'd.
- ~~"Receipt validation strategy"~~ — resolved. On-device `VerificationResult` is sufficient for V1; no server component planned.
- ~~"Pending purchases (Ask to Buy / SCA)"~~ — resolved in §6.3.
- ~~"Network failures and product fetch"~~ — resolved in §6.4.
- ~~"In-app trial countdown surfacing"~~ — resolved in §2.3 (Home chrome line on days 5–7, optional day-7 local notification).
- ~~"Apple-initiated revocations and chargebacks"~~ — resolved in §7.6.
- ~~"Subscription upgrade/downgrade UX"~~ — resolved in §7.1 (downgrade pending state in matrix §7.2 row 5).
- ~~"Welcome-from-family per-device vs per-account"~~ — resolved in §8.5 (per-device, intentional).
- ~~"`SubscriptionService` TCA dependency pattern"~~ — resolved in §6.2 (full `@DependencyKey` conformance, three dependency flavors).
- ~~"Refund API name correctness"~~ — resolved. `Transaction.beginRefundRequest(in:)` is the correct API; `AppStore.refundRequestSheet(...)` does not exist.
- ~~"No-chaining enforcement in routing"~~ — resolved in §8.2 with the `trialState == .notStarted && hasCommittedBefore` branch.
- ~~"Lifetime gate code correctness"~~ — resolved in §2.2 (async functions, correct iteration semantics).
- ~~"Date math safety for refund window"~~ — resolved in §7.4 (`Calendar.date(byAdding:value:to:)` instead of raw seconds).
- ~~"Server-side App Store Server Notifications"~~ — explicitly deferred. V1 relies solely on `Transaction.updates`. If a backend is ever introduced, server-to-server notifications become available; for V1 the local listener is sufficient with acknowledged latency tradeoffs (state changes that happen with the app closed are picked up at next launch, not immediately).

## 13. Cross-references

### Internal documents

- `localization_edd.md` — §3 language list, §3.1 style guide, §3.2 glossary, §6.4 "selling FM-gated features in paywalls"; §12 migration plan Batch 1 covers the paywall strings.
- `integration_matrix_edd.md` — adjacent commercial decisions on which third-party integrations require subscription gating (none currently; all integrations available to all paid tiers).
- `bootstrap_edd.md` — the paywall is the final step of the onboarding flow gated by `BootstrapFeature`; the flow's persistence and resume semantics are documented there. The §8 onboarding decision tree above extends `BootstrapFeature` with the trial-state branch.
- `view_layer_edd.md` — three-tier view taxonomy that the paywall's component decomposition follows.
- `design_system_edd.md` — token sources for paywall typography, color, and spacing.
- `dates_edd.md` — `CalendarContext` usage for trial state, refund window math, renewal date display.
- `CLAUDE.md` — overarching project rules including the `AppStrings` localization pattern, the design system's no-shadow / no-gradient / linear-animation discipline that the paywall obeys, and the "no third-party deps when Apple frameworks cover it" rule that keeps us from reimplementing Apple's subscription chrome.

### Apple Developer documentation (authoritative)

- **Family Sharing toggle in App Store Connect** — [Turn on Family Sharing for In-App Purchases](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases/). Confirms the one-way-door rule, the "all customers within a few hours" retroactive applicability, and the equivalence between subscription and non-consumable Family Sharing.
- **StoreKit 2 Family Sharing implementation** — [Supporting Family Sharing in your app](https://developer.apple.com/documentation/storekit/supporting-family-sharing-in-your-app). Source for the `Transaction.ownershipType`, `Transaction.revocationDate`, and "listen for transactions at launch and throughout the lifetime of the app" requirements.
- **Sandbox testing** — [Testing Family Sharing](https://developer.apple.com/documentation/storekit/testing-family-sharing). Sandbox tester setup, family group creation, and entitlement verification flow.
- **Tech Talk overview** — [Explore Family Sharing for In-App Purchases](https://developer.apple.com/videos/play/tech-talks/110345/). Apple's narrated walkthrough; useful for understanding the behavioral edge cases.
- **App Store Review Guidelines** — [3.1.1 In-App Purchase](https://developer.apple.com/app-store/review/guidelines/#3.1.1), [3.1.2 Subscriptions](https://developer.apple.com/app-store/review/guidelines/#3.1.2). Authoritative for IAP type definitions, subscription disclosure requirements, and Restore Purchases obligations.
- **StoreKit 2 reference** — [StoreKit framework documentation](https://developer.apple.com/documentation/storekit). Source of truth for `Product`, `Transaction`, `AppStore.sync()`, `AppStore.showManageSubscriptions(in:)`, `AppStore.refundRequestSheet(for:in:)` APIs used throughout §6 and §7.

---

*From Ink — Blair Technologies LLC — 2026-06*
