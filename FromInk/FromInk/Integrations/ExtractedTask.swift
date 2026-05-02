import Foundation

struct ExtractedTask: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var destinations: Set<Integration> = []
}
