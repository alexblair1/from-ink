import SwiftUI

struct IntegrationButton: View {
    let integration: Integration
    let isSelected: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: integration.icon)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isSelected ? Color.inkOnDark : Color.inkSecondary)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.ink : Color.clear)
                .overlay(
                    Rectangle()
                        .strokeBorder(isSelected ? Color.ink : Color.border, lineWidth: 1)
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
        IntegrationButton(integration: .github, isSelected: false)
        IntegrationButton(integration: .reminders, isSelected: false)
        IntegrationButton(integration: .calendar, isSelected: true)
        IntegrationButton(integration: .mail, isSelected: false)
    }
    .padding()
    .background(Color.surface)
}
