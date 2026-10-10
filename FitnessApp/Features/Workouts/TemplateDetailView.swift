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
            Stepper("Серии: \(item.targetSets)", value: $item.targetSets, in: 1...10)
            Stepper("Повторения от: \(item.repMin)", value: $item.repMin, in: 1...50)
            Stepper("Повторения до: \(item.repMax)", value: $item.repMax, in: item.repMin...60)
            Stepper("Почивка: \(item.restSeconds) сек", value: $item.restSeconds, in: 30...600, step: 15)
            TextField("Бележка", text: $item.note)
                .onChange(of: item.repMin) {
                    if item.repMax < item.repMin { item.repMax = item.repMin }
                }
        } label: {
            VStack(alignment: .leading) {
                Text(item.exercise?.name ?? "Изтрито упражнение")
                Text(item.targetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
