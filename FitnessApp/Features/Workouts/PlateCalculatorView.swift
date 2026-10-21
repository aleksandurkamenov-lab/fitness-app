import SwiftUI

struct PlateRequest: Identifiable {
    let id = UUID()
    let weight: Double
}

/// Кои дискове да се сложат от всяка страна на щангата.
struct PlateCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var weight: Double
    @AppStorage("barWeight") private var barWeight = 20.0

    private let plates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    static func perSide(total: Double, bar: Double, plates: [Double]) -> (plates: [Double], remainder: Double) {
        var left = max(0, (total - bar) / 2)
        var result: [Double] = []
        for plate in plates {
            while left + 0.001 >= plate {
                result.append(plate)
                left -= plate
            }
        }
        return (result, left)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Общо")
                        DecimalField(placeholder: "кг", value: $weight)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.weight(.semibold))
                        Text("кг").foregroundStyle(.secondary)
                    }
                    Picker("Щанга", selection: $barWeight) {
                        ForEach([20.0, 15.0, 10.0, 0.0], id: \.self) { bar in
                            Text(bar == 0 ? "без щанга" : "\(bar.short) кг").tag(bar)
                        }
                    }
                }

                let result = Self.perSide(total: weight, bar: barWeight, plates: plates)
                Section {
                    if weight <= 0 {
                        Text("Въведи тежест.")
                            .foregroundStyle(.secondary)
                    } else if weight < barWeight {
                        Text("Целта е под теглото на щангата (\(barWeight.short) кг).")
                            .foregroundStyle(.orange)
                    } else if weight == barWeight {
                        Text(barWeight > 0 ? "Само щангата." : "Без щанга.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(result.plates.map(\.short).joined(separator: " + "))
                            .font(.title2.weight(.bold))
                        if result.remainder > 0.01 {
                            Text("Не се получава точно: липсват \((result.remainder * 2).short) кг общо.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("От всяка страна")
                } footer: {
                    Text("Дискове: 25, 20, 15, 10, 5, 2,5 и 1,25 кг.")
                }
            }
            .navigationTitle("Дискове")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
