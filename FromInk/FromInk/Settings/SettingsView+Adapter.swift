import ComposableArchitecture
import SwiftUI

/// Bridge from `SettingsFeature` store into the stateless
/// `SettingsView.Model`. Single source of truth for translating
/// store shape → flat view fields. The view file is TCA-free.
///
extension SettingsView.Model {
    init(store: StoreOf<SettingsFeature>, ds: DesignSystem = .standard) {
        let onDismiss: () -> Void = { store.send(.dismissTapped) }
        let onBack: () -> Void = { store.send(.backTapped) }
        let backLabel = AppStrings.Settings.title

        self.title = AppStrings.Settings.title
        self.titleFont = .system(size: 28, weight: .regular, design: .serif)
        self.titleColor = ds.colors.ink
        self.closeIconColor = ds.colors.ink2
        self.headerHorizontalPadding = ds.spacing.lg
        self.headerVerticalPadding = ds.spacing.md
        self.onDismiss = onDismiss

        // Binding that drives NavigationStack's
        // `.navigationDestination(item:)`. SwiftUI sets it to nil
        // when the user pops via back chevron or swipe-back; the
        // reducer sets it to a non-nil destination when a row is
        // tapped.
        self.destinationBinding = Binding(
            get: { store.destination },
            set: { newDestination in
                if let newDestination {
                    store.send(.destinationTapped(newDestination))
                } else {
                    store.send(.backTapped)
                }
            }
        )

        // Secondary text — neutral prose values that summarize the
        // current setting at a glance (the "do I need to look in
        // here?" answer). Nil for stubs without meaningful state.
        let appearanceLabel = store.appearance.label
        let handednessLabel = store.handedness.label

        self.groups = [
            SettingsView.Group(
                id: "editor",
                title: AppStrings.Settings.groupEditor,
                rows: [
                    SettingsRowView.Model(
                        id: SettingsDestination.appearance.rawValue,
                        title: AppStrings.Settings.appearance,
                        secondaryText: appearanceLabel,
                        onTap: { store.send(.destinationTapped(.appearance)) }
                    ),
                    SettingsRowView.Model(
                        id: SettingsDestination.handedness.rawValue,
                        title: AppStrings.Settings.handedness,
                        secondaryText: handednessLabel,
                        onTap: { store.send(.destinationTapped(.handedness)) }
                    ),
                    SettingsRowView.Model(
                        id: SettingsDestination.themes.rawValue,
                        title: AppStrings.Settings.themes,
                        onTap: { store.send(.destinationTapped(.themes)) }
                    ),
                ]
            ),
            SettingsView.Group(
                id: "yourData",
                title: AppStrings.Settings.groupYourData,
                rows: [
                    SettingsRowView.Model(
                        id: SettingsDestination.permissions.rawValue,
                        title: AppStrings.Settings.permissions,
                        onTap: { store.send(.destinationTapped(.permissions)) }
                    ),
                ]
            ),
        ]

        // Detail Models — built up-front so the view's
        // `.navigationDestination` switch is a pure lookup. Cheap.
        let appearanceHeader = SettingsDetailHeader.Model(
            title: AppStrings.Settings.appearance,
            backLabel: backLabel,
            onBack: onBack,
            onDismiss: onDismiss
        )
        let handednessHeader = SettingsDetailHeader.Model(
            title: AppStrings.Settings.handedness,
            backLabel: backLabel,
            onBack: onBack,
            onDismiss: onDismiss
        )
        let themesHeader = SettingsDetailHeader.Model(
            title: AppStrings.Settings.themes,
            backLabel: backLabel,
            onBack: onBack,
            onDismiss: onDismiss
        )
        let permissionsHeader = SettingsDetailHeader.Model(
            title: AppStrings.Settings.permissions,
            backLabel: backLabel,
            onBack: onBack,
            onDismiss: onDismiss
        )

        self.detailModels = SettingsView.DetailModels(
            appearance: OptionPickerDetailView<AppearanceSetting>.Model(
                header: appearanceHeader,
                options: AppearanceSetting.allCases.map { value in
                    OptionPickerDetailView<AppearanceSetting>.Option(
                        value: value,
                        label: value.label,
                        isSelected: value == store.appearance
                    )
                },
                onSelect: { store.send(.appearanceChanged($0)) }
            ),
            handedness: OptionPickerDetailView<Handedness>.Model(
                header: handednessHeader,
                options: Handedness.allCases.map { value in
                    OptionPickerDetailView<Handedness>.Option(
                        value: value,
                        label: value.label,
                        isSelected: value == store.handedness
                    )
                },
                onSelect: { store.send(.handednessChanged($0)) }
            ),
            themes: ThemesDetailView.Model(
                header: themesHeader,
                emptyTitle: AppStrings.Settings.themesEmptyTitle,
                emptyBody: AppStrings.Settings.themesEmptyBody
            ),
            permissions: PermissionsDetailView.Model(
                store: store.scope(state: \.permissions, action: \.permissions),
                header: permissionsHeader
            )
        )
    }
}

// MARK: - Permissions adapter

extension PermissionsDetailView.Model {
    /// Bridges `PermissionsFeature` state into the stateless detail view.
    /// Each row carries its current status label/color, a CTA hint, and
    /// a tap closure routed to the right child action. `onAppear` and
    /// `onSceneBecameActive` keep the rows live across navigation and
    /// system-Settings round-trips. All visuals resolve here, in the
    /// init, off `DesignSystem` — the view reads only flat fields.
    init(
        store: StoreOf<PermissionsFeature>,
        header: SettingsDetailHeader.Model,
        ds: DesignSystem = .standard
    ) {
        self.header = header

        let calendar = store.calendar
        let reminders = store.reminders

        self.rows = [
            PermissionsDetailView.Row(
                id: "calendar",
                icon: "calendar",
                title: AppStrings.Settings.permissionCalendar,
                body: AppStrings.Settings.permissionCalendarDescription,
                statusLabel: calendar.statusLabel,
                statusColor: calendar.statusColor(ds: ds),
                cta: calendar.ctaLabel,
                onTap: { store.send(.calendarRowTapped) }
            ),
            PermissionsDetailView.Row(
                id: "reminders",
                icon: "checklist",
                title: AppStrings.Settings.permissionReminders,
                body: AppStrings.Settings.permissionRemindersDescription,
                statusLabel: reminders.statusLabel,
                statusColor: reminders.statusColor(ds: ds),
                cta: reminders.ctaLabel,
                onTap: { store.send(.remindersRowTapped) }
            ),
        ]

        // Layout
        self.headerLineSpacing = ds.spacing.xs
        self.titleRowSpacing = ds.spacing.md
        self.horizontalPadding = ds.spacing.lg
        self.verticalPadding = ds.spacing.md
        self.iconFrame = ds.layout.iconFrame
        // Body + CTA align past the leading icon column.
        self.bodyIndent = ds.layout.iconFrame + ds.spacing.md
        // Typography
        self.iconFont = .system(size: 17)
        self.titleFont = .system(size: 17, weight: .regular, design: .serif)
        self.bodyFont = .system(size: 13, weight: .regular, design: .serif)
        self.statusSize = 10
        self.ctaSize = 10
        // Colors
        self.iconColor = ds.colors.ink2
        self.titleColor = ds.colors.ink
        self.bodyColor = ds.colors.ink2
        self.ctaColor = ds.colors.ink3
        // Lifecycle
        self.onAppear = { store.send(.appeared) }
        self.onSceneBecameActive = { store.send(.sceneBecameActive) }
    }
}
