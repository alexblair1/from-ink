import ComposableArchitecture
import SwiftUI

/// Bridge from `SettingsFeature` store into the stateless
/// `SettingsView.Model`. Single source of truth for translating
/// store shape → flat view fields. The view file is TCA-free.
///
extension SettingsView.Model {
    init(store: StoreOf<SettingsFeature>) {
        let onDismiss: () -> Void = { store.send(.dismissTapped) }
        let onBack: () -> Void = { store.send(.backTapped) }
        let backLabel = AppStrings.Settings.title

        self.title = AppStrings.Settings.title
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

        // Status hints — live values for settings that have meaningful
        // current state, nil for stubs. The design's "do I need to
        // look in here?" principle applied: only show prose when
        // it answers something.
        let appearanceStatus: StatusHint = .neutral(store.appearance.label)
        let handednessStatus: StatusHint = .neutral(store.handedness.label)

        self.groups = [
            SettingsView.Group(
                id: "editor",
                title: AppStrings.Settings.groupEditor,
                rows: [
                    SettingsRow.Model(
                        id: .appearance,
                        title: AppStrings.Settings.appearance,
                        statusHint: appearanceStatus,
                        onTap: { store.send(.destinationTapped(.appearance)) }
                    ),
                    SettingsRow.Model(
                        id: .handedness,
                        title: AppStrings.Settings.handedness,
                        statusHint: handednessStatus,
                        onTap: { store.send(.destinationTapped(.handedness)) }
                    ),
                    SettingsRow.Model(
                        id: .themes,
                        title: AppStrings.Settings.themes,
                        statusHint: nil,
                        onTap: { store.send(.destinationTapped(.themes)) }
                    ),
                ]
            ),
            SettingsView.Group(
                id: "yourData",
                title: AppStrings.Settings.groupYourData,
                rows: [
                    SettingsRow.Model(
                        id: .integrations,
                        title: AppStrings.Settings.integrations,
                        statusHint: nil,
                        onTap: { store.send(.destinationTapped(.integrations)) }
                    ),
                    SettingsRow.Model(
                        id: .permissions,
                        title: AppStrings.Settings.permissions,
                        statusHint: nil,
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
        let integrationsHeader = SettingsDetailHeader.Model(
            title: AppStrings.Settings.integrations,
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
            integrations: IntegrationsListView.Model(
                store: store.scope(state: \.integrations, action: \.integrations),
                header: integrationsHeader
            ),
            permissions: PermissionsDetailView.Model(
                header: permissionsHeader,
                emptyTitle: AppStrings.Settings.permissionsEmptyTitle,
                emptyBody: AppStrings.Settings.permissionsEmptyBody
            )
        )
    }
}
