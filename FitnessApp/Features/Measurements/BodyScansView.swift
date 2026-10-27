import SwiftUI
import SwiftData

/// DEXA / InBody сканирания: от тях се смята % мазнини и BMR по безмастната маса.
struct BodyScansView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyScan.date, order: .reverse) private var scans: [BodyScan]
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \MeasurementEntry.date) private var measurements: [MeasurementEntry]
    @State private var adding = false

    var body: some View {
        List {
            Section {
                if scans.isEmpty {
                    Text("Още няма сканирания.").foregroundStyle(.secondary)
                }
                ForEach(scans) { scan in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(scan.kind) · \(scan.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline.weight(.semibold))
                        Text("\(scan.weightKg.short) кг · \(scan.bodyFatPercent.short) % мазнини · безмастна \(scan.fatFreeKg.short) кг")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(scans[index]) }
                    refresh()
                }
                Button("Добави сканиране") { adding = true }
            } footer: {
                Text("Последното сканиране до 24 месеца назад е с предимство пред обиколките и кантара. Безмастната маса оттогава се коригира с ~25% от промяната на теглото (средно за 7 дни). BMR се смята по Katch-McArdle. Ориентировъчно, не е медицински съвет.")
            }
        }
        .navigationTitle("DEXA / InBody")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding, onDismiss: refresh) {
            AddBodyScanSheet(initialWeight: weights.last?.kg)
        }
    }

    private func refresh() {
        try? context.save()
        if let profile = profiles.first {
            BodyMath.refreshBodyFat(profile: profile, weights: weights, measurements: measurements)
        }
    }
}

private struct AddBodyScanSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let initialWeight: Double?
    @State private var date = Date.now
    @State private var kind = "DEXA"
    @State private var weight: Double?
    @State private var fat: Double?
    @State private var lean: Double?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Вид", selection: $kind) {
                    Text("DEXA").tag("DEXA")
                    Text("InBody").tag("InBody")
                    Text("Друго").tag("Друго")
                }
                .pickerStyle(.segmented)
                DatePicker("Дата", selection: $date, in: ...Date.now, displayedComponents: .date)
                TextField(initialWeight.map { "Тегло (\($0.short) кг)" } ?? "Тегло, кг", value: $weight, format: .number)
                    .keyboardType(.decimalPad)
                TextField("% мазнини", value: $fat, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Постна маса, кг (ако няма %)", value: $lean, format: .number)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("Ново сканиране")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отказ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Запази") {
                        let kg = weight ?? initialWeight ?? 0
                        if kg > 0 && ((fat ?? 0) > 0 || (lean ?? 0) > 0) {
                            context.insert(BodyScan(date: date, weightKg: kg, bodyFatPercent: fat ?? 0,
                                                    leanMassKg: lean ?? 0, kind: kind))
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
