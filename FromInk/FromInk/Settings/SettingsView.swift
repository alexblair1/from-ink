import SwiftUI

/// Settings sheet content — title + two-group row list, with detail
/// screens pushed via `NavigationStack`.
///
/// The outer presentation chrome (sheet shape, backdrop, corner
/// radius, height detent) is owned by the parent (`HomeWiringView`'s
/// `.sheet` modifier) — this view assumes it's already inside that
/// sheet. No scrim, no centered card here.
///
/// Navigation uses `NavigationStack` with `.navigationDestination(
/// item:)` driving pushes from `store.destination`. The system nav
/// bar is hidden in favor of our custom `SettingsDetailHeader`,
/// which carries the back chevron + title + close X.
///
/// Feature view: zero TCA imports. All store binding happens in
/// `SettingsView+Adapter.swift`.
///
struct SettingsView: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        NavigationStack {
            rootList
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: model.destinationBinding) { destination in
                    detail(for: destination)
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
    }

    // MARK: - Root list (groups + rows)

    private var rootList: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ForEach(model.groups) { group in
                SettingsGroupHeader(title: group.title)
                ForEach(group.rows) { row in
                    SettingsRow(model: row)
                    HairlineRule()
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack {
            Text(model.title)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(ds.colors.ink)

            Spacer()

            IconButton("xmark", size: .footnote, color: ds.colors.ink2, action: model.onDismiss)
        }
        .padding(.horizontal, ds.spacing.base)
        .padding(.vertical, ds.spacing.md)
    }

    // MARK: - Detail screens (pushed via NavigationStack)

    @ViewBuilder
    private func detail(for destination: SettingsDestination) -> some View {
        switch destination {
        case .appearance:
            OptionPickerDetailView(model: model.detailModels.appearance)
        case .handedness:
            OptionPickerDetailView(model: model.detailModels.handedness)
        case .themes:
            ThemesDetailView(model: model.detailModels.themes)
        case .integrations:
            IntegrationsListView(model: model.detailModels.integrations)
        case .permissions:
            PermissionsDetailView(model: model.detailModels.permissions)
        }
    }
}

// MARK: - Model

extension SettingsView {
    struct Model {
        let title: String
        let groups: [Group]
        let onDismiss: () -> Void

        /// Two-way binding for `NavigationStack`'s
        /// `.navigationDestination(item:)`. Set by the system when
        /// the user pops via back chevron or swipe gesture; read
        /// when the reducer pushes a destination.
        let destinationBinding: Binding<SettingsDestination?>

        /// Detail Models are built up-front in the adapter — view
        /// picks the one matching the pushed destination. Cheap
        /// (just enum-case construction); avoids switching the
        /// destination → Model resolution into the view layer.
        let detailModels: DetailModels
    }

    struct Group: Identifiable {
        let id: String          // stable key, NOT the localized title
        let title: String       // localized header text
        let rows: [SettingsRow.Model]
    }

    struct DetailModels {
        let appearance: OptionPickerDetailView<AppearanceSetting>.Model
        let handedness: OptionPickerDetailView<Handedness>.Model
        let themes: ThemesDetailView.Model
        let integrations: IntegrationsListView.Model
        let permissions: PermissionsDetailView.Model
    }
}
