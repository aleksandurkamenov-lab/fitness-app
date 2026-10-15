import SwiftUI
import SwiftData
import Charts

/// Библиотека с упражнения, групирани по мускулна група.
struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var showingNew = false

    private var filtered: [Exercise] {
        search.isEmpty ? exercises : exercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            ForEach(MuscleGroup.allCases) { muscle in
                let items = filtered.filter { $0.primaryMuscle == muscle }
                if !items.isEmpty {
                    Section(muscle.title) {
                        ForEach(items) { exercise in
                            NavigationLink(exercise.name) {
                                ExerciseDetailView(exercise: exercise)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(items[index]) }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Търси упражнение")
        .navigationTitle("Упражнения")
        .toolbar {
            Button {
                showingNew = true
            } label: {
                Label("Ново", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingNew) {
            NewExerciseSheet { _ in }
        }
    }
}

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
                        Section(muscle.title) {
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

/// Прогрес по упражнение: най-добри резултати и приблизителен 1RM във времето.
struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var exercise: Exercise
    @State private var history: [ExerciseHistoryEntry] = []

    private struct ProgressPoint: Identifiable {
        let date: Date
        let oneRM: Double
        var id: Date { date }
    }

    private var points: [ProgressPoint] {
        history.compactMap { entry in
            guard let best = WorkoutMath.bestSet(entry.sets) else { return nil }
            return ProgressPoint(date: entry.session.date, oneRM: best.estimatedOneRepMax)
        }
    }

    var body: some View {
        List {
            Section("Име") {
                TextField("Име на упражнението", text: $exercise.name)
            }
            Section {
                LabeledContent("Основна група", value: exercise.primaryMuscle.title)
                if !exercise.secondaryMuscles.isEmpty {
                    LabeledContent("Второстепенни", value: exercise.secondaryMuscles.map(\.title).joined(separator: ", "))
                }
            }

            if points.count >= 2 {
                Section("Приблизителен 1RM (кг)") {
                    Chart(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Дата", point.date), y: .value("1RM", point.oneRM))
                        PointMark(x: .value("Дата", point.date), y: .value("1RM", point.oneRM))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartScrub(points.map {
                        ScrubPoint(date: $0.date, value: $0.oneRM,
                                   text: "\(scrubDate($0.date)): \($0.oneRM.formatted(.number.precision(.fractionLength(0...1)))) кг")
                    })
                    .padding(.top, 24)
                    .frame(height: 204)
                }
            }

            let allSets = history.flatMap(\.sets).filter { $0.repsValue > 0 }
            if let best = allSets.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }) {
                Section("Рекорди") {
                    LabeledContent("Приблизителен 1RM", value: "~\(best.estimatedOneRepMax.short) кг (\(best.weight.short)×\(best.repsText))")
                    if let heaviest = allSets.max(by: { ($0.weight, $0.repsValue) < ($1.weight, $1.repsValue) }) {
                        LabeledContent("Най-тежко", value: "\(heaviest.weight.short) кг × \(heaviest.repsText)")
                    }
                    if let most = allSets.max(by: { ($0.repsValue, $0.weight) < ($1.repsValue, $1.weight) }) {
                        LabeledContent("Най-много повторения", value: "\(most.repsText) × \(most.weight.short) кг")
                    }
                    if let biggest = allSets.max(by: { $0.volume < $1.volume }) {
                        LabeledContent("Най-голям обем в серия", value: "\(biggest.volume.short) кг")
                    }
                    if let session = history.max(by: { WorkoutMath.totalVolume($0.sets) < WorkoutMath.totalVolume($1.sets) }) {
                        LabeledContent("Най-голям обем в тренировка",
                                       value: "\(WorkoutMath.totalVolume(session.sets).short) кг, \(session.session.date.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
            }

            Section("История") {
                if history.isEmpty {
                    Text("Още няма записани серии.")
                        .foregroundStyle(.secondary)
                }
                ForEach(history) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.session.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.semibold))
                        Text(entry.sets.map { "\($0.weight.short)×\($0.repsText)" }.joined(separator: "  "))
                            .font(.caption)
                        Text("Обем \(WorkoutMath.totalVolume(entry.sets).short) кг")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("1RM е приблизителен (формула на Epley) и е само ориентир.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            history = WorkoutService.history(for: exercise, in: context)
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
