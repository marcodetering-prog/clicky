import AppKit
import Foundation

@MainActor
final class MacToolApprovalPresenter {
    func requestApproval(title: String, message: String, details: String? = nil) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = details.map { "\(message)\n\n\($0)" } ?? message
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")
        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }
}

