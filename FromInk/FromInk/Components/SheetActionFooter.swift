import SwiftUI

struct SheetActionFooter: View {
    let secondary: String
    let primary: String
    var secondaryAction: () -> Void = {}
    var primaryAction: () -> Void = {}
    var primaryDisabled: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.border).frame(height: 1)
            HStack(spacing: 12) {
                Button(action: secondaryAction) {
                    Text(secondary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .overlay(Rectangle().strokeBorder(Color.border, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: primaryAction) {
                    Text(primary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(primaryDisabled ? Color.inkSecondary : Color.inkOnDark)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(primaryDisabled ? Color.border : Color.ink)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(primaryDisabled)
                .animation(.linear(duration: 0.08), value: primaryDisabled)
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
        }
        .background(Color.surface)
    }
}

#Preview {
    SheetActionFooter(secondary: "Edit Brief", primary: "Send All → 3 Destinations")
}
