import SwiftUI
import SwiftData

/// Екранът по време на тренировка: бързо въвеждане на кг и повторения, таймер за почивка.
struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: WorkoutSession
    @State private var timer = RestTimer()
    @State private var previous: [Int: [SetEntry]] = [:]
    @State private var showingFinish = false
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.exerciseGroups) { group in
                    Section {
                        ForEach(group.sets) { set in
                            SetRow(set: set, previous: previousSet(for: group, index: set.setIndex)) {
                                if set.isDone { timer.start(seconds: set.restSeconds) }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(group.sets[index]) }
                        }
                        Button {
                            addSet(to: group)
                        } label: {
                            Label("Серия", systemImage: "plus")
                                .font(.subheadline)
                        }
                    } header: {
                        GroupHeader(group: group)
                    }
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Добави упражнение", systemImage: "plus.circle")
                    }
                    TextField("Бележка за тренировката", text: $session.notes, axis: .vertical)
                } footer: {
                    Text("Обем \(WorkoutMath.totalVolume(session.sets).short) кг · \(WorkoutMath.totalReps(session.sets)) повторения")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if timer.endDate != nil {
                    RestTimerBar(timer: timer)
                }
            }
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Скрий") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    TimelineView(.periodic(from: session.date, by: 1)) { context in
                        Text(Duration.seconds(context.date.timeIntervalSince(session.date)),
                             format: .time(pattern: .hourMinuteSecond))
                            .monospacedDigit()
                            .font(.subheadline.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Край") { showingFinish = true }
                }
            }
            .confirmationDialog("Да приключа ли тренировката?", isPresented: $showingFinish, titleVisibility: .visible) {
                Button("Запази и приключи") { finish() }
                Button("Изтрий тренировката", role: .destructive) { discard() }
                Button("Отказ", role: .cancel) {}
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise in addExercise(exercise) }
            }
            .onAppear(perform: loadPrevious)
        }
    }

    private func previousSet(for group: ExerciseGroup, index: Int) -> SetEntry? {
        guard let sets = previous[group.order], index < sets.count else { return nil }
        return sets[index]
    }

    private func loadPrevious() {
        var result: [Int: [SetEntry]] = [:]
        for group in session.exerciseGroups {
            guard let exercise = group.exercise else { continue }
            result[group.order] = WorkoutService.lastSets(for: exercise, before: session.date, in: context)
        }
        previous = result
    }

    private func addSet(to group: ExerciseGroup) {
        let last = group.sets.last
        let set = SetEntry(
            exercise: group.exercise,
            exerciseOrder: group.order,
            setIndex: (last?.setIndex ?? -1) + 1,
            targetRepMin: last?.targetRepMin ?? 0,
            targetRepMax: last?.targetRepMax ?? 0,
            restSeconds: last?.restSeconds ?? 120
        )
        set.session = session
        context.insert(set)
    }

    private func addExercise(_ exercise: Exercise) {
        let order = (session.sets.map(\.exerciseOrder).max() ?? -1) + 1
        let set = SetEntry(exercise: exercise, exerciseOrder: order, setIndex: 0)
        set.session = session
        context.insert(set)
        loadPrevious()
    }

    private func finish() {
        // Празните серии (без кг и повторения) не се пазят.
        for set in session.sets where !set.isDone && set.reps == 0 {
            context.delete(set)
        }
        for set in session.sets where set.reps > 0 {
            set.isDone = true
        }
        session.finishedAt = .now
        timer.stop()
        try? context.save()
        dismiss()
    }

    private func discard() {
        timer.stop()
        context.delete(session)
        try? context.save()
        dismiss()
    }
}

private struct GroupHeader: View {
    let group: ExerciseGroup

    private var noteBinding: Binding<String> {
        Binding(
            get: { group.sets.first?.exerciseNote ?? "" },
            set: { group.sets.first?.exerciseNote = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.exercise?.name ?? "Упражнение")
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)
            TextField("Бележка", text: noteBinding, axis: .vertical)
                .font(.caption)
                .textCase(nil)
        }
    }
}

private struct SetRow: View {
    @Bindable var set: SetEntry
    let previous: SetEntry?
    let onToggle: () -> Void

    private var target: String {
        guard set.targetRepMax > 0 else { return "" }
        return set.targetRepMin == set.targetRepMax
            ? "\(set.targetRepMin)" : "\(set.targetRepMin)–\(set.targetRepMax)"
    }

    private var weightHint: String {
        if let previous, previous.weight > 0 { return previous.weight.short }
        return set.plannedWeight > 0 ? set.plannedWeight.short : "кг"
    }

    private var repsHint: String {
        if let previous, previous.reps > 0 { return "\(previous.reps)" }
        return "повт."
    }

    private var weightBinding: Binding<Double?> {
        Binding(get: { set.weight > 0 ? set.weight : nil }, set: { set.weight = $0 ?? 0 })
    }

    private var repsBinding: Binding<Int?> {
        Binding(get: { set.reps > 0 ? set.reps : nil }, set: { set.reps = $0 ?? 0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Серия \(set.setIndex + 1)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !target.isEmpty {
                    Text("цел \(target) повт.")
                        .font(.title3.weight(.bold))
                }
            }
            HStack(spacing: 10) {
                TextField(weightHint, value: weightBinding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                Text("кг ×").foregroundStyle(.secondary)
                TextField(repsHint, value: repsBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                Text("повт.").foregroundStyle(.secondary)
                Button {
                    set.isDone.toggle()
                    onToggle()
                } label: {
                    Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .foregroundStyle(set.isDone ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            if set.bestWeight > 0 {
                Text("Най-добър до сега: \(set.bestWeight.short) × \(set.bestReps.short)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RestTimerBar: View {
    let timer: RestTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = timer.remaining(at: context.date)
            HStack {
                Image(systemName: "timer")
                Text(remaining > 0 ? "Почивка" : "Почивката свърши")
                Spacer()
                Text(Duration.seconds(remaining.rounded(.up)), format: .time(pattern: .minuteSecond))
                    .monospacedDigit()
                    .font(.title3.weight(.semibold))
                Button("+15") { timer.add(seconds: 15) }
                    .buttonStyle(.bordered)
                Button {
                    timer.stop()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.thinMaterial)
        }
    }
}
