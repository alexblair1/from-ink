import SwiftUI
import EventKit
import EventKitUI

/// Wraps EKEventEditViewController for the vague-deadline calendar routing path.
/// EKEventEditViewController cannot be styled — system Calendar appearance only.
/// This is acceptable here because user input is required to supply the exact time.
struct EventEditView: UIViewControllerRepresentable {
    let taskTitle: String
    var onSave: (RoutingResult) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSave: onSave, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        // Store is retained on the coordinator so it outlives the VC.
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = taskTitle
        event.startDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        event.endDate = event.startDate.addingTimeInterval(3600)
        event.notes = "From From Ink"

        let vc = EKEventEditViewController()
        vc.event = event
        vc.eventStore = store
        vc.editViewDelegate = context.coordinator
        context.coordinator.store = store
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        var store: EKEventStore?
        var onSave: (RoutingResult) -> Void
        var onCancel: () -> Void

        init(onSave: @escaping (RoutingResult) -> Void, onCancel: @escaping () -> Void) {
            self.onSave = onSave
            self.onCancel = onCancel
        }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            controller.dismiss(animated: true)
            switch action {
            case .saved:
                guard let event = controller.event else { onCancel(); return }
                let startDate: Date = event.startDate ?? .now
                onSave(RoutingResult(
                    integration: .calendar,
                    destinationURL: "calshow://\(startDate.timeIntervalSince1970)",
                    eventKitIdentifier: event.eventIdentifier
                ))
            case .canceled, .deleted:
                onCancel()
            @unknown default:
                onCancel()
            }
        }
    }
}
