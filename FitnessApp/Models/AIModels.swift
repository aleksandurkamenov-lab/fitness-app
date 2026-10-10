import Foundation
import SwiftData

/// Съобщение в AI чата. role: "user", "assistant" или "action" (какво е записал AI-ът).
@Model
final class AIMessage {
    var date: Date = Date.now
    var role: String = "user"
    var text: String = ""

    init(role: String, text: String) {
        self.date = .now
        self.role = role
        self.text = text
    }
}
