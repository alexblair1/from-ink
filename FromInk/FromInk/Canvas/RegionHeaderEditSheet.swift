import SwiftUI

/// Modal sheet that edits a `NoteRegion`'s `headerOCRText`. Used by the
/// canvas when the user taps a region's header badge OR picks
/// "Edit header" from the manage menu. The view holds no domain state
/// — the caller binds `text`, persists on save, and dismisses on
/// cancel. Mirrors the existing `LinkInputSheet` shape so the two
/// region edit affordances feel consistent.
struct RegionHeaderEditSheet: View {
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        AppStrings.RegionIndicator.headerEditPlaceholder,
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(3...10)
                }
            }
            .navigationTitle(AppStrings.RegionIndicator.headerEditTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.RegionIndicator.headerEditCancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.RegionIndicator.headerEditSave, action: onSave)
                }
            }
        }
    }
}
