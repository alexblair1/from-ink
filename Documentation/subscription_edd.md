# From Ink — Subscription Engineering Design

> **Status:** Active. Pricing, paywall layout, and the ownership commitment ratified at the pre-V1 design pass (2026-06). StoreKit product configuration and Restore Purchases wiring are blocked on StoreKit integration; the paywall UI ships first with display-only strings.

---

## 1. Goals

- **Ship a paywall that tells the brand story.** The paywall is the first time most users encounter From Ink's commercial posture. Its visual hierarchy, headline, and tier framing should communicate the values position — *we believe writers should own their tools* — before they communicate any individual price.
- **Default to ownership.** Lifetime is the canonical purchase. Yearly and monthly subscriptions exist for users who specifically prefer recurring billing; they are not the brand position.
- **Bound complexity to three SKUs on one screen.** No tier ladder, no upsell modals, no feature gating between tiers. Every paid customer gets the same From Ink, only the payment cadence differs.
- **No recurring infrastructure cost commitment.** The pricing model is sustainable because operating cost per user is near zero — no servers, no per-user AI inference billing (Foundation Models runs on the user's device), no per-user storage billing (data lives in the user's own iCloud account). The subscription tiers fund development; the lifetime tier funds development at launch and accepts no further revenue.
- **Procreate as the comparable, not Notion.** The closest analog to the model From Ink ships is Procreate's one-time iPad purchase: a tool sold once, supported with free updates forever, no rent. From Ink's three-tier shape extends this by offering subscriptions for users who want them, while keeping the one-time-purchase as the default frame.

## 2. Tiers

Three SKUs. One paywall. Lifetime is the default-selected option.

| Tier | Price | Type | Trial | Default? | Family Sharing |
|---|---|---|---|---|---|
| **From Ink Plus — Lifetime** | $19.99 | Non-consumable IAP | None | **Yes — default-selected on paywall** | ✅ Enabled |
| **From Ink Plus — Yearly** | $14.99 / year | Auto-renewable subscription | 7 days | No | ✅ Enabled |
| **From Ink Plus — Monthly** | $2.99 / month | Auto-renewable subscription | 7 days | No | ✅ Enabled |

**Why $19.99 lifetime.** The conventional indie ratio of lifetime to annual is 4–6×, on the assumption that lifetime sales replace future subscription revenue from the same customer. That ratio is appropriate for apps with ongoing per-user costs and recurring-revenue investor expectations. From Ink has neither. The brand's pricing model is closer to iTunes's rent-vs-buy ratio: $14.99/year rents the app; $19.99 owns it. A user who would have stayed two years on annual pays $29.98 — they save $9.99 by owning. A user who would have churned at month 7 pays $14.99 — they spend $5 more to own. The math favors lifetime conversion in both common retention scenarios while removing all subscription anxiety. Higher conversion × marginally lower per-customer revenue is the deliberate trade.

**Why $14.99/year.** Matches Bear's Bear Pro annual price exactly. Bear is the closest direct comparable in brand-positioning terms (editorial typography, indie maker, premium-but-accessible). Matching the price aligns From Ink with the category Bear occupies in user mental models without re-anchoring expectations.

**Why $2.99/month.** Mathematical: $2.99 × 12 = $35.88, making the yearly tier 58% cheaper than monthly. That ratio is the right rhetorical strength — clearly anchors yearly as the value choice without making monthly feel deliberately punitive ($1.99/mo would make yearly only 37% cheaper, weakening the anchor; $3.99/mo at 65% would feel manipulative).

### 2.1 Family Sharing policy

**Family Sharing is enabled on all three tiers.**

Apple supports Family Sharing for both auto-renewable subscriptions AND non-consumable IAPs — [Apple confirms](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases/): *"Family Sharing for In-App Purchases lets people share their auto-renewable subscriptions and non-consumables with up to five additional family members."* This means a single $19.99 lifetime purchase grants permanent access to up to 6 family members in the purchaser's Apple Family Sharing group, with no additional cost.

**Why all three, including lifetime.** From Ink's positioning ("we don't want to rent you software — we want to give it to you") naturally extends to "we don't want to rent your family software either." Refusing Family Sharing on the lifetime tier would be saying "you own your software, but not enough to share with your spouse" — reads as a brand contradiction. The realistic per-purchase revenue dilution from Family Sharing is bounded (most family groups use 2-3 of the available 6 slots, not all 6), and the marketing value of "Family Sharing supported" is a passively-discovered conversion signal users specifically filter for in the App Store.

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

**StoreKit implementation cost: zero.** Per Apple: *"Your application will likely already handle family transactions without making any changes, because automatically these purchases are available to all family members."* The integration code reads `Transaction.currentEntitlements` and grants access regardless of whether the transaction is `.purchased` or `.familyShared`. The only optional UI surface is differentiating the two in the user's Settings screen (e.g., "Subscribed via Family Sharing") via `Transaction.ownershipType`. See §6 for the canonical StoreKit pattern.

**Revocation handling.** When a non-consumable lifetime IAP is family-shared and a family member later leaves the family group, Apple's StoreKit emits a transaction with `Transaction.revocationDate` set. The app must handle this — same handler as subscription expiry. Per Apple's [Supporting Family Sharing in your app](https://developer.apple.com/documentation/storekit/supporting-family-sharing-in-your-app) doc: *"It is critical to listen for transactions at launch and to continue to do so throughout the lifetime of the app to ensure your app never misses a transaction."* See §6.2 for the implementation pattern.

**Region constraint.** Family Sharing requires all family members to be in the same App Store country/region. Users in mixed-region families cannot share From Ink purchases. This is an Apple platform constraint, not something the app implements.

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

## 4. Trial policy

**Seven days. Subscription tiers only. None on lifetime.**

Trial duration was evaluated against industry benchmarks (RevenueCat State of Subscription Apps; ProfitWell research on trial-to-paid conversion curves). The pattern is consistent: trial-to-paid conversion rate decreases as trial length increases, and the decrease outpaces the increase in trial-start rate. Net revenue per trial start typically peaks at 7 days.

For an app like From Ink, where value is shown daily (morning brief, writing canvas, search) and habit forms within the first 2–3 days, 7 days is sufficient runway. Longer trials would suffer the "forgetting effect" — users decide whether to subscribe in the first few days; the remaining days primarily increase the probability the user disengages and the auto-bill becomes an unpleasant surprise.

**Apple's day-6 trial-ending push notification** is part of the conversion mechanic. Apple's standard StoreKit flow delivers a "your trial ends tomorrow" notification on day 6 of a 7-day trial. This notification recovers marginal users who would have otherwise let the trial lapse without subscribing.

**Lifetime gets no trial** because it is a one-time non-consumable IAP, not a subscription. StoreKit's trial mechanism applies only to auto-renewable subscriptions. Lifetime is purchased as-is; there is no "try before you buy" precedent at this price point in Apple's IAP system. The 7-day trial copy on the subscription cards must not appear on the lifetime card.

## 5. Paywall layout architecture

The paywall is `OnboardingSubscriptionView`, the fourth screen of the onboarding flow. It is also surfaced post-onboarding when users tap subscription-related affordances elsewhere in the app (Settings → Plus, free-tier limit prompts, etc.) — these surfaces reuse the same view with the same Model contract.

### 5.1 Visual hierarchy

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
       │            LIFETIME    ●                 │      (selected by default)
       │                                          │
       │              $19.99                      │
       │           pay once                       │
       │                                          │
       │   From Ink, and every update we'll       │
       │   ever ship. Yours, on every device      │
       │   you'll ever own. No subscription.      │
       └──────────────────────────────────────────┘

                  or, try free for 7 days             ← Connector copy

         ┌──────────────────┐  ┌──────────────────┐   ← Subscription cards
         │      YEARLY      │  │     MONTHLY      │     (paired, equal weight,
         │    $14.99/yr     │  │    $2.99/mo      │      visually smaller than
         │  about $1.25/mo  │  │                  │      the lifetime hero)
         └──────────────────┘  └──────────────────┘

       ── ── ── ── ── ── ── ── ── ── ── ── ── ──        ← Rule

         ✓ Unlimited notebooks and pages                 ← Feature list
         ✓ A canvas for ink and text                       (8 rows, identical
         ✓ Handwriting becomes searchable                  for all tiers — the
         ✓ Daily brief and smart search                    tiers differ in
         ✓ Calendar and reminder linking                   payment cadence,
         ✓ Tasks routed to your apps                       not feature set)
         ✓ Searchable PDF import
         ✓ iCloud sync across devices

         ┌──────────────────────────────────────┐       ← CTA (varies by
         │                Buy →                 │         selected tier;
         └──────────────────────────────────────┘         see §5.4)

                  RESTORE  PRIVACY  TERMS                ← Legal chrome
```

### 5.2 Why this hierarchy

**Lifetime as visual hero, subscriptions as paired secondary.** A three-equal-card grid would communicate "here are three options; pick one." That is the standard subscription paywall and it does not say what From Ink believes. The hero-plus-pair hierarchy communicates "this is what we recommend; these are alternatives if you prefer." The visual language matches industry conventions for highlighting "Most popular" tiers, so the user recognizes the pattern instantly — but the *meaning* is inverted: instead of "most popular subscription," it's "the way we want you to buy this."

**The connector "or, try free for 7 days"** does two things in one line: it bridges the visual transition from hero to paired cards, and it tells the user that the 7-day trial is a subscription-only thing. Without this line, a user looking at the lifetime card would reasonably wonder where the trial went. With it, the trial offer is clearly associated with the right tiers.

**Feature list identical for all three tiers.** Because the tiers differ in payment cadence, not feature access, there is no "Lifetime gets X, Yearly gets Y, Monthly gets Z" matrix to render. Every paid customer receives the same From Ink. The feature list reflects this — eight rows, identical regardless of which tier is selected.

### 5.3 The Lifetime card body copy

Three lines, each doing one job:

> **From Ink, and every update we'll ever ship.**
> **Yours, on every device you'll ever own.**
> **No subscription.**

Line 1 — the lifetime *update* promise (the Procreate commitment).
Line 2 — the lifetime *device* promise (clarifies the practical scope; iCloud sync means lifetime access follows the user across devices they own now and devices they buy in the future).
Line 3 — the *negative space* punch. "No subscription." is the one sentence on the entire paywall that defines what From Ink is *against*. It does not appear anywhere else on the paywall. Do not soften it. Do not bury it.

### 5.4 CTA label per selected tier

The primary CTA's label varies based on which tier is currently selected:

| Selected tier | CTA label |
|---|---|
| Lifetime | **Buy →** |
| Yearly | **Start free trial →** |
| Monthly | **Start free trial →** |

The CTA does double duty as both action affordance and brand reinforcement. "Buy →" is intentionally minimal — one word in English that translates as a single word or 2-character cluster in every target language (`Acheter`, `Kaufen`, `Acquista`, `Comprar`, `购买`, `購入`, `구매`), with no length-expansion risk on the button at AX5 Dynamic Type sizes. It also matches Apple's standard button label for non-consumable IAPs across all 175 App Store storefronts, conforming with platform convention at the moment of conversion.

The brand commitment is carried by the headline, the lifetime card's three lines, and the body copy — not by the button. The button confirms the action the user is about to take, and does it briefly.

The subscription CTAs ("Start free trial →") match user expectations from every other subscription paywall they've seen and accurately describe what tapping the button triggers (a 7-day trial period before billing begins).

The CTA's position, color, typography, and width are constant. Only the label string varies. This preserves the persistent-button view identity established in `OnboardingContainerView`.

### 5.5 Default selection

**Lifetime is selected by default.**

The reasoning is dual: it captures the indifferent middle of users (the ones who don't manually change the default) for the brand's preferred outcome, AND it communicates the brand position. Users who specifically want a subscription will manually switch; users who don't care will land where the product steers them, which is exactly where the brand wants them.

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

**Restoring purchases.** `AppStore.sync()` plus `Transaction.currentEntitlements` is the StoreKit 2 pattern. The Restore button on the paywall footer calls `AppStore.sync()` and then re-evaluates entitlements; if any are restored, the user is granted access and the paywall dismisses.

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

### 6.2 StoreKit 2 code pattern for entitlement handling

The integration code is identical for subscriptions and non-consumables. The canonical pattern:

```swift
import StoreKit

@MainActor
final class SubscriptionService {
    private let productIDs = [
        "com.fromink.app.plus.lifetime",
        "com.fromink.app.plus.yearly",
        "com.fromink.app.plus.monthly",
    ]

    // Cached products fetched once at launch.
    var products: [Product] = []

    // Per-user entitlement state.
    @Published var hasEntitlement: Bool = false
    @Published var entitlementSource: EntitlementSource = .none

    enum EntitlementSource: Equatable {
        case none
        case purchased(productID: String)
        case familyShared(productID: String)
    }

    func bootstrap() async {
        await fetchProducts()
        await reevaluateEntitlements()
        startTransactionListener()
    }

    private func fetchProducts() async {
        do {
            self.products = try await Product.products(for: productIDs)
        } catch {
            // Log; paywall will show retry affordance.
        }
    }

    private func reevaluateEntitlements() async {
        // `Transaction.currentEntitlements` is the source of truth for
        // both purchases AND family-shared entitlements. The
        // `ownershipType` property distinguishes them.
        var found: EntitlementSource = .none
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate != nil { continue }

            switch transaction.ownershipType {
            case .purchased:
                found = .purchased(productID: transaction.productID)
            case .familyShared:
                found = .familyShared(productID: transaction.productID)
            @unknown default:
                continue
            }
            break
        }
        self.entitlementSource = found
        self.hasEntitlement = (found != .none)
    }

    // Long-running listener for transactions that arrive while the app
    // is running — purchases completed in another session, family
    // member joining the family group, etc.
    //
    // Per Apple's [Supporting Family Sharing in your app] docs:
    // "It is critical to listen for transactions at launch and to
    // continue to do so throughout the lifetime of the app."
    private func startTransactionListener() {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self.reevaluateEntitlements()
            }
        }
    }

    // Triggered by the Restore Purchases button.
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await reevaluateEntitlements()
        } catch {
            // Surface error to user.
        }
    }
}
```

Key invariants:

- `Transaction.currentEntitlements` enumerates BOTH the user's own purchases AND family-shared entitlements. The app does not need separate code paths.
- `Transaction.ownershipType` is the only place the app differentiates `.purchased` from `.familyShared`. Useful for showing "Subscribed via Family Sharing" in the Settings screen; not load-bearing for granting access.
- `Transaction.revocationDate` must be checked. When a family member leaves the family group (or any other revocation event), Apple sends a transaction with `revocationDate` set; the app must respect this and revoke access.
- `Transaction.updates` is the long-running listener for transactions arriving while the app is running. This is what catches a family member joining mid-session, a purchase completing on another device, or a refund being processed. **Per Apple, this listener must be started at launch and remain active for the app's lifetime.**

### 6.3 Testing Family Sharing in sandbox

Apple's [Testing Family Sharing](https://developer.apple.com/documentation/storekit/testing-family-sharing) doc covers the sandbox setup. Summary:

- Create a **Sandbox Apple ID** at App Store Connect → **Users and Access** → **Sandbox Testers**. Repeat for each family member you want to test with.
- On the test device, sign into iOS Settings → **Developer** → **Sandbox Apple Account** with the organizer's sandbox ID.
- Create a Family group in **Settings → [Sandbox Apple ID] → Family Sharing**, invite the other sandbox testers as family members.
- Run From Ink, purchase the lifetime IAP as the organizer. Verify the purchase succeeds.
- Sign out and sign in on a second device with a family member's sandbox ID. Launch From Ink. The app should detect the family-shared entitlement via `Transaction.currentEntitlements` and unlock access automatically.
- Test revocation: remove the family member from the family group. The next time the app reads entitlements (next launch or next `Transaction.updates` tick), the entitlement should disappear.

The sandbox doesn't simulate the production "few hours" delay for retroactive Family Sharing activation; sandbox is immediate.

## 7. Restore Purchases, Privacy, Terms — required affordances

Apple's App Store Review Guidelines require three affordances visible at the point of purchase:

1. **Restore Purchases** — for users who previously purchased on another device or under another Apple ID. Must be accessible without first creating an account or providing any other input.
2. **Privacy Policy** — link to the published privacy policy. Apple requires this for any app that handles user data; From Ink handles user data (notes, handwriting, calendar events) extensively.
3. **Terms of Service** (or "Terms of Use" / "Terms and Conditions") — link to the published terms of service. Apple requires this for any app with subscriptions.

These three live in the paywall's legal-chrome footer row, rendered as small mono uppercase tap targets below the primary CTA. The component is `OnboardingLegalChrome`. Each tap target carries its own action — the wiring view routes Restore through StoreKit and Privacy / Terms through `UIApplication.shared.open(URL)` to the respective URLs.

**URLs are TBD.** Pre-V1 launch action item: publish the Privacy Policy and Terms of Service at stable URLs and wire them into the chrome's action handlers. The current code path has no-op actions in the placeholder configuration.

## 8. Apple guideline compliance

The pricing model and IAP configuration are evaluated against the relevant Apple guidelines.

| Guideline | How From Ink complies |
|---|---|
| **3.1.1 — In-App Purchase** | Non-consumable (lifetime) and auto-renewable subscriptions (yearly, monthly) are both standard IAP types. Apple has approved thousands of apps using exactly this combination. |
| **3.1.2 — Subscriptions** | The two subscription tiers provide ongoing value (full app access for the duration). Auto-renewal terms are clearly disclosed. Trial duration is clearly stated. Restore Purchases is provided. Privacy and Terms links are visible at the point of purchase. |
| **3.1.2(a) — Subscription Information** | The paywall includes: subscription length (yearly / monthly), price per period, auto-renewal disclosure, free trial length, link to Terms, link to Privacy Policy, Restore Purchases affordance. All of these must be visible before the user taps the primary CTA. |
| **3.1.3 — "Reader" Apps** | Not applicable. From Ink does not qualify as a "Reader" app (the reader-app exemption is for apps whose primary purpose is consuming previously-purchased content from external accounts). |
| **3.1.5(a) — Goods and Services Outside of the App** | Not applicable. From Ink's IAPs unlock features within the app itself, not external goods or services. |

**Lifetime-specific copy compliance.** The word "subscription" must not appear in copy that describes the lifetime tier (lifetime is a one-time purchase, not a subscription). "Pay once," "yours forever," "lifetime access," and "one-time purchase" are all compliant. "Lifetime subscription" is non-compliant and confusing. The current copy uses "Pay once. Yours, forever." which is compliant.

**"Lifetime" definition for legal purposes.** Internally and in user-facing fine print, "lifetime" is defined as "for as long as the app remains available on the App Store under the same ownership." This bounded definition avoids ambiguity about whether "lifetime" means the user's lifetime, the device's lifetime, the company's lifetime, or some other timeline. The bounded definition is the industry norm and matches Apple's expectation for non-consumable IAPs.

## 9. Localization

The paywall is one of the most carefully localized surfaces in the app — its copy is load-bearing for both conversion and brand. All strings flow through the localization architecture described in `localization_edd.md`.

| String | Translation notes |
|---|---|
| Kicker: "From Ink Plus" | **Not translated.** Per glossary §3.2 of the localization EDD, "From Ink" and "From Ink Plus" pass through verbatim in all languages, in Latin script. |
| Headline: "Pay once. Yours, forever." | **Most carefully translated string on the paywall.** The two-tone effect (declarative + emotive) must survive the translation. The translator's brief explicitly calls out the rhythmic break between the two sentences. JP/KO contractions of the English structure are expected. |
| Body: 3 sentences | Translated. The third sentence ("Subscriptions are also available.") is informational; preserve neutral register, not pitched. |
| Lifetime card body, 3 lines | Translated. The third line ("No subscription.") is the punch — translators must preserve its terseness even if the target language tends toward longer phrasing. |
| Connector: "or, try free for 7 days" | Translated. The lower-case "or" is intentional in English and may need locale-specific capitalization in target languages. |
| Subscription card prices and units | Currency formatting handled at runtime by `Product.displayPrice` per StoreKit 2; the surrounding chrome strings (yearly, monthly, "about $1.25/mo") are translated. |
| Feature list, 8 rows | Same translation budget as the rest of `AppStrings.Onboarding`. Per `localization_edd.md` §3.2, terms like "iCloud" and "PDF" pass through verbatim. |
| CTA labels (3 variants) | Translated. Each variant ("Pay once →", "Start free trial →") is its own key — same English string maps to different localized strings if needed. |
| Legal chrome ("Restore", "Privacy", "Terms") | Translated. These are short labels; the translator's brief calls out their function as legal-chrome affordances so the translation matches platform convention in the target language. |

Phase 1 of the localization rollout (`localization_edd.md` §12 Batch 1) ships the paywall in all nine launch languages alongside the rest of the onboarding domain.

## 10. Open questions

| # | Question | Impact |
|---|---|---|
| 1 | Privacy Policy URL — where will it be published, and when? | Blocks the paywall footer's `Privacy` action from doing real work. Pre-V1 must-have. |
| 2 | Terms of Service URL — where will it be published, and when? | Same as above. |
| 3 | When does StoreKit integration land? | The paywall is currently UI-only with placeholder display strings. StoreKit integration converts the placeholder display into actual product fetching, paywall tap → purchase flow, Restore Purchases wiring, transaction validation. |
| 4 | Should the paywall be tested with `Configuration.storekit` files in the test target before the live App Store Connect SKUs are configured? | Yes — StoreKit testing in Xcode is the standard pre-integration validation. Should be set up alongside StoreKit integration work. |
| 5 | What's the cancellation grace policy for users who tap Restore but have no valid entitlements? | Standard behavior: dismiss the paywall, return to the previous screen, present a non-blocking toast. Not blocking, but should be explicitly designed before launch. |
| 6 | Will From Ink Plus offer a referral program (existing user invites friend, both get a discount or extended trial)? | Strategic. Not in the V1 launch scope. If yes later, the Pro tier disclosure (§3.1) and the StoreKit configuration need a referral SKU lane. |
| 7 | When a future Pro tier is introduced, what entitlement model gates Pro from Plus? | Open. Two patterns: (a) Pro is a separate auto-renewable subscription, lifetime Plus customers can additionally subscribe to Pro for the Pro features. (b) Pro features are a separate non-consumable that unlocks on top of Plus entitlement. Decision deferred; this EDD will be amended when Pro is on the roadmap. |
| 8 | "Founder's pricing" — should there be a limited-time launch discount on lifetime ($14.99 instead of $19.99 for the first 30 days post-launch)? | Strategic. Considered and rejected at this design pass; the unbiased ratio of lifetime to yearly ($19.99 / $14.99 = 1.33×) is already compelling without further discounting. Revisit if launch conversion is below expectations. |

## 11. Cross-references

### Internal documents

- `localization_edd.md` — §3 language list, §3.1 style guide, §3.2 glossary, §6.4 "selling FM-gated features in paywalls"; §12 migration plan Batch 1 covers the paywall strings.
- `integration_matrix_edd.md` — adjacent commercial decisions on which third-party integrations require subscription gating (none currently; all integrations available to all paid tiers).
- `bootstrap_edd.md` — the paywall is the final step of the onboarding flow gated by `BootstrapFeature`; the flow's persistence and resume semantics are documented there.
- `view_layer_edd.md` — three-tier view taxonomy that the paywall's component decomposition follows.
- `design_system_edd.md` — token sources for paywall typography, color, and spacing.
- `CLAUDE.md` — overarching project rules including the `AppStrings` localization pattern and the design system's no-shadow / no-gradient / linear-animation discipline that the paywall obeys.

### Apple Developer documentation (authoritative)

- **Family Sharing toggle in App Store Connect** — [Turn on Family Sharing for In-App Purchases](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases/). Confirms the one-way-door rule, the "all customers within a few hours" retroactive applicability, and the equivalence between subscription and non-consumable Family Sharing.
- **StoreKit 2 Family Sharing implementation** — [Supporting Family Sharing in your app](https://developer.apple.com/documentation/storekit/supporting-family-sharing-in-your-app). Source for the `Transaction.ownershipType`, `Transaction.revocationDate`, and "listen for transactions at launch and throughout the lifetime of the app" requirements.
- **Sandbox testing** — [Testing Family Sharing](https://developer.apple.com/documentation/storekit/testing-family-sharing). Sandbox tester setup, family group creation, and entitlement verification flow.
- **Tech Talk overview** — [Explore Family Sharing for In-App Purchases](https://developer.apple.com/videos/play/tech-talks/110345/). Apple's narrated walkthrough; useful for understanding the behavioral edge cases.
- **App Store Review Guidelines** — [3.1.1 In-App Purchase](https://developer.apple.com/app-store/review/guidelines/#3.1.1), [3.1.2 Subscriptions](https://developer.apple.com/app-store/review/guidelines/#3.1.2). Authoritative for IAP type definitions, subscription disclosure requirements, and Restore Purchases obligations.
- **StoreKit 2 reference** — [StoreKit framework documentation](https://developer.apple.com/documentation/storekit). Source of truth for `Product`, `Transaction`, `AppStore.sync()` APIs used in the §6.2 pattern.

---

*From Ink — Blair Technologies LLC — 2026-06*
