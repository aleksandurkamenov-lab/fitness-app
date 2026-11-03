import SwiftUI

/// Поле за килограми: приема и запетая, и точка (82,5 или 82.5) и не трие дробната част докато пишеш.
struct DecimalField: View {
    let placeholder: String
    /// 0 означава празно поле.
    @Binding var value: Double
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .focused($focused)
            .onAppear { text = Self.format(value) }
            .onChange(of: text) { _, newText in
                let cleaned = newText.replacingOccurrences(of: ",", with: ".")
                if cleaned.isEmpty {
                    value = 0
                } else if let number = Double(cleaned) {
                    value = number
                }
            }
            .onChange(of: value) { _, newValue in
                if !focused { text = Self.format(newValue) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { text = Self.format(value) }
            }
    }

    static func format(_ value: Double) -> String {
        value > 0 ? value.short : ""
    }
}

/// Същото поле за по избор число (повторения): празно = nil, приема и запетая, и точка.
struct OptionalDecimalField: View {
    let placeholder: String
    @Binding var value: Double?

    var body: some View {
        DecimalField(placeholder: placeholder, value: Binding(
            get: { value ?? 0 },
            set: { value = $0 > 0 ? $0 : nil }
        ))
    }
}
