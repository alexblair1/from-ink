import SwiftUI
import SwiftData
import EventKit

private enum PanelTab: String, CaseIterable {
    case headers   = "Headers"
    case links     = "Links"
    case calendar  = "Calendar"
    case reminders = "Reminders"

    var icon: String {
        switch self {
        case .headers:   return "bookmark.fill"
        case .links:     return "link"
        case .calendar:  return "calendar"
        case .reminders: return "bell"
        }
    }
}

struct HeaderPanel: View {
    let headers: [CanvasHeader]
    let links: [CanvasLink]
    let toolbarOnLeft: Bool
    let notebookID: UUID
    let pageIndex: Int
    let onNavigate: (CanvasHeader) -> Void
    let onOpenLink: (URL) -> Void
    let onDismiss: () -> Void
    
    
    // TODO: Can the reducer own the query? Does this have to live inside of the view?
    @Query(sort: \RoutedItem.routedAt, order: .reverse) private var allRoutedItems: [RoutedItem]
    // TODO: At state should be driven the reducer
    @State private var selectedTab: PanelTab = .headers
    @State private var selectedCalendarEventID: String? = nil

    private var sorted: [CanvasHeader] {
        headers.sorted { $0.contentRect.minY < $1.contentRect.minY }
    }

    private var calendarItems: [RoutedItem] {
        allRoutedItems.filter {
            $0.notebookID == notebookID &&
            $0.pageIndex == pageIndex &&
            $0.destination == Integration.calendar.rawValue
        }
    }

    private var reminderItems: [RoutedItem] {
        allRoutedItems.filter {
            $0.notebookID == notebookID &&
            $0.pageIndex == pageIndex &&
            $0.destination == Integration.reminders.rawValue
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Rectangle().fill(Color.border).frame(height: 1)
            tabBar
            Rectangle().fill(Color.border).frame(height: 1)
            content
        }
        .frame(width: 420)
        .frame(maxHeight: .infinity)
        .background(Color.surface)
        .overlay(alignment: toolbarOnLeft ? .leading : .trailing) {
            Rectangle().fill(Color.border).frame(width: 1)
        }
        .sheet(isPresented: Binding(
            get: { selectedCalendarEventID != nil },
            set: { if !$0 { selectedCalendarEventID = nil } }
        )) {
            if let id = selectedCalendarEventID {
                EventDetailView(
                    eventIdentifier: id,
                    onDismiss: { selectedCalendarEventID = nil }
                )
                .ignoresSafeArea()
            }
        }
        .task(id: allRoutedItems.count) {
            guard
                EKEventStore.authorizationStatus(for: .event) == .fullAccess ||
                EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
            else {
                return
            }
            let ekStore = EKEventStore()
            for item in calendarItems + reminderItems {
                guard let identifier = item.eventKitIdentifier else { continue }
                
                switch item.destination {
                case Integration.calendar.rawValue:
                    if ekStore.event(withIdentifier: identifier) == nil {
                        // TODO: Can we avoid this by adapting models to idiomatic swift? instead of setting raw strings?
                        item.status = "deleted"
                    }
                case Integration.reminders.rawValue:
                    if (ekStore.calendarItem(withIdentifier: identifier)) == nil {
                        item.status = "deleted"
                    }
                default: break
                }
            }
        }
    }

    // MARK: - Title bar
    
    
    // TODO: Magic numbers everywhere
    private var titleBar: some View {
        HStack {
            Text(selectedTab.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
                .textCase(.uppercase)
                .kerning(0.5)
                .animation(.none, value: selectedTab)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.linear(duration: 0.08)) { selectedTab = tab }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 15, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.inkOnDark : Color.inkSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isSelected ? Color.ink : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if tab != PanelTab.allCases.last {
                    Rectangle().fill(Color.border).frame(width: 1)
                }
            }
        }
        .frame(height: 44)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .headers:
            headersContent
        case .links:
            linksContent
        case .calendar:
            routedItemsList(items: calendarItems, emptyMessage: "No calendar events yet")
        case .reminders:
            routedItemsList(items: reminderItems, emptyMessage: "No reminders yet")
        }
    }

    // MARK: - Headers tab

    private var headersContent: some View {
        Group {
            if sorted.isEmpty {
                emptyState("No headers yet")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(sorted) { header in
                            HeaderCell(header: header) { onNavigate(header) }
                            Rectangle()
                                .fill(Color.border)
                                .frame(height: 1)
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Links tab

    private var linksContent: some View {
        Group {
            if links.isEmpty {
                emptyState("No links yet")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(links) { link in
                            linkRow(link)
                            Rectangle()
                                .fill(Color.border)
                                .frame(height: 1)
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private func linkRow(_ link: CanvasLink) -> some View {
        Button { onOpenLink(link.url) } label: {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    if !link.recognizedText.isEmpty {
                        Text(link.recognizedText)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                    }
                    Text(link.url.host() ?? link.url.absoluteString)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(HeaderCellButtonStyle())
    }

    // MARK: - Routed items list (Calendar / Reminders tabs)

    private func routedItemsList(items: [RoutedItem], emptyMessage: String) -> some View {
        Group {
            if items.isEmpty {
                emptyState(emptyMessage)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            routedItemRow(item)
                            Rectangle()
                                .fill(Color.border)
                                .frame(height: 1)
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func routedItemRow(_ item: RoutedItem) -> some View {
        let isDeleted = item.status == "deleted"

        Button { openItem(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: isDeleted ? "xmark.circle" : "checkmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isDeleted ? Color.inkSecondary.opacity(0.4) : Color.inkSecondary)
                    .frame(width: 18)

                Text(item.destinationTitle.isEmpty ? item.sourceText : item.destinationTitle)
                    .font(.system(size: 14))
                    .foregroundStyle(isDeleted ? Color.inkSecondary.opacity(0.5) : Color.ink)
                    .lineLimit(1)
                    .strikethrough(isDeleted)

                Spacer()

                Text(item.routedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(HeaderCellButtonStyle())
        .disabled(isDeleted)
    }

    // MARK: - Empty state

    private func emptyState(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.inkSecondary.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Open routed item

    private func openItem(_ item: RoutedItem) {
        switch item.destination {
        case Integration.calendar.rawValue:
            if let id = item.eventKitIdentifier {
                selectedCalendarEventID = id
            }
        default:
            if let url = URL(string: item.destinationURL) {
                UIApplication.shared.open(url)
            }
        }
    }
}
