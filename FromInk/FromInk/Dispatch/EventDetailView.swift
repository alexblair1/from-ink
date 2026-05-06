import SwiftUI
import EventKit
import EventKitUI

/// Wraps EKEventViewController for re-opening a Calendar event from dispatch history.
/// Fetches the live event by identifier — shows a "deleted" message if the event no longer exists.
struct EventDetailView: UIViewControllerRepresentable {
    let eventIdentifier: String
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let store = EKEventStore()
        context.coordinator.store = store

        guard let event = store.event(withIdentifier: eventIdentifier) else {
            let vc = EventDeletedViewController()
            vc.onDismiss = onDismiss
            return UINavigationController(rootViewController: vc)
        }

        let vc = EKEventViewController()
        vc.event = event
        vc.allowsEditing = true
        vc.delegate = context.coordinator
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, EKEventViewDelegate {
        var store: EKEventStore?
        var onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func eventViewController(
            _ controller: EKEventViewController,
            didCompleteWith action: EKEventViewAction
        ) {
            onDismiss()
        }
    }
}

// MARK: - Deleted state

private final class EventDeletedViewController: UIViewController {
    var onDismiss: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "This event was deleted from Calendar."
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in self?.onDismiss?() }
        )
    }
}
