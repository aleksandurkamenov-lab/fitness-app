import SwiftUI
import SwiftData

/// Таблица като в Excel: за всяко упражнение седмиците една под друга, кг × повт. по серии и обем вдясно.
/// Въведеното тук се записва като тренировка за съответната седмица и се вижда в историята.
struct MesoGridView: View {
    @Environment(\.modelContext) private var context
    let template: WorkoutTemplate
    @Binding var activeSession: WorkoutSession?
    @Query(sort: \WorkoutSession.date) private var allSessions: [WorkoutSession]
    @State private var isEditing = false
    @State private var showingPicker = false

    private var weeks: Int { max(template.mesocycle?.weekCount ?? 4, 1) }

    private var sessions: [WorkoutSession] {
        allSessions.filter { $0.template?.persistentModelID == template.persistentModelID }
    }

    /// За седмицата се взима сесията с най-много серии (при равенство - най-новата).
    private func session(week: Int) -> WorkoutSession? {
        pick(from: sessions, week: week)
    }

    private func pick(from list: [WorkoutSession], week: Int) -> WorkoutSession? {
        var best: WorkoutSession?
        for candidate in list where candidate.week == week {
            if best == nil || candidate.sets.count >= (best?.sets.count ?? 0) { best = candidate }
        }
        return best
    }

    /// Работните серии на упражнението за седмицата, по реда на сериите.
    private func sets(for item: TemplateExercise, week: Int) -> [SetEntry] {
        guard let session = session(week: week), let exercise = item.exercise else { return [] }
        return session.sets
            .filter { $0.exerciseOrder == item.order && !$0.isWarmup
                && $0.exercise?.persistentModelID == exercise.persistentModelID }
            .sorted { $0.setIndex < $1.setIndex }
    }

    private func setCount(for item: TemplateExercise) -> Int {
        var extra = 0
        for week in 1...weeks {
            let highest = (sets(for: item, week: week).map(\.setIndex).max() ?? -1) + 1
            extra = max(extra, highest)
        }
        return max(item.targets.count, extra)
    }

    private func volume(_ item: TemplateExercise, week: Int) -> Double {
        WorkoutMath.totalVolume(sets(for: item, week: week))
    }

    private func totalVolume(week: Int) -> Double {
        template.sortedItems.reduce(0) { $0 + volume($1, week: week) }
    }

    /// Най-близката предишна седмица с въведени данни.
    private func previousWeek(of week: Int, where hasData: (Int) -> Bool) -> Int? {
        guard week > 1 else { return nil }
        return (1..<week).reversed().first(where: hasData)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if template.items.isEmpty {
                    Text("Добави упражнения към тренировката, за да се появи таблицата.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
                ForEach(template.sortedItems) { item in
                    ExerciseGridCard(item: item, weeks: weeks, setCount: setCount(for: item),
                                     isEditing: isEditing,
                                     canRemoveSet: canRemoveSet(item),
                                     onAddSet: { addSet(to: item) },
                                     onRemoveSet: { removeSet(from: item) },
                                     onDelete: { context.delete(item) },
                                     sets: { sets(for: item, week: $0) },
                                     volume: { volume(item, week: $0) },
                                     previousWeek: { week in
                                         previousWeek(of: week) { volume(item, week: $0) > 0 }
                                     },
                                     binding: { binding(item, week: $0, index: $1) })
                }
                if isEditing {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Добави упражнение", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                if !template.items.isEmpty { totalCard }
                Text("Въвеждаш кг и повторения направо в таблицата. Сивите числа са от предишната седмица. Обемът = кг × повторения.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { exercise in
                let order = (template.items.map(\.order).max() ?? -1) + 1
                let item = TemplateExercise(exercise: exercise, order: order)
                item.template = template
                context.insert(item)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Готово" : "Редакция") { isEditing.toggle() }
            }
            ToolbarItem(placement: .secondaryAction) {
                NavigationLink {
                    TemplateDetailView(template: template, activeSession: $activeSession)
                } label: {
                    Label("Упражнения и старт", systemImage: "list.bullet.clipboard")
                }
            }
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Общо обем на тренировката").font(.headline)
            ForEach(1...weeks, id: \.self) { week in
                let value = totalVolume(week: week)
                let prev = previousWeek(of: week) { totalVolume(week: $0) > 0 }
                HStack {
                    Text("Седмица \(week)").foregroundStyle(.secondary)
                    Spacer()
                    Text(value > 0 ? "\(value.short) кг" : "–").font(.subheadline.weight(.semibold))
                    DeltaText(value: value, previous: prev.map { totalVolume(week: $0) })
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Редакция

    private func addSet(to item: TemplateExercise) {
        var targets = item.targets
        targets.append(SetTarget(repMin: targets.last?.repMin ?? 8, repMax: targets.last?.repMax ?? 12))
        item.targets = targets
    }

    /// Последната серия се маха само ако в нея няма въведени данни.
    private func canRemoveSet(_ item: TemplateExercise) -> Bool {
        let count = setCount(for: item)
        guard count > 1 else { return false }
        for week in 1...weeks {
            let logged = sets(for: item, week: week).contains { $0.setIndex == count - 1 && ($0.reps > 0 || $0.weight > 0) }
            if logged { return false }
        }
        return true
    }

    private func removeSet(from item: TemplateExercise) {
        let count = setCount(for: item)
        for week in 1...weeks {
            for entry in sets(for: item, week: week) where entry.setIndex == count - 1 { context.delete(entry) }
        }
        var targets = item.targets
        if targets.count > 1 && targets.count >= count { targets.removeLast() }
        item.targets = targets
    }

    // MARK: Запис

    /// Връзка към серия; тренировката и серията се създават чак когато въведеш стойност.
    private func binding(_ item: TemplateExercise, week: Int, index: Int) -> (weight: Binding<Double>, reps: Binding<Int?>) {
        let existing = { sets(for: item, week: week).first { $0.setIndex == index } }
        let weight = Binding<Double>(
            get: { existing()?.weight ?? 0 },
            set: { newValue in
                guard newValue > 0 || existing() != nil else { return }
                ensureSet(item, week: week, index: index).weight = newValue
            }
        )
        let reps = Binding<Int?>(
            get: { existing().flatMap { $0.reps > 0 ? $0.reps : nil } },
            set: { newValue in
                guard (newValue ?? 0) > 0 || existing() != nil else { return }
                let set = ensureSet(item, week: week, index: index)
                set.reps = newValue ?? 0
                set.isDone = set.reps > 0
            }
        )
        return (weight, reps)
    }

    private func ensureSession(week: Int) -> WorkoutSession {
        // @Query може да не е опреснен веднага след запис, затова се търси директно в контекста.
        let fresh = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let mine = fresh.filter { $0.template?.persistentModelID == template.persistentModelID }
        if let found = pick(from: mine, week: week) { return found }
        let start = template.mesocycle?.startDate ?? .now
        let planned = Calendar.current.date(byAdding: .day, value: (week - 1) * 7, to: start) ?? .now
        let session = WorkoutSession(date: min(planned, .now), week: week, template: template)
        session.finishedAt = session.date
        context.insert(session)
        return session
    }

    private func ensureSet(_ item: TemplateExercise, week: Int, index: Int) -> SetEntry {
        let session = ensureSession(week: week)
        let exerciseID = item.exercise?.persistentModelID
        let found = session.sets.first { entry in
            entry.exerciseOrder == item.order && !entry.isWarmup && entry.setIndex == index
                && entry.exercise?.persistentModelID == exerciseID
        }
        if let found { return found }
        let targets = item.targets
        let target = index < targets.count ? targets[index] : targets.last
        let set = SetEntry(exercise: item.exercise, exerciseOrder: item.order, setIndex: index,
                           targetRepMin: target?.repMin ?? 0, targetRepMax: target?.repMax ?? 0,
                           restSeconds: item.restSeconds, bestWeight: target?.bestWeight ?? 0,
                           bestReps: target?.bestReps ?? 0, exerciseNote: index == 0 ? item.note : "",
                           plannedWeight: target?.plannedWeight ?? 0)
        set.supersetNext = item.supersetNext
        set.session = session
        context.insert(set)
        return set
    }
}

private struct ExerciseGridCard: View {
    let item: TemplateExercise
    let weeks: Int
    let setCount: Int
    let isEditing: Bool
    let canRemoveSet: Bool
    let onAddSet: () -> Void
    let onRemoveSet: () -> Void
    let onDelete: () -> Void
    let sets: (Int) -> [SetEntry]
    let volume: (Int) -> Double
    let previousWeek: (Int) -> Int?
    let binding: (Int, Int) -> (weight: Binding<Double>, reps: Binding<Int?>)

    private let weekWidth: CGFloat = 26
    private let cellWidth: CGFloat = 70
    private let volumeWidth: CGFloat = 58
    private let repsWidth: CGFloat = 34

    private func targetText(_ index: Int) -> String {
        let targets = item.targets
        guard index < targets.count else { return "" }
        return targets[index].rangeText
    }

    private func bestText(_ index: Int) -> String {
        let targets = item.targets
        guard index < targets.count else { return "" }
        return targets[index].bestText ?? ""
    }

    private func totalReps(_ week: Int) -> Int {
        WorkoutMath.totalReps(sets(week))
    }

    private func hintWeight(_ set: SetEntry?) -> String {
        guard let set, set.weight > 0 else { return "" }
        return set.weight.short
    }

    private func hintReps(_ set: SetEntry?) -> String {
        guard let set, set.reps > 0 else { return "" }
        return "\(set.reps)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                HStack {
                    if let exercise = item.exercise {
                        ExerciseNameField(exercise: exercise)
                    }
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                }
                HStack {
                    Button(action: onRemoveSet) { Label("Серия", systemImage: "minus.circle") }
                        .disabled(!canRemoveSet)
                    Button(action: onAddSet) { Label("Серия", systemImage: "plus.circle") }
                    Spacer()
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 2) {
                if !isEditing { Text(item.exercise?.name ?? "Упражнение").font(.headline) }
                Text("Колона „Повт.“ е общо повторения; 🏆 е най-добрият до сега.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Text("Сед.").frame(width: weekWidth)
                        ForEach(0..<setCount, id: \.self) { index in
                            VStack(spacing: 0) {
                                Text("Серия \(index + 1)")
                                Text(targetText(index)).foregroundStyle(.primary)
                            }
                            .frame(width: cellWidth)
                        }
                        Text("Повт.").frame(width: repsWidth)
                        Text("Обем").frame(width: volumeWidth)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                    if item.targets.contains(where: { $0.bestText != nil }) {
                        HStack(spacing: 4) {
                            Text("🏆").frame(width: weekWidth)
                            ForEach(0..<setCount, id: \.self) { index in
                                Text(bestText(index)).frame(width: cellWidth)
                            }
                            Color.clear.frame(width: repsWidth, height: 1)
                            Color.clear.frame(width: volumeWidth, height: 1)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                    }

                    ForEach(1...weeks, id: \.self) { week in
                        let prev = previousWeek(week)
                        HStack(spacing: 4) {
                            Text("\(week)")
                                .font(.subheadline.weight(.bold))
                                .frame(width: weekWidth)
                            ForEach(0..<setCount, id: \.self) { index in
                                let hint = prev.flatMap { pw in sets(pw).first { entry in entry.setIndex == index } }
                                GridCell(binding: binding(week, index),
                                         weightHint: hintWeight(hint),
                                         repsHint: hintReps(hint))
                                    .frame(width: cellWidth)
                            }
                            Text(totalReps(week) > 0 ? "\(totalReps(week))" : "–")
                                .font(.subheadline)
                                .monospacedDigit()
                                .frame(width: repsWidth)
                            VStack(spacing: 0) {
                                let value = volume(week)
                                Text(value > 0 ? value.short : "–")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                DeltaText(value: value, previous: prev.map { volume($0) })
                            }
                            .frame(width: volumeWidth)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Едно поле „кг × повт.“.
private struct GridCell: View {
    let binding: (weight: Binding<Double>, reps: Binding<Int?>)
    let weightHint: String
    let repsHint: String

    var body: some View {
        HStack(spacing: 2) {
            DecimalField(placeholder: weightHint, value: binding.weight)
                .multilineTextAlignment(.center)
                .frame(width: 38, height: 32)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Text("×").font(.caption2).foregroundStyle(.secondary)
            TextField(repsHint, value: binding.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 24, height: 32)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .font(.subheadline)
    }
}

/// Промяна в обема спрямо предишната седмица с данни.
private struct DeltaText: View {
    let value: Double
    let previous: Double?

    var body: some View {
        if value > 0, let previous, previous > 0 {
            let percent = (value - previous) / previous * 100
            Text("\(percent >= 0 ? "+" : "")\(percent.formatted(.number.precision(.fractionLength(0))))%")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(percent >= 0 ? Color.green : Color.red)
        } else {
            Text(" ").font(.caption2)
        }
    }
}

/// Преименуване на упражнението (променя името и в библиотеката).
private struct ExerciseNameField: View {
    @Bindable var exercise: Exercise

    var body: some View {
        TextField("Име на упражнението", text: $exercise.name)
            .font(.headline)
            .textFieldStyle(.roundedBorder)
    }
}
