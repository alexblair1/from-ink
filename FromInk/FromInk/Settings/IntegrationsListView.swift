import SwiftUI

/// The Integrations sub-screen — header, count chip, provider
/// sections (Linear, Slack), and an optional "Make default?" prompt
/// card pinned below the list after a new account is added.
///
/// Feature view: zero TCA imports. State + callbacks flow through
/// `Model`, which is constructed by `IntegrationsListView+Adapter`
/// from a `StoreOf<IntegrationsFeature>`.
///
/// Replaces the prior `IntegrationsDetailView` stub.
///
struct IntegrationsListView: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsDetailHeader(model: model.header)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleStrip
                        .padding(.horizontal, ds.spacing.base)
                        .padding(.top, ds.spacing.md)
                        .padding(.bottom, ds.spacing.base)

                    ForEach(model.providerSections) { section in
                        IntegrationProviderSection(model: section)
                            .padding(.bottom, ds.spacing.md)
                    }

                    if let prompt = model.defaultPromptCard {
                        IntegrationDefaultPromptCard(model: prompt)
                            .padding(.top, ds.spacing.xs)
                    }
                }
                .padding(.horizontal, ds.spacing.base)
                .padding(.bottom, ds.spacing.xxl)
            }
        }
    }

    /// Bottom-aligned title row — serif `Integrations.` on the left,
    /// mono "<connected> of <total>" count chip on the right. Sits
    /// above a hairline rule, same shape as the design's c-head.
    private var titleStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(model.title)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(ds.colors.ink)

                Spacer()

                MonoLabel(model.countChip, color: ds.colors.ink2)
            }
            .padding(.bottom, ds.spacing.base)

            HairlineRule()
        }
    }
}

// MARK: - Model

extension IntegrationsListView {
    struct Model {
        let header: SettingsDetailHeader.Model
        let title: String
        let countChip: String
        let providerSections: [IntegrationProviderSection.Model]
        let defaultPromptCard: IntegrationDefaultPromptCard.Model?
    }
}
