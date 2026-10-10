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
    @State private var records: [Int: (weight: Double, oneRM: Double)] = [:]
    @State private var sessionBest: [Int: (weight: Double, oneRM: Double)] = [:]
    @State private var prBanner: String?
    @State private var plateRequest: PlateRequest?

    var body: some View {
        NavigationStack {
            List {
                let groups = session.exerciseGroups
                ForEach(Array(groups.enumerated()), id: \.element.id) { position, group in
                    let linkedFromPrevious = position > 0 && groups[position - 1].isSuperset
                    let linkedToNext = group.isSuperset
                    Section {
                        ForEach(group.sets) { set in
                            SetRow(set: set, previous: previousSet(for: group, index: set.setIndex),
                                   isRecord: isRecord(set, in: group)) {
                                setToggled(set, in: group)
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
                        GroupHeader(group: group,
                                    linkedFromPrevious: linkedFromPrevious,
                                    linkedToNext: linkedToNext,
                                    canLinkNext: position < groups.count - 1,
                                    onWarmup: { addWarmups(to: group) },
                                    onPlates: { plateRequest = PlateRequest(weight: workingWeight(for: group)) },
                                    onToggleSuperset: { toggleSuperset(group) })
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
            .overlay(alignment: .top) {
                if let prBanner {
                    Text(prBanner)
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.yellow.opacity(0.9), in: Capsule())
                        .foregroundStyle(.black)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring, value: prBanner)
            .sensoryFeedback(.success, trigger: prBanner) { _, new in new != nil }
            .sheet(item: $plateRequest) { request in
                PlateCalculatorView(weight: request.weight)
            }
            .navigationTitle(session.title)
            .keyboardDoneButton()
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
        guard index >= 0, let sets = previous[group.order], index < sets.count else { return nil }
        return sets[index]
    }

    private func loadPrevious() {
        var result: [Int: [SetEntry]] = [:]
        var bests: [Int: (weight: Double, oneRM: Double)] = [:]
        for group in session.exerciseGroups {
            guard let exercise = group.exercise else { continue }
            result[group.order] = WorkoutService.lastSets(for: exercise, before: session.date, in: context)
            bests[group.order] = WorkoutService.records(for: exercise, before: session.date, in: context)
        }
        previous = result
        records = bests
    }

    /// Нов рекорд спрямо всички предишни тренировки (само ако упражнението вече има история).
    private func isRecord(_ set: SetEntry, in group: ExerciseGroup) -> Bool {
        guard set.isWorkSet, set.reps > 0, let best = records[group.order], best.weight > 0 else { return false }
        return set.weight > best.weight + 0.001 || set.estimatedOneRepMax > best.oneRM + 0.001
    }

    private func setToggled(_ set: SetEntry, in group: ExerciseGroup) {
        guard set.isDone else { return }
        // В суперсерия почивката започва след второто упражнение.
        if !group.isSuperset {
            timer.start(seconds: set.restSeconds)
        }
        guard isRecord(set, in: group), let baseline = records[group.order] else { return }
        // Банерът се показва само когато се бие и най-доброто от тази тренировка.
        let best = sessionBest[group.order] ?? baseline
        let name = group.exercise?.name ?? "Упражнение"
        if set.weight > best.weight + 0.001 {
            prBanner = "🏆 Нов рекорд: \(name) \(set.weight.short) кг"
        } else if set.estimatedOneRepMax > best.oneRM + 0.001 {
            prBanner = "🏆 Нов рекорд 1RM: \(name) ~\(set.estimatedOneRepMax.short) кг"
        } else {
            return
        }
        sessionBest[group.order] = (weight: max(best.weight, set.weight), oneRM: max(best.oneRM, set.estimatedOneRepMax))
        let shown = prBanner
        Task {
            try? await Task.sleep(for: .seconds(3))
            if prBanner == shown { prBanner = nil }
        }
    }

    /// Работната тежест: въведената, планираната или от последния път.
    private func workingWeight(for group: ExerciseGroup) -> Double {
        let work = group.sets.filter { !$0.isWarmup }
        if let typed = work.first(where: { $0.weight > 0 })?.weight { return typed }
        if let planned = work.first(where: { $0.plannedWeight > 0 })?.plannedWeight { return planned }
        return previous[group.order]?.first?.weight ?? 0
    }

    private func addWarmups(to group: ExerciseGroup) {
        let base = workingWeight(for: group)
        guard base > 0 else { return }
        WorkoutService.addWarmups(to: group, baseWeight: base, session: session, in: context)
    }

    private func toggleSuperset(_ group: ExerciseGroup) {
        let value = !group.isSuperset
        for set in group.sets { set.supersetNext = value }
        // Запомня се и в шаблона за следващите тренировки.
        if let item = session.template?.items.first(where: { $0.order == group.order }) {
            item.supersetNext = value
        }
    }

    private func addSet(to group: ExerciseGroup) {
        let last = group.sets.last(where: { !$0.isWarmup })
        let set = SetEntry(
            exercise: group.exercise,
            exerciseOrder: group.order,
            setIndex: (last?.setIndex ?? -1) + 1,
            targetRepMin: last?.targetRepMin ?? 0,
            targetRepMax: last?.targetRepMax ?? 0,
            restSeconds: last?.restSeconds ?? 120
        )
        set.supersetNext = group.isSuperset
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
    let linkedFromPrevious: Bool
    let linkedToNext: Bool
    let canLinkNext: Bool
    let onWarmup: () -> Void
    let onPlates: () -> Void
    let onToggleSuperset: () -> Void

    private var noteBinding: Binding<String> {
        Binding(
            get: { group.firstWorkSet?.exerciseNote ?? "" },
            set: { group.firstWorkSet?.exerciseNote = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if linkedFromPrevious || linkedToNext {
                Label(linkedToNext ? "Суперсерия със следващото" : "Суперсерия с предишното", systemImage: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                    .textCase(nil)
            }
            HStack(spacing: 8) {
                Text(group.exercise?.name ?? "Упражнение")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
                if let exercise = group.exercise {
                    RenameExerciseButton(exercise: exercise)
                }
                Spacer()
                Menu {
                    Button(action: onWarmup) {
                        Label("Добави загряващи серии", systemImage: "flame")
                    }
                    Button(action: onPlates) {
                        Label("Калкулатор за дискове", systemImage: "circle.circle")
                    }
                    if canLinkNext || linkedToNext {
                        Button(action: onToggleSuperset) {
                            Label(linkedToNext ? "Махни суперсерията" : "Суперсерия със следващото",
                                  systemImage: "link")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
            TextField("Бележка", text: noteBinding, axis: .vertical)
                .font(.caption)
                .textCase(nil)
        }
    }
}

private struct SetRow: View {
    @Bindable var set: SetEntry
    let previous: SetEntry?
    let isRecord: Bool
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

    private var repsBinding: Binding<Int?> {
        Binding(get: { set.reps > 0 ? set.reps : nil }, set: { set.reps = $0 ?? 0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if set.isWarmup {
                    Label("Загрявка", systemImage: "flame")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text("Серия \(set.setIndex + 1)")
                        .font(.subheadline.weight(.semibold))
                }
                if isRecord {
                    Text("🏆 рекорд")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.yellow)
                }
                Spacer()
                if !target.isEmpty && !set.isWarmup {
                    Text("цел \(target) повт.")
                        .font(.title3.weight(.bold))
                }
            }
            HStack(spacing: 10) {
                DecimalField(placeholder: weightHint, value: $set.weight)
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
            if !set.isWarmup {
                HStack(spacing: 6) {
                    Text("RIR").font(.caption).foregroundStyle(.secondary)
                    Picker("RIR", selection: $set.rir) {
                        Text("–").tag(-1)
                        ForEach(0...5, id: \.self) { value in
                            Text(value == 5 ? "5+" : "\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            if set.bestWeight > 0 && !set.isWarmup {
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
