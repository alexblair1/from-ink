import SwiftUI

struct SheetActionFooter: View {
    let secondary: String
    let primary: String
    var secondaryAction: () -> Void = {}
    var primaryAction: () -> Void = {}
    var primaryDisabled: Bool = false

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(ds.colors.rule).frame(height: 1)
            HStack(spacing: 12) {
                Button(action: secondaryAction) {
                    Text(secondary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ds.colors.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .overlay(Rectangle().strokeBorder(ds.colors.rule, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: primaryAction) {
                    Text(primary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(primaryDisabled ? ds.colors.ink2 : ds.colors.paperOnInk)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(primaryDisabled ? ds.colors.rule : ds.colors.ink)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(primaryDisabled)
                .animation(.linear(duration: 0.08), value: primaryDisabled)
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
        }
        .background(ds.colors.surface)
    }
}

#Preview {
    SheetActionFooter(secondary: "Edit Brief", primary: "Send All → 3 Destinations")
}
