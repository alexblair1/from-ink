import SwiftUI

/// Section divider with mono label, count, and optional trailing action.
///
///     SectionHeader("Notebooks", count: 3)
///     SectionHeader("Folders", count: 5, action: ("View all", viewAll))
///     SectionHeader("Recent", count: 12, trailing: { Image(systemName: "plus") })
///
struct SectionHeader<Trailing: View>: View {
    let title: String
    let count: Int?
    let action: (label: String, handler: () -> Void)?
    let trailing: () -> Trailing

    init(
        _ title: String,
        count: Int? = nil,
        action: (String, () -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.count = count
        if let action {
            self.action = (action.0, action.1)
        } else {
            self.action = nil
        }
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            HairlineRule()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                MonoLabel(title, color: Color("ink/Ink2"))

                if let count {
                    MonoLabel("· \(count)", color: Color("ink/Ink3"))
                }

                Spacer()

                if let action {
                    Button(action: action.handler) {
                        MonoLabel("\(action.label) →", color: Color("ink/Ink"))
                    }
                    .buttonStyle(.plain)
                }

                trailing()
            }
            .padding(.vertical, 12)
        }
    }
}
