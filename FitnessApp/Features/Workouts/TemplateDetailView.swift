import SwiftUI
import SwiftData

struct TemplateDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var template: WorkoutTemplate
    @Binding var activeSession: WorkoutSession?
    @State private var showingPicker = false
    @State private var showingStartOptions = false

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

            Section {
                Button {
                    showingStartOptions = true
                } label: {
                    Label("Започни тренировка", systemImage: "play.fill")
                        .font(.headline)
                }
                .disabled(template.items.isEmpty)
            }
        }
        .navigationTitle(template.name)
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
        .confirmationDialog("Как да започнем?", isPresented: $showingStartOptions, titleVisibility: .visible) {
            Button("С кг и повторения от миналия път") { start(copyPrevious: true) }
            Button("Само упражненията") { start(copyPrevious: false) }
            Button("Отказ", role: .cancel) {}
        }
    }

    private func start(copyPrevious: Bool) {
        RestTimer.requestPermission()
        activeSession = WorkoutService.startSession(from: template, copyPrevious: copyPrevious, in: context)
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
            ForEach(Array(item.targets.enumerated()), id: \.offset) { index, target in
                VStack(alignment: .leading, spacing: 10) {
                    Text("Серия \(index + 1)").font(.subheadline.weight(.semibold))
                    RepStepperRow(title: "Повторения от", value: minBinding(index), range: 1...50)
                    RepStepperRow(title: "Повторения до", value: maxBinding(index), range: target.repMin...60)
                    if let best = target.bestText {
                        Text("Най-добър до сега: \(best)")
                            .font(.caption)
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
            TextField("Бележка", text: $item.note, axis: .vertical)
        } label: {
            VStack(alignment: .leading) {
                Text(item.exercise?.name ?? "Изтрито упражнение")
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
