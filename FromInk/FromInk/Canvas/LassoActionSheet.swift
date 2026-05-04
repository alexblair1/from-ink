import SwiftUI

struct LassoActionSheet: View {
    var isLoading: Bool = false
    var task: InkTask = InkTask(title: "")
    var onDismiss: () -> Void = {}
    var onSend: (InkTask) -> Void = { _ in }

    @State private var editableTask = InkTask(title: "")

    private var selectedCount: Int { editableTask.destinations.count }
    private var primaryLabel: String {
        selectedCount == 0
            ? "Send"
            : "Send → \(selectedCount) Destination\(selectedCount == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.border).frame(height: 1)

            if isLoading {
                loadingState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        taskListHeader
                        Rectangle().fill(Color.border).frame(height: 1)
                        taskRow
                        Rectangle().fill(Color.border).frame(height: 1)
                    }
                }
            }

            SheetActionFooter(
                secondary: "Cancel",
                primary: primaryLabel,
                secondaryAction: onDismiss,
                primaryAction: { onSend(editableTask) },
                primaryDisabled: editableTask.destinations.isEmpty || isLoading
            )
        }
        .background(Color.surface)
        .presentationBackground(Color.surface)
        .presentationCornerRadius(0)
        .presentationDragIndicator(.hidden)
        .presentationDetents([.large])
        .onAppear { editableTask = task }
        .onChange(of: task) { _, newTask in editableTask = newTask }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "lasso")
                .font(.system(size: 13))
                .foregroundStyle(Color.ink)
            Text("Task Brief")
                .font(.canvasTitle)
                .foregroundStyle(Color.ink)
            Spacer()
            if !isLoading {
                Text(Date.now.formatted(date: .abbreviated, time: .omitted).uppercased() + " · SELECTED")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkSecondary)
                    .kerning(0.3)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Reading your ink…")
                .font(.system(size: 15))
                .foregroundStyle(Color.inkSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Task list header

    private var taskListHeader: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 36, alignment: .leading)
            Text("Task")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Send To")
                .frame(width: 148, alignment: .center)
            Text("Status")
                .frame(width: 72, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.inkSecondary)
        .textCase(.uppercase)
        .kerning(0.5)
        .padding(.horizontal, 20)
        .frame(height: 36)
        .background(Color.canvas.opacity(0.5))
    }

    // MARK: - Task row

    private var taskRow: some View {
        HStack(spacing: 0) {
            Text("01")
                .font(.system(size: 12, weight: .regular).monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(editableTask.title.isEmpty ? "No text recognized" : editableTask.title)
                    .font(.system(size: 15))
                    .foregroundStyle(editableTask.title.isEmpty ? Color.inkSecondary : Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !editableTask.detail.isEmpty {
                    Text(editableTask.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            IntegrationButtonRow(destinations: $editableTask.destinations)
                .frame(width: 148, alignment: .center)

            Text("Pending")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
                .textCase(.uppercase)
                .kerning(0.3)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    Color.canvas.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            LassoActionSheet(
                task: InkTask(title: "Call John about the Q3 report", detail: "Due Fri")
            )
        }
}
