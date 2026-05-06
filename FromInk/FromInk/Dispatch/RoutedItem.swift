import Foundation
import SwiftData

@Model final class RoutedItem {
    var id: UUID = UUID()
    var notebookID: UUID = UUID()
    var pageIndex: Int = 0
    var sourceText: String = ""
    var routedAt: Date = Date()
    var destination: String = ""        // Integration.rawValue
    var destinationTitle: String = ""
    var destinationURL: String = ""
    var eventKitIdentifier: String? = nil
    var status: String = "sent"         // "sent" | "deleted" | "completed"

    init(
        notebookID: UUID,
        pageIndex: Int,
        sourceText: String,
        destination: String,
        destinationTitle: String,
        destinationURL: String,
        eventKitIdentifier: String? = nil
    ) {
        self.notebookID = notebookID
        self.pageIndex = pageIndex
        self.sourceText = sourceText
        self.destination = destination
        self.destinationTitle = destinationTitle
        self.destinationURL = destinationURL
        self.eventKitIdentifier = eventKitIdentifier
    }
}
