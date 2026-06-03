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
            // Hairline closes off the masthead so the first group
            // header doesn't feel orphaned from the title above.
            // Mirrors the IntegrationsListView title-strip treatment
            // and Dispatch's header/scroll separation.
            HairlineRule()

            ForEach(model.groups) { group in
                SettingsGroupHeader(title: group.title)
                HairlineRule()
                ForEach(group.rows) { row in
                    SettingsRowView(model: row)
                    HairlineRule()
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack {
            Text(model.title)
                .font(model.titleFont)
                .foregroundStyle(model.titleColor)

            Spacer()

            IconButton(
                "xmark",
                size: .footnote,
                color: model.closeIconColor,
                action: model.onDismiss
            )
        }
        .padding(.horizontal, model.headerHorizontalPadding)
        .padding(.vertical, model.headerVerticalPadding)
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
        case .permissions:
            PermissionsDetailView(model: model.detailModels.permissions)
        }
    }
}

// MARK: - Model

extension SettingsView {
    struct Model {
        let title: String
        let titleFont: Font
        let titleColor: Color
        let closeIconColor: Color
        let headerHorizontalPadding: CGFloat
        let headerVerticalPadding: CGFloat
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
        let rows: [SettingsRowView.Model]
    }

    struct DetailModels {
        let appearance: OptionPickerDetailView<AppearanceSetting>.Model
        let handedness: OptionPickerDetailView<Handedness>.Model
        let themes: ThemesDetailView.Model
        let permissions: PermissionsDetailView.Model
    }
}
