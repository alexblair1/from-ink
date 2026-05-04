import SwiftUI

struct LinkInputSheet: View {
    var isLoading: Bool
    var recognizedText: String
    var onConfirm: (URL) -> Void
    var onDismiss: () -> Void

    @State private var urlText = ""
    @FocusState private var urlFieldFocused: Bool

    private var parsedURL: URL? {
        var raw = urlText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "https://\(raw)" }
        return URL(string: raw)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Linked text") {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Recognizing…")
                                .foregroundStyle(.secondary)
                        }
                    } else if recognizedText.isEmpty {
                        Text("No text recognized")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(recognizedText)
                            .font(.body)
                    }
                }

                Section("URL") {
                    TextField("https://", text: $urlText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($urlFieldFocused)
                }
            }
            .navigationTitle("Add Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let url = parsedURL else { return }
                        onConfirm(url)
                    }
                    .disabled(parsedURL == nil)
                }
            }
            .onAppear { urlFieldFocused = !isLoading }
            .onChange(of: isLoading) { _, loading in
                if !loading { urlFieldFocused = true }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
