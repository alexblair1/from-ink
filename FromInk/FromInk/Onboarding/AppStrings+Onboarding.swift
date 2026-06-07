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
            value: "Everything,",
            comment: "Onboarding value screen headline — first line"
        )
        static let valueHeadlineLine2 = NSLocalizedString(
            "onboarding.value.headline.line2",
            value: "in one brief.",
            comment: "Onboarding value screen headline — second (italic accent) line"
        )

        // Feature rows
        static let valueBriefKicker = NSLocalizedString(
            "onboarding.value.brief.kicker",
            value: "Daily brief",
            comment: "Value row eyebrow — daily brief"
        )
        static let valueBriefTitle = NSLocalizedString(
            "onboarding.value.brief.title",
            value: "Your day, composed",
            comment: "Value row title — daily brief"
        )
        static let valueBriefBody = NSLocalizedString(
            "onboarding.value.brief.body",
            value: "Events, reminders and recent notes gathered into a single morning read.",
            comment: "Value row body — daily brief"
        )

        static let valueNotebooksKicker = NSLocalizedString(
            "onboarding.value.notebooks.kicker",
            value: "Notebooks & pages",
            comment: "Value row eyebrow — notebooks"
        )
        static let valueNotebooksTitle = NSLocalizedString(
            "onboarding.value.notebooks.title",
            value: "Write freely, sort later",
            comment: "Value row title — notebooks"
        )
        static let valueNotebooksBody = NSLocalizedString(
            "onboarding.value.notebooks.body",
            value: "A calm shelf that keeps every notebook within reach.",
            comment: "Value row body — notebooks"
        )

        static let valueSearchKicker = NSLocalizedString(
            "onboarding.value.search.kicker",
            value: "Search & PDFs",
            comment: "Value row eyebrow — search"
        )
        static let valueSearchTitle = NSLocalizedString(
            "onboarding.value.search.title",
            value: "Find it in a keystroke",
            comment: "Value row title — search"
        )
        static let valueSearchBody = NSLocalizedString(
            "onboarding.value.search.body",
            value: "Surface any note, notebook, or imported PDF instantly.",
            comment: "Value row body for the search row. Active voice replaces a passive em-dash construction so the line localizes cleanly."
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
            comment: "Subscription screen eyebrow"
        )
        static let subscriptionHeadlineLine1 = NSLocalizedString(
            "onboarding.subscription.headline.line1",
            value: "Try everything,",
            comment: "Subscription headline — first line"
        )
        static let subscriptionHeadlineLine2 = NSLocalizedString(
            "onboarding.subscription.headline.line2",
            value: "free for 7 days.",
            comment: "Subscription headline — second (italic accent) line"
        )
        static let subscriptionBody = NSLocalizedString(
            "onboarding.subscription.body",
            value: "Full access while you settle in. Keep it for less than a coffee a year. Cancel anytime.",
            comment: "Subscription screen body. 'Cancel anytime' is the final, standalone sentence — the reassurance the user reads last, immediately before reaching the primary CTA."
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

        static let subscriptionPrimary = NSLocalizedString(
            "onboarding.subscription.primary",
            value: "Start free trial",
            comment: "Subscription primary CTA"
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
