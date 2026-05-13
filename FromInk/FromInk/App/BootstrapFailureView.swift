import SwiftUI

/// Shown when a required bootstrap stage fails (storage unavailable).
/// Offers retry and a visual error message. No TCA — receives callbacks.
///
struct BootstrapFailureView: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        ZStack {
            ds.colors.paper
                .ignoresSafeArea()

            VStack(spacing: ds.spacing.xl) {
                Image(systemName: model.icon)
                    .font(.system(size: 40))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(ds.colors.ink)

                VStack(spacing: ds.spacing.sm) {
                    Text(model.title)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(ds.colors.ink)

                    Text(model.message)
                        .font(.system(.body, design: .default))
                        .foregroundStyle(ds.colors.ink2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }

                Button(action: model.onRetry) {
                    Text(model.retryLabel)
                        .font(.system(.body, design: .default, weight: .medium))
                        .foregroundStyle(ds.colors.paperOnInk)
                        .padding(.horizontal, ds.spacing.xl)
                        .padding(.vertical, ds.spacing.md)
                        .background(ds.colors.ink)
                }
            }
        }
    }
}

extension BootstrapFailureView {
    struct Model {
        let icon: String
        let title: String
        let message: String
        let retryLabel: String
        let onRetry: () -> Void
    }
}
