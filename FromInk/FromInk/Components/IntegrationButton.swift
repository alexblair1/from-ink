import SwiftUI

struct IntegrationButton: View {
    let integration: Integration
    let isSelected: Bool
    var action: () -> Void = {}

    private let ds = DesignSystem.standard

    var body: some View {
        Button(action: action) {
            Image(systemName: integration.icon)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isSelected ? ds.colors.paperOnInk : ds.colors.ink2)
                .frame(width: 28, height: 28)
                .background(isSelected ? ds.colors.ink : Color.clear)
                .overlay(
                    Rectangle()
                        .strokeBorder(isSelected ? ds.colors.ink : ds.colors.rule, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.linear(duration: 0.08), value: isSelected)
    }
}

/// A horizontal row of all integration buttons for a single task
struct IntegrationButtonRow: View {
    @Binding var destinations: Set<Integration>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Integration.allCases, id: \.self) { integration in
                IntegrationButton(
                    integration: integration,
                    isSelected: destinations.contains(integration)
                ) {
                    if destinations.contains(integration) {
                        destinations.remove(integration)
                    } else {
                        destinations.insert(integration)
                    }
                }
            }
        }
    }
}

#Preview {
    HStack(spacing: 4) {
        IntegrationButton(integration: .linear, isSelected: true)
        IntegrationButton(integration: .slack, isSelected: false)
        IntegrationButton(integration: .reminders, isSelected: false)
        IntegrationButton(integration: .calendar, isSelected: true)
        IntegrationButton(integration: .mail, isSelected: false)
    }
    .padding()
    .background(DesignSystem.standard.colors.surface)
}
