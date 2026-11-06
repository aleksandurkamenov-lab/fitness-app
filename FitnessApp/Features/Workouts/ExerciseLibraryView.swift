import SwiftUI
import SwiftData

/// Избор на упражнение (при добавяне в шаблон или по време на тренировка).
struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var showingNew = false
    let onPick: (Exercise) -> Void

    private var filtered: [Exercise] {
        search.isEmpty ? exercises : exercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(MuscleGroup.allCases) { muscle in
                    let items = filtered.filter { $0.primaryMuscle == muscle }
                    if !items.isEmpty {
                        Section(tr(muscle.title)) {
                            ForEach(items) { exercise in
                                Button(exercise.name) {
                                    onPick(exercise)
                                    dismiss()
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Търси упражнение")
            .navigationTitle("Избери упражнение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отказ") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNew = true
                    } label: {
                        Label("Ново", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNew) {
                NewExerciseSheet { exercise in
                    onPick(exercise)
                    dismiss()
                }
            }
        }
    }
}

struct NewExerciseSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var primary: MuscleGroup = .chest
    @State private var secondary: Set<MuscleGroup> = []
    let onCreate: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Име", text: $name)
                Picker("Основна група", selection: $primary) {
                    ForEach(MuscleGroup.allCases) { Text($0.title).tag($0) }
                }
                Section("Второстепенни групи (броят 0.5 серия)") {
                    ForEach(MuscleGroup.allCases.filter { $0 != primary }) { muscle in
                        Toggle(muscle.title, isOn: Binding(
                            get: { secondary.contains(muscle) },
                            set: { isOn in
                                if isOn { secondary.insert(muscle) } else { secondary.remove(muscle) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Ново упражнение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отказ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Запази") {
                        let exercise = Exercise(
                            name: name.trimmingCharacters(in: .whitespaces),
                            primary: primary,
                            secondary: MuscleGroup.allCases.filter { secondary.contains($0) && $0 != primary },
                            isCustom: true
                        )
                        context.insert(exercise)
                        onCreate(exercise)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Молив до името на упражнението: отваря прозорче за ново име.
struct RenameExerciseButton: View {
    @Bindable var exercise: Exercise
    @State private var showing = false
    @State private var draft = ""

    var body: some View {
        Button {
            draft = exercise.name
            showing = true
        } label: {
            Image(systemName: "pencil.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.borderless)
        .alert("Ново име на упражнението", isPresented: $showing) {
            TextField("Име", text: $draft)
            Button("Запази") {
                let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { exercise.name = name }
            }
            Button("Отказ", role: .cancel) {}
        }
    }
}
