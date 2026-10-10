import SwiftUI
import SwiftData
import Charts

struct MeasurementsView: View {
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \MeasurementEntry.date) private var measurements: [MeasurementEntry]
    @State private var showingAddWeight = false
    @State private var rangeDays = 30

    private var trend: [BodyMath.TrendPoint] { BodyMath.trend(weights) }

    /// Точките за избрания период (0 = всички).
    private var visible: [BodyMath.TrendPoint] {
        guard rangeDays > 0 else { return trend }
        let from = Date.now.addingTimeInterval(-Double(rangeDays) * 86_400)
        return trend.filter { $0.date >= from }
    }

    /// Последната стойност; за мускулните зони отпуснато / стегнато, по страни.
    private func summary(for kind: MeasurementKind) -> String {
        func value(side: String?, flexed: Bool?) -> String {
            measurements.last {
                $0.kind == kind
                    && (side == nil || $0.sideRaw == side)
                    && (flexed == nil || $0.isFlexed == flexed)
            }.map { $0.cm.short } ?? "–"
        }
        func pair(_ side: String?) -> String {
            kind.supportsFlex
                ? "\(value(side: side, flexed: false))/\(value(side: side, flexed: true))"
                : value(side: side, flexed: nil)
        }
        if kind.supportsSides { return "Л \(pair("left")) · Д \(pair("right")) см" }
        return "\(pair(nil)) см"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Тегло") {
                    if let last = trend.last {
                        LabeledContent("Последно", value: "\(last.kg.short) кг")
                        LabeledContent("Тренд (7 дни)", value: "\(last.trend.short) кг")
                    } else {
                        Text("Още няма записано тегло.")
                            .foregroundStyle(.secondary)
                    }
                    if trend.count >= 2 {
                        Picker("Период", selection: $rangeDays) {
                            Text("7 дни").tag(7)
                            Text("30 дни").tag(30)
                            Text("90 дни").tag(90)
                            Text("Всички").tag(0)
                        }
                        .pickerStyle(.segmented)
                        if visible.count >= 2 {
                            WeightChart(points: visible)
                        } else {
                            Text("Няма достатъчно записи за този период.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showingAddWeight = true
                    } label: {
                        Label("Добави тегло", systemImage: "plus")
                    }
                    NavigationLink("История на теглото") {
                        WeightHistoryView()
                    }
                }

                Section("Обиколки") {
                    ForEach(MeasurementKind.allCases) { kind in
                        NavigationLink {
                            MeasurementDetailView(kind: kind)
                        } label: {
                            LabeledContent(kind.title, value: summary(for: kind))
                        }
                    }
                }

                Section("Калкулатори") {
                    NavigationLink("ИТМ, % мазнини, калории и макроси") {
                        CalculatorsView()
                    }
                }
            }
            .navigationTitle("Мерки")
            .profileButton()
            .sheet(isPresented: $showingAddWeight) {
                AddWeightSheet(initial: weights.last?.kg)
            }
        }
    }
}

struct WeightChart: View {
    let points: [BodyMath.TrendPoint]

    var body: some View {
        Chart(points) { point in
            PointMark(x: .value("Дата", point.date), y: .value("кг", point.kg))
                .foregroundStyle(.secondary)
            LineMark(x: .value("Дата", point.date), y: .value("Тренд", point.trend))
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 200)
    }
}

struct AddWeightSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let initial: Double?
    @State private var date = Date.now
    @State private var kg: Double?
    @State private var bodyFat: Double?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Дата", selection: $date, in: ...Date.now, displayedComponents: .date)
                TextField(initial.map { $0.short } ?? "кг", value: $kg, format: .number)
                    .keyboardType(.decimalPad)
                TextField("% мазнини (по избор)", value: $bodyFat, format: .number)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("Ново тегло")
            .keyboardDoneButton()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отказ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Запази") {
                        if let kg, kg > 0 {
                            context.insert(WeightEntry(date: date, kg: kg, bodyFatPercent: bodyFat))
                        }
                        dismiss()
                    }
                    .disabled((kg ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct WeightHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    var body: some View {
        List {
            ForEach(weights) { entry in
                HStack {
                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    if let fat = entry.bodyFatPercent {
                        Text("\(fat.short)%").foregroundStyle(.secondary)
                    }
                    Text("\(entry.kg.short) кг").font(.headline)
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(weights[index]) }
            }
        }
        .navigationTitle("История на теглото")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MeasurementDetailView: View {
    @Environment(\.modelContext) private var context
    let kind: MeasurementKind
    @Query(sort: \MeasurementEntry.date, order: .reverse) private var all: [MeasurementEntry]
    @State private var date = Date.now
    @State private var cm: Double?
    @State private var flexed = false
    @State private var side = "left"

    private var entries: [MeasurementEntry] { all.filter { $0.kind == kind } }

    private func label(_ entry: MeasurementEntry) -> String {
        var parts: [String] = []
        if kind.supportsSides { parts.append(entry.sideRaw == "right" ? "Дясно" : "Ляво") }
        if kind.supportsFlex { parts.append(entry.isFlexed ? "стегнато" : "отпуснато") }
        return parts.isEmpty ? "см" : parts.joined(separator: " ")
    }

    private var hint: String {
        entries.first {
            (!kind.supportsFlex || $0.isFlexed == flexed) && (!kind.supportsSides || $0.sideRaw == side)
        }.map { $0.cm.short } ?? "см"
    }

    var body: some View {
        List {
            Section("Нов запис") {
                DatePicker("Дата", selection: $date, in: ...Date.now, displayedComponents: .date)
                if kind.supportsSides {
                    Picker("Страна", selection: $side) {
                        Text("Ляво").tag("left")
                        Text("Дясно").tag("right")
                    }
                    .pickerStyle(.segmented)
                }
                if kind.supportsFlex {
                    Picker("Състояние", selection: $flexed) {
                        Text("Отпуснато").tag(false)
                        Text("Стегнато").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                TextField(hint, value: $cm, format: .number)
                    .keyboardType(.decimalPad)
                Button("Запази") {
                    if let cm, cm > 0 {
                        context.insert(MeasurementEntry(date: date, kind: kind, cm: cm,
                                                        isFlexed: kind.supportsFlex && flexed,
                                                        side: kind.supportsSides ? side : ""))
                        self.cm = nil
                    }
                }
                .disabled((cm ?? 0) <= 0)
            }

            if entries.count >= 2 {
                Section {
                    Chart(entries.reversed()) { entry in
                        LineMark(x: .value("Дата", entry.date), y: .value("см", entry.cm))
                            .foregroundStyle(by: .value("Серия", label(entry)))
                        PointMark(x: .value("Дата", entry.date), y: .value("см", entry.cm))
                            .foregroundStyle(by: .value("Серия", label(entry)))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                }
            }

            Section("История") {
                ForEach(entries) { entry in
                    LabeledContent(
                        "\(entry.date.formatted(date: .abbreviated, time: .omitted))" +
                            (label(entry) == "см" ? "" : " · \(label(entry).lowercased())"),
                        value: "\(entry.cm.short) см")
                }
                .onDelete { offsets in
                    let items = entries
                    for index in offsets { context.delete(items[index]) }
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
    }
}
