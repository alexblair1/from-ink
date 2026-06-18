#if DEBUG
import SwiftUI

struct ExtractionDebugSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let log = ExtractionDebugLog.shared
    @State private var selectedRunID: UUID? = nil

    private let ds = DesignSystem.standard

    private var displayRun: ExtractionDebugLog.Run? {
        if let id = selectedRunID { return log.runs.first { $0.id == id } }
        return log.runs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ds.colors.rule).frame(height: 1)

            if log.runs.isEmpty {
                emptyState
            } else {
                if log.runs.count > 1 { runPicker }
                entryList
            }
        }
        .background(ds.colors.surface)
        .presentationBackground(ds.colors.surface)
        .presentationCornerRadius(0)
        .presentationDragIndicator(.hidden)
        .presentationDetents([.medium, .large])
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "ant")
                .font(.system(size: 13))
                .foregroundStyle(ds.colors.ink2)
            Text("Extraction Debug")
                .font(.system(size: 17, weight: .medium, design: .serif))
                .foregroundStyle(ds.colors.ink)
            Spacer()
            if !log.runs.isEmpty {
                Button("Clear") {
                    log.clear()
                    selectedRunID = nil
                }
                .font(.system(size: 13))
                .foregroundStyle(ds.colors.ink2)
            }
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ds.colors.ink2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    // MARK: - Run picker

    private var runPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(log.runs) { run in
                    let isSelected = (selectedRunID ?? log.runs.first?.id) == run.id
                    Button {
                        selectedRunID = run.id
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.scope)
                                .font(.system(size: 11, weight: .semibold))
                            Text(run.startedAt.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(isSelected ? ds.colors.paperOnInk : ds.colors.ink2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isSelected ? ds.colors.ink : ds.colors.paper, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(ds.colors.paper.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(ds.colors.rule).frame(height: 1)
        }
    }

    // MARK: - Entry list

    private var entryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(ExtractionDebugLog.Entry.Phase.allCases, id: \.self) { phase in
                    let entries = displayRun?.entries.filter { $0.phase == phase } ?? []
                    if !entries.isEmpty {
                        Section {
                            ForEach(entries) { entry in
                                EntryRow(entry: entry)
                                Rectangle().fill(ds.colors.rule).frame(height: 1)
                            }
                        } header: {
                            sectionHeader(phase.rawValue, count: entries.count)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ds.colors.ink2)
                .textCase(.uppercase)
                .kerning(0.5)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(ds.colors.ink2)
        }
        .padding(.horizontal, 20)
        .frame(height: 32)
        .background(ds.colors.paper.opacity(0.6))
        .overlay(alignment: .bottom) {
            Rectangle().fill(ds.colors.rule).frame(height: 1)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "ant")
                .font(.system(size: 32))
                .foregroundStyle(ds.colors.ink2.opacity(0.4))
            Text("No extractions yet")
                .font(.system(size: 15))
                .foregroundStyle(ds.colors.ink2)
            Text("Tap the bolt or use two-finger lasso to run the pipeline.")
                .font(.system(size: 13))
                .foregroundStyle(ds.colors.ink2.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Entry row

private struct EntryRow: View {
    let entry: ExtractionDebugLog.Entry
    @State private var expanded = false

    private let ds = DesignSystem.standard

    private var accentColor: Color {
        if entry.isError { return .red }
        if entry.isWarning { return .orange }
        return ds.colors.ink2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.linear(duration: 0.1)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 6, height: 6)
                    Text(entry.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(entry.isError ? .red : entry.isWarning ? .orange : ds.colors.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(ds.colors.ink2)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(entry.content.isEmpty ? "(empty)" : entry.content)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(ds.colors.ink.opacity(0.85))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(ds.colors.paper.opacity(0.4))
            }
        }
    }
}

#Preview {
    DesignSystem.standard.colors.paper.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ExtractionDebugSheet()
        }
}
#endif
