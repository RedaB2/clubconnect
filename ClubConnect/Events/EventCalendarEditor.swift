import EventKit
import EventKitUI
import SwiftUI

/// EventKitUI owns calendar selection, confirmation and the write on iOS 17 and later.
struct EventCalendarEditor: UIViewControllerRepresentable {
    let title: String
    let start: Date
    let end: Date
    let location: String
    let notes: String
    let url: URL?
    let onDismiss: () -> Void

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let eventStore = EKEventStore()
        let dismiss: () -> Void

        init(dismiss: @escaping () -> Void) {
            self.dismiss = dismiss
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = context.coordinator.eventStore
        let entry = EKEvent(eventStore: store)
        entry.title = title
        entry.startDate = start
        entry.endDate = end
        entry.location = location
        entry.notes = notes
        entry.url = url

        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = entry
        editor.editViewDelegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
}
