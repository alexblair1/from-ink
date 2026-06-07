import Foundation

extension AppStrings {

    enum Onboarding {

        // MARK: - Welcome

        static let welcomeKicker = NSLocalizedString(
            "onboarding.welcome.kicker",
            value: "Welcome to",
            comment: "Onboarding welcome screen eyebrow above the wordmark"
        )
        static let welcomeWordmark = NSLocalizedString(
            "onboarding.welcome.wordmark",
            value: "From Ink",
            comment: "App wordmark displayed as the hero on the welcome screen"
        )
        static let welcomeBody = NSLocalizedString(
            "onboarding.welcome.body",
            value: "A quiet home for your notes, notebooks, and PDFs. Composed into one brief each morning.",
            comment: "Welcome screen lede. Two sentences instead of an em-dash separator so the copy localizes cleanly without typographic furniture."
        )
        static let welcomeButton = NSLocalizedString(
            "onboarding.welcome.button",
            value: "Begin",
            comment: "Welcome screen primary CTA"
        )

        // MARK: - Value

        static let valueKicker = NSLocalizedString(
            "onboarding.value.kicker",
            value: "The idea",
            comment: "Onboarding value screen eyebrow"
        )
        static let valueHeadlineLine1 = NSLocalizedString(
            "onboarding.value.headline.line1",
            value: "From ink",
            comment: "Onboarding value screen headline — first line, ink color. Half of the brand mantra; rendered alongside the italic accent line below."
        )
        static let valueHeadlineLine2 = NSLocalizedString(
            "onboarding.value.headline.line2",
            value: "to done.",
            comment: "Onboarding value screen headline — second line, italic ink-2 accent. Completes the 'From ink to done.' brand mantra."
        )

        // MARK: - Value feature rows
        //
        // Five pillars rendered top to bottom. The escalation is: how you
        // write → what you see each morning → where it goes → who can
        // use it → who can see it. Privacy is the deliberate close,
        // landing the user on the boundary that protects them right
        // before the Continue button.

        // Pillar 1 — capture / input modes. Names both Apple Pencil and
        // keyboard input honestly; finger drawing is omitted because the
        // canvas runs in .pencilOnly mode (per PaperKit canvas rules in
        // CLAUDE.md). Future-proof for the text-based note system.
        static let valueInkTextKicker = NSLocalizedString(
            "onboarding.value.ink_text.kicker",
            value: "Ink & text",
            comment: "Value row eyebrow — capture modes. Names both supported input modalities."
        )
        static let valueInkTextTitle = NSLocalizedString(
            "onboarding.value.ink_text.title",
            value: "Write the way you think",
            comment: "Value row title — capture modes."
        )
        static let valueInkTextBody = NSLocalizedString(
            "onboarding.value.ink_text.body",
            value: "Apple Pencil for ink. Keyboard for text. Whichever your hands prefer.",
            comment: "Value row body — capture modes. Three short sentences instead of an em-dash so the copy localizes cleanly. 'Apple Pencil' passes through verbatim per the localization EDD glossary."
        )

        // Pillar 2 — the daily brief. Sources named (calendar, reminders,
        // weather, notes) ground the abstract brief in concrete inputs.
        static let valueBriefKicker = NSLocalizedString(
            "onboarding.value.brief.kicker",
            value: "Daily brief",
            comment: "Value row eyebrow — daily brief."
        )
        static let valueBriefTitle = NSLocalizedString(
            "onboarding.value.brief.title",
            value: "Your day, composed",
            comment: "Value row title — daily brief."
        )
        static let valueBriefBody = NSLocalizedString(
            "onboarding.value.brief.body",
            value: "Calendar, reminders, weather, and recent notes drawn into one morning read.",
            comment: "Value row body — daily brief. 'Drawn into' carries the brand's ink metaphor. No em-dash so the copy localizes cleanly."
        )

        // Pillar 3 — user-driven linking from inside the writing experience.
        // The destinations (reminder / calendar event / contact) are
        // V1-honest examples under an 'anything' umbrella that will
        // expand gracefully when V2 OAuth integrations ship.
        static let valueConnectionsKicker = NSLocalizedString(
            "onboarding.value.connections.kicker",
            value: "Connections",
            comment: "Value row eyebrow — linking handwriting to other apps and entities."
        )
        static let valueConnectionsTitle = NSLocalizedString(
            "onboarding.value.connections.title",
            value: "Connected to your day",
            comment: "Value row title — linking handwriting to other apps and entities."
        )
        static let valueConnectionsBody = NSLocalizedString(
            "onboarding.value.connections.body",
            value: "Link your handwriting to anything. A reminder, a calendar event, a name.",
            comment: "Value row body — linking. 'Anything' carries the breadth promise; the three nouns are V1-honest examples (Reminders, Calendar, Contacts). Pattern expands gracefully when V2 OAuth integrations ship — no copy update needed."
        )

        // Pillar 4 — accessibility, framed without the word. Three
        // concrete capabilities (Dynamic Type, VoiceOver, RTL support)
        // under a universalizing premise. The localization EDD covers
        // RTL layout, and the design system covers Dynamic Type — this
        // row commits the marketing to the experience.
        static let valueReadingKicker = NSLocalizedString(
            "onboarding.value.reading.kicker",
            value: "For every reader",
            comment: "Value row eyebrow — universal-design framing without using the word 'accessibility'. Names the audience the row serves implicitly."
        )
        static let valueReadingTitle = NSLocalizedString(
            "onboarding.value.reading.title",
            value: "Made for the way you read",
            comment: "Value row title — universal-design framing. 'The way you read' universalizes (every reader fits in this sentence)."
        )
        static let valueReadingBody = NSLocalizedString(
            "onboarding.value.reading.body",
            value: "Text at every size. Reads aloud when you ask. Whichever way you read.",
            comment: "Value row body — three concrete capabilities. 'Text at every size' covers Dynamic Type; 'Reads aloud when you ask' covers VoiceOver; 'Whichever way you read' covers RTL layout implicitly. The word 'accessibility' is deliberately absent — the row describes the experience, not the audience it serves."
        )

        // Pillar 5 — privacy as the deliberate close. Three factually
        // defensible claims: on-device Foundation Models (no third-party
        // AI servers), no From Ink backend that ingests notes, and
        // CloudKit sync as a boundary the user already has with Apple.
        static let valuePrivacyKicker = NSLocalizedString(
            "onboarding.value.privacy.kicker",
            value: "Privacy",
            comment: "Value row eyebrow — privacy. Direct, no marketing softening."
        )
        static let valuePrivacyTitle = NSLocalizedString(
            "onboarding.value.privacy.title",
            value: "The privacy you deserve",
            comment: "Value row title — privacy. Claims a moral position (privacy as a right) before substantiating it in the body."
        )
        static let valuePrivacyBody = NSLocalizedString(
            "onboarding.value.privacy.body",
            value: "On-device AI. We never see your notes. iCloud sync, between you and Apple.",
            comment: "Value row body — three factually defensible privacy claims. (1) Foundation Models runs locally, no third-party AI server in the loop. (2) From Ink operates no backend that ingests note content. (3) CloudKit private database — the sync exists but stays in the user's iCloud, not From Ink's infrastructure."
        )

        // MARK: - Permissions

        static let permissionsKicker = NSLocalizedString(
            "onboarding.permissions.kicker",
            value: "Permissions",
            comment: "Onboarding permissions screen eyebrow"
        )
        static let permissionsHeadlineLine1 = NSLocalizedString(
            "onboarding.permissions.headline.line1",
            value: "Let From Ink",
            comment: "Permissions headline — first line"
        )
        static let permissionsHeadlineLine2 = NSLocalizedString(
            "onboarding.permissions.headline.line2",
            value: "read your day.",
            comment: "Permissions headline — second (italic accent) line"
        )
        static let permissionsBody = NSLocalizedString(
            "onboarding.permissions.body",
            value: "Your morning brief reads from your calendar and reminders. Without them, the page stays quiet. Change anytime in Settings.",
            comment: "Permissions screen body. Marketing-leaning: ties the permissions ask to the Daily Brief experience and uses the brand metaphor ('the page stays quiet') so the cost of declining is concrete without being preachy. Three short sentences instead of an em-dash so the copy localizes cleanly."
        )

        static let permissionsCalendarTitle = NSLocalizedString(
            "onboarding.permissions.calendar.title",
            value: "Calendar & Events",
            comment: "Permissions row title — calendar"
        )
        static let permissionsCalendarBody = NSLocalizedString(
            "onboarding.permissions.calendar.body",
            value: "Show today's events at the top of your brief.",
            comment: "Permissions row body — calendar"
        )
        static let permissionsRemindersTitle = NSLocalizedString(
            "onboarding.permissions.reminders.title",
            value: "Reminders",
            comment: "Permissions row title — reminders"
        )
        static let permissionsRemindersBody = NSLocalizedString(
            "onboarding.permissions.reminders.body",
            value: "Surface what's due and what's overdue.",
            comment: "Permissions row body — reminders"
        )

        static let permissionsLocationTitle = NSLocalizedString(
            "onboarding.permissions.location.title",
            value: "Location",
            comment: "Permissions row title — location (used for weather in the daily brief)"
        )
        static let permissionsLocationBody = NSLocalizedString(
            "onboarding.permissions.location.body",
            value: "Show weather in your morning brief.",
            comment: "Permissions row body — location. Brief, brief-focused, mirrors the framing of the calendar and reminders rows above."
        )

        static let permissionsMicrophoneKicker = NSLocalizedString(
            "onboarding.permissions.microphone.kicker",
            value: "Microphone",
            comment: "Microphone permission card eyebrow. 'Later' framing dropped now that the card requests access in-flow rather than deferring it."
        )
        static let permissionsMicrophoneBody = NSLocalizedString(
            "onboarding.permissions.microphone.body",
            value: "Voice notes use the microphone. Tap to grant access, or change it anytime in Settings.",
            comment: "Microphone permission card body. Tells the user the affordance is interactive and reversible from Settings."
        )

        /// Inline affordance rendered in place of the OnboardingSwitch
        /// when a permission row's status is denied, restricted, or
        /// write-only — anywhere the user can't grant in-app and must
        /// open the system Settings app to change the state.
        static let permissionsOpenSettings = NSLocalizedString(
            "onboarding.permissions.open_settings",
            value: "Open Settings",
            comment: "Inline link rendered in place of the toggle when a permission is denied/restricted. Tap routes to the iOS Settings app via UIApplication.openSettingsURLString."
        )

        static let permissionsContinue = NSLocalizedString(
            "onboarding.permissions.continue",
            value: "Continue",
            comment: "Permissions primary CTA"
        )

        // MARK: - Permissions confirmation (both toggles off)

        /// Shown when the user taps Continue with both Calendar and
        /// Reminders still disabled. One-shot ask — the user must then
        /// pick "Turn on both" or "Continue without".
        static let permissionsConfirmationTitle = NSLocalizedString(
            "onboarding.permissions.confirmation.title",
            value: "Without these, the brief stays quiet",
            comment: "Title of the confirmation alert shown when a user tries to advance from permissions with both toggles off"
        )
        static let permissionsConfirmationMessage = NSLocalizedString(
            "onboarding.permissions.confirmation.message",
            value: "Calendar and reminders are how From Ink composes your day, and how the page meets you each morning.",
            comment: "Message body of the permissions confirmation alert. Comma replaces an em-dash so the copy localizes cleanly."
        )
        static let permissionsConfirmationConfirm = NSLocalizedString(
            "onboarding.permissions.confirmation.confirm",
            value: "Turn on both",
            comment: "Primary CTA in the permissions confirmation alert — flips both toggles to on and advances"
        )
        static let permissionsConfirmationDismiss = NSLocalizedString(
            "onboarding.permissions.confirmation.dismiss",
            value: "Continue without",
            comment: "Secondary CTA in the permissions confirmation alert — advances with both toggles off"
        )

        // MARK: - Subscription

        static let subscriptionKicker = NSLocalizedString(
            "onboarding.subscription.kicker",
            value: "From Ink Plus",
            comment: "Subscription screen eyebrow. Brand name passes through verbatim per the localization EDD glossary."
        )

        // MARK: - Per-tier headline + body
        //
        // The paywall's main headline and supporting body change based
        // on which tier the user has selected. This keeps the three
        // tier options visually equal (stacked, equal weight) while
        // letting the editorial copy at the top of the screen carry
        // each tier's specific framing.
        //
        // Each tier follows the established two-tone pattern:
        // line1 (ink) + line2 (italic, ink-2 accent), joined with a
        // space in the view.

        // LIFETIME — brand-position headline; the ownership commitment.
        static let subscriptionLifetimeHeadlineLine1 = NSLocalizedString(
            "onboarding.subscription.lifetime.headline.line1",
            value: "Pay once.",
            comment: "Lifetime tier headline — first line, ink color. The anti-subscription pattern interrupt."
        )
        static let subscriptionLifetimeHeadlineLine2 = NSLocalizedString(
            "onboarding.subscription.lifetime.headline.line2",
            value: "Yours, forever.",
            comment: "Lifetime tier headline — second line, italic ink-2 accent. The emotional payoff."
        )
        /// Lifetime tier body, three separate sentences rendered as a
        /// stacked VStack under the headline. Each does one job:
        ///   line 1: the lifetime UPDATES promise (Procreate-style)
        ///   line 2: the lifetime DEVICES promise (iCloud scope)
        ///   line 3: "No subscription." — the negative-space punch
        ///
        /// Per subscription EDD §5.3, line 3 must NOT be softened or
        /// buried in translation. It is the one sentence that defines
        /// what From Ink is against. Translators should preserve its
        /// terseness even if the target language tends toward longer
        /// phrasing.
        static let subscriptionLifetimeBody1 = NSLocalizedString(
            "onboarding.subscription.lifetime.body.1",
            value: "From Ink, and every update we'll ever ship.",
            comment: "Lifetime tier body line 1 of 3 — the Procreate-style lifetime updates commitment."
        )
        static let subscriptionLifetimeBody2 = NSLocalizedString(
            "onboarding.subscription.lifetime.body.2",
            value: "Yours, on every device you'll ever own.",
            comment: "Lifetime tier body line 2 of 3 — clarifies practical scope (iCloud sync follows the user across devices)."
        )
        static let subscriptionLifetimeBody3 = NSLocalizedString(
            "onboarding.subscription.lifetime.body.3",
            value: "No subscription.",
            comment: "Lifetime tier body line 3 of 3 — the negative-space punch. Per subscription EDD §5.3, this is the one sentence that defines what From Ink is against. Do NOT soften. Do NOT bury. Translators should preserve its terseness even if the target language tends toward longer phrasing."
        )

        // YEARLY — trial-first framing with the post-trial annual cost.
        static let subscriptionYearlyHeadlineLine1 = NSLocalizedString(
            "onboarding.subscription.yearly.headline.line1",
            value: "Free for 7 days,",
            comment: "Yearly tier headline — first line, ink color. Leads with the trial offer."
        )
        static let subscriptionYearlyHeadlineLine2 = NSLocalizedString(
            "onboarding.subscription.yearly.headline.line2",
            value: "then $14.99 a year.",
            comment: "Yearly tier headline — second line, italic ink-2 accent. The post-trial cadence. Price is a placeholder until StoreKit integration replaces it with Product.displayPrice."
        )
        static let subscriptionYearlyBody = NSLocalizedString(
            "onboarding.subscription.yearly.body",
            value: "Cancel anytime.",
            comment: "Yearly tier body. The cancellation reassurance, kept short."
        )

        // MONTHLY — same trial-first framing with monthly cadence.
        static let subscriptionMonthlyHeadlineLine1 = NSLocalizedString(
            "onboarding.subscription.monthly.headline.line1",
            value: "Free for 7 days,",
            comment: "Monthly tier headline — first line, ink color. Leads with the trial offer (matches yearly tier's line1)."
        )
        static let subscriptionMonthlyHeadlineLine2 = NSLocalizedString(
            "onboarding.subscription.monthly.headline.line2",
            value: "then $2.99 a month.",
            comment: "Monthly tier headline — second line, italic ink-2 accent. The post-trial cadence. Price is a placeholder until StoreKit integration replaces it with Product.displayPrice."
        )
        static let subscriptionMonthlyBody = NSLocalizedString(
            "onboarding.subscription.monthly.body",
            value: "Cancel anytime.",
            comment: "Monthly tier body. Matches yearly tier's body."
        )

        static let subscriptionPriceMajor = NSLocalizedString(
            "onboarding.subscription.price.major",
            value: "$11.99",
            comment: "Subscription price — major value"
        )
        static let subscriptionPriceUnit = NSLocalizedString(
            "onboarding.subscription.price.unit",
            value: "per year",
            comment: "Subscription price unit. 'per year' instead of '/ year' so the copy reads naturally and localizes cleanly without a slash separator."
        )
        static let subscriptionPriceCaption = NSLocalizedString(
            "onboarding.subscription.price.caption",
            value: "After your 7 day free trial",
            comment: "Subscription mono caption beneath the price. '7 day' (no hyphen) instead of '7-day' so the copy localizes cleanly without compound-word punctuation."
        )
        /// Consumer-friendly monthly breakdown rendered beneath the
        /// annual price. Reframes the $11.99 sticker as a coffee-a-month
        /// cost — same psychology as the body copy line "Keep it for
        /// less than a coffee a year." Borrowed from competitive pattern
        /// (Goodnotes Essential / Pro tiers).
        static let subscriptionPriceMonthly = NSLocalizedString(
            "onboarding.subscription.price.monthly",
            value: "About $1 a month, billed annually",
            comment: "Consumer-friendly per-month breakdown rendered beneath the annual price."
        )

        static let subscriptionFeatureNotebooks = NSLocalizedString(
            "onboarding.subscription.feature.notebooks",
            value: "Unlimited notebooks and pages",
            comment: "Subscription included feature row — capacity unlock vs free plan."
        )
        static let subscriptionFeatureWriting = NSLocalizedString(
            "onboarding.subscription.feature.writing",
            value: "A canvas for ink and text",
            comment: "Subscription included feature row — capture experience. Names both supported modalities (handwritten ink AND typed text on the same page) because the app does both — most competing notes apps make the user choose. 'Canvas' does the experiential showcase work; 'ink' reinforces the brand."
        )
        static let subscriptionFeatureHandwriting = NSLocalizedString(
            "onboarding.subscription.feature.handwriting",
            value: "Handwriting becomes searchable",
            comment: "Subscription included feature row — Vision-based on-device handwriting recognition. The big differentiator."
        )
        static let subscriptionFeatureBrief = NSLocalizedString(
            "onboarding.subscription.feature.brief",
            value: "Daily brief and smart search",
            comment: "Subscription included feature row — Foundation Models intelligence layer."
        )
        static let subscriptionFeatureLinking = NSLocalizedString(
            "onboarding.subscription.feature.linking",
            value: "Calendar and reminder linking",
            comment: "Subscription included feature row — notebook ↔ EventKit linking. Competitive wedge."
        )
        static let subscriptionFeatureRouting = NSLocalizedString(
            "onboarding.subscription.feature.routing",
            value: "Tasks routed to your apps",
            comment: "Subscription included feature row — Dispatch action layer (Reminders / Mail / Messages / etc)."
        )
        static let subscriptionFeaturePDFs = NSLocalizedString(
            "onboarding.subscription.feature.pdfs",
            value: "Searchable PDF import",
            comment: "Subscription included feature row — content acquisition path. Deliberately avoids the acronym 'OCR' (which most users don't decode — they just experience it as 'the app understands the page'); 'searchable' communicates the value of OCR without the jargon."
        )
        static let subscriptionFeatureSync = NSLocalizedString(
            "onboarding.subscription.feature.sync",
            value: "iCloud sync across devices",
            comment: "Subscription included feature row — multi-device experience via CloudKit."
        )
        static let subscriptionFeatureFamilySharing = NSLocalizedString(
            "onboarding.subscription.feature.family",
            value: "Family Sharing for up to 6",
            comment: "Subscription included feature row — Family Sharing applies to all three tiers per subscription EDD §2.1. The 'for up to 6' framing communicates the practical scope without using the literal Apple count (organizer + 5 family members)."
        )

        static let subscriptionPrimary = NSLocalizedString(
            "onboarding.subscription.primary",
            value: "Start free trial",
            comment: "Subscription primary CTA when a subscription tier (yearly or monthly) is selected. Accurately describes the action: tapping starts a 7-day free trial before billing begins."
        )

        /// Primary CTA label when the lifetime tier is selected. Per
        /// subscription EDD §5.4, intentionally minimal — one word in
        /// English that translates as a single word or 2-character
        /// cluster in every target language with no expansion risk on
        /// the button at AX5 Dynamic Type sizes. Matches Apple's
        /// standard non-consumable IAP button label across all 175
        /// App Store storefronts.
        static let subscriptionPrimaryLifetime = NSLocalizedString(
            "onboarding.subscription.primary.lifetime",
            value: "Buy",
            comment: "Primary CTA when the lifetime tier is selected. One word, universal across languages. Matches Apple's standard non-consumable IAP button label."
        )

        // MARK: - Tier cards (kickers, prices, subtitles)
        //
        // All three tiers render as equal-weight stacked cards. Each
        // shows a kicker (uppercase mono), a price, and an optional
        // subtitle. Lifetime's "pay once" subtitle distinguishes it
        // from the per-period subscriptions; yearly and monthly carry
        // no subtitle (the per-cadence cost is in the price itself).

        static let subscriptionLifetimeKicker = NSLocalizedString(
            "onboarding.subscription.lifetime.kicker",
            value: "Lifetime",
            comment: "Mono uppercase label at the top of the lifetime tier card."
        )
        static let subscriptionLifetimePriceMajor = NSLocalizedString(
            "onboarding.subscription.lifetime.price.major",
            value: "$19.99",
            comment: "Lifetime tier price. Placeholder until StoreKit integration replaces it with Product.displayPrice (locale-aware currency formatting)."
        )
        static let subscriptionLifetimePriceCaption = NSLocalizedString(
            "onboarding.subscription.lifetime.price.caption",
            value: "pay once",
            comment: "Small mono uppercase caption beneath the lifetime price. Distinguishes lifetime from per-period subscription tiers."
        )

        static let subscriptionYearlyKicker = NSLocalizedString(
            "onboarding.subscription.yearly.kicker",
            value: "Yearly",
            comment: "Mono uppercase label at the top of the yearly tier card."
        )
        static let subscriptionYearlyPrice = NSLocalizedString(
            "onboarding.subscription.yearly.price",
            value: "$14.99/yr",
            comment: "Yearly tier price. Placeholder until StoreKit integration."
        )

        static let subscriptionMonthlyKicker = NSLocalizedString(
            "onboarding.subscription.monthly.kicker",
            value: "Monthly",
            comment: "Mono uppercase label at the top of the monthly tier card."
        )
        static let subscriptionMonthlyPrice = NSLocalizedString(
            "onboarding.subscription.monthly.price",
            value: "$2.99/mo",
            comment: "Monthly tier price. Placeholder until StoreKit integration."
        )

        /// VoiceOver label for the X close button rendered in the
        /// top-right corner of the subscription screen. Replaced the
        /// older "Maybe later" textual link — at large Dynamic Type
        /// sizes a footer link grew into a giant tap zone; an X in the
        /// corner stays compact and out of the primary CTA's hierarchy.
        static let closeButton = NSLocalizedString(
            "onboarding.close",
            value: "Close",
            comment: "VoiceOver label for the subscription screen's X dismiss button"
        )

        // MARK: - Subscription legal chrome
        //
        // Required by App Store guidelines: Restore Purchases must be
        // easily accessible; subscription terms and privacy policy must
        // be visible at the point of purchase. Rendered as small mono
        // text links directly below the primary CTA on subscription only.

        static let subscriptionLegalRestore = NSLocalizedString(
            "onboarding.subscription.legal.restore",
            value: "Restore",
            comment: "Footer link label: restore prior purchases. Required by App Store guidelines."
        )
        static let subscriptionLegalPrivacy = NSLocalizedString(
            "onboarding.subscription.legal.privacy",
            value: "Privacy",
            comment: "Footer link label: opens the privacy policy. Required by App Store guidelines."
        )
        static let subscriptionLegalTerms = NSLocalizedString(
            "onboarding.subscription.legal.terms",
            value: "Terms",
            comment: "Footer link label: opens the terms of service. Required by App Store guidelines."
        )

        // MARK: - Continue (shared CTA on value)

        static let continueButton = NSLocalizedString(
            "onboarding.continue",
            value: "Continue",
            comment: "Primary CTA on intermediate onboarding screens"
        )
    }
}
