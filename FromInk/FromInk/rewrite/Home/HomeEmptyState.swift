import SwiftUI

/// Empty state shown when there are no folders or notebooks yet.
/// Editorial tone — invites the user to create their first notebook.
///
struct HomeEmptyState: View {
    let onCreateNotebook: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 48)

            Image(systemName: "book.closed")
                .font(.system(size: 36, weight: .ultraLight))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color("ink/Ink3"))

            VStack(spacing: 6) {
                Text("Start writing")
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .foregroundStyle(Color("ink/Ink"))

                Text("Create your first notebook to begin.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color("ink/Ink2"))
            }

            InkButton("New Notebook", style: .filled, icon: "plus", action: onCreateNotebook)
                .padding(.top, 4)

            Spacer().frame(height: 48)
        }
        .frame(maxWidth: .infinity)
    }
}
