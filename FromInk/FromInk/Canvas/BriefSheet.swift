import SwiftUI

struct BriefSheet: View {
    var isLoading: Bool = false
    var summary: String = ""
    @Binding var tasks: [ExtractedTask]
    var openQuestion: String? = nil
    var onDismiss: () -> Void = {}
    var onSendAll: () -> Void = {}

    private var selectedDestinationCount: Int {
        Set(tasks.flatMap(\.destinations)).count
    }

    private var primaryLabel: String {
        selectedDestinationCount == 0
            ? "Send All"
            : "Send All → \(selectedDestinationCount) Destination\(selectedDestinationCount == 1 ? "" : "s")"
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
                        if !summary.isEmpty {
                            summaryBlock
                            Rectangle().fill(Color.border).frame(height: 1)
                        }
                        taskListHeader
                        Rectangle().fill(Color.border).frame(height: 1)
                        ForEach($tasks) { $task in
                            TaskRow(index: tasks.firstIndex(where: { $0.id == task.id })! + 1,
                                    task: $task)
                            Rectangle().fill(Color.border).frame(height: 1)
                        }
                    }
                }

                if let q = openQuestion {
                    openQuestionBar(q)
                }
            }

            SheetActionFooter(
                secondary: "Edit Brief",
                primary: primaryLabel,
                secondaryAction: onDismiss,
                primaryAction: onSendAll,
                primaryDisabled: tasks.isEmpty || isLoading
            )
        }
        .background(Color.surface)
        .presentationBackground(Color.surface)
        .presentationCornerRadius(0)
        .presentationDragIndicator(.hidden)
        .presentationDetents([.large])
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.bolt)
            Text("Page Brief")
                .font(.canvasTitle)
                .foregroundStyle(Color.ink)
            Spacer()
            if !isLoading {
                Text(Date.now.formatted(date: .abbreviated, time: .omitted).uppercased() + " · GENERATED")
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
            Text("Reading your notes…")
                .font(.system(size: 15))
                .foregroundStyle(Color.inkSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Summary

    private var summaryBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .fill(Color.ink)
                .frame(width: 3)
                .padding(.vertical, 2)
            Text(summary)
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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

    // MARK: - Open question

    private func openQuestionBar(_ question: String) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.border).frame(height: 1)
            HStack(spacing: 6) {
                Text("Open question:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                Text("\(question)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSecondary)
                    .italic()
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 40)
        }
    }
}

// MARK: - Task Row

private struct TaskRow: View {
    let index: Int
    @Binding var task: ExtractedTask

    var body: some View {
        HStack(spacing: 0) {
            Text(String(format: "%02d", index))
                .font(.system(size: 12, weight: .regular).monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink)
                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            IntegrationButtonRow(destinations: $task.destinations)
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
