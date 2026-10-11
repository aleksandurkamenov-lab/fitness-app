import SwiftUI
import SwiftData

struct TemplateDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var template: WorkoutTemplate
    @Binding var activeSession: WorkoutSession?
    @State private var showingPicker = false

    var body: some View {
        List {
            Section {
                TextField("Име на тренировката", text: $template.name)
            }

            Section("Упражнения") {
                if template.items.isEmpty {
                    Text("Добави упражнения от библиотеката.")
                        .foregroundStyle(.secondary)
                }
                ForEach(template.sortedItems) { item in
                    TemplateExerciseRow(item: item)
                }
                .onDelete(perform: delete)
                .onMove(perform: move)

                Button {
                    showingPicker = true
                } label: {
                    Label("Добави упражнение", systemImage: "plus")
                }
            }

            if template.items.contains(where: { !$0.note.isEmpty }) {
                Section {
                    Button("Изтрий всички бележки от таблицата", role: .destructive) {
                        for item in template.items { item.note = "" }
                    }
                }
            }
        }
        .navigationTitle(template.name)
        .keyboardDoneButton()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { exercise in
                let order = (template.items.map(\.order).max() ?? -1) + 1
                let item = TemplateExercise(exercise: exercise, order: order)
                item.template = template
                context.insert(item)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let sorted = template.sortedItems
        for index in offsets { context.delete(sorted[index]) }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var sorted = template.sortedItems
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, item) in sorted.enumerated() { item.order = index }
    }
}

private struct TemplateExerciseRow: View {
    @Bindable var item: TemplateExercise
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            HStack(spacing: 8) {
                Text("Серия").frame(width: 44, alignment: .leading)
                Text("Повт. от").frame(maxWidth: .infinity)
                Text("до").frame(maxWidth: .infinity)
                Text("Кг").frame(maxWidth: .infinity)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(Array(item.targets.enumerated()), id: \.offset) { index, target in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("\(index + 1)").font(.headline).frame(width: 44, alignment: .leading)
                        TextField("от", value: minBinding(index), format: .number)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                        TextField("до", value: maxBinding(index), format: .number)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                        DecimalField(placeholder: "кг", value: weightBinding(index))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                    }
                    if let best = target.bestText {
                        Text("Най-добър до сега: \(best)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button("Добави серия") {
                    var targets = item.targets
                    targets.append(targets.last ?? SetTarget(repMin: 8, repMax: 12))
                    targets[targets.count - 1].bestWeight = nil
                    targets[targets.count - 1].bestReps = nil
                    targets[targets.count - 1].plannedWeight = targets.count > 1 ? targets[targets.count - 2].plannedWeight : nil
                    item.targets = targets
                }
                Spacer()
                Button("Махни серия", role: .destructive) {
                    var targets = item.targets
                    guard targets.count > 1 else { return }
                    targets.removeLast()
                    item.targets = targets
                }
            }
            .buttonStyle(.borderless)
            RepStepperRow(title: "Почивка (сек)", value: $item.restSeconds, range: 30...600, step: 15)
            TextField("Моя бележка (по избор)", text: $item.note, axis: .vertical)
            if !item.note.isEmpty {
                Button("Изтрий бележката", role: .destructive) { item.note = "" }
                    .buttonStyle(.borderless)
            }
        } label: {
            VStack(alignment: .leading) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.exercise?.name ?? "Изтрито упражнение")
                    if let exercise = item.exercise {
                        RenameExerciseButton(exercise: exercise)
                    }
                }
                Text(item.targetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func minBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { item.targets[index].repMin },
            set: { newValue in
                var targets = item.targets
                targets[index].repMin = newValue
                if targets[index].repMax < newValue { targets[index].repMax = newValue }
                item.targets = targets
            }
        )
    }

    private func weightBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { item.targets[index].plannedWeight ?? 0 },
            set: { newValue in
                var targets = item.targets
                targets[index].plannedWeight = newValue > 0 ? newValue : nil
                item.targets = targets
            }
        )
    }

    private func maxBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { item.targets[index].repMax },
            set: { newValue in
                var targets = item.targets
                targets[index].repMax = max(newValue, targets[index].repMin)
                item.targets = targets
            }
        )
    }
}

/// Ред с етикет, текущата стойност и малък −/+ контрол, без застъпване между редовете.
private struct RepStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
                .fixedSize()
        }
        .frame(minHeight: 36)
    }
}

