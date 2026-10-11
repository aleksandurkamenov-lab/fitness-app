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
    @State private var detail: GridDetail?
    @State private var timer = RestTimer()
    @AppStorage("gridRestTimer") private var restTimerOn = false

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
                                     onDetail: { detail = GridDetail(order: item.order, week: $0) },
                                     isRecord: { isRecordWeek(item, week: $0) },
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
                Text("Въвеждаш кг и повторения направо в таблицата и те се записват в историята. Сивите числа са от предишната седмица. Обемът = кг × повторения, 🏆 = нов рекорд.")
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
        .safeAreaInset(edge: .bottom) {
            if timer.endDate != nil { RestTimerBar(timer: timer) }
        }
        .sheet(item: $detail) { target in
            if let item = template.sortedItems.first(where: { $0.order == target.order }) {
                WeekDetailSheet(item: item, week: target.week,
                                entries: { allSets(for: item, week: target.week) },
                                onWarmups: { addWarmups(to: item, week: target.week) })
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Готово" : "Редакция") { isEditing.toggle() }
            }
            ToolbarItem(placement: .secondaryAction) {
                Toggle("Таймер за почивка", isOn: $restTimerOn)
            }
            ToolbarItem(placement: .secondaryAction) {
                NavigationLink {
                    TemplateDetailView(template: template, activeSession: $activeSession)
                } label: {
                    Label("Цели по серии и упражнения", systemImage: "list.bullet.clipboard")
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

    // MARK: Опции

    struct GridDetail: Identifiable {
        let order: Int
        let week: Int
        var id: Int { order * 100 + week }
    }

    /// Всички серии (и загрявките) на упражнението за седмицата.
    private func allSets(for item: TemplateExercise, week: Int) -> [SetEntry] {
        guard let session = session(week: week), let exercise = item.exercise else { return [] }
        return session.sets
            .filter { $0.exerciseOrder == item.order && $0.exercise?.persistentModelID == exercise.persistentModelID }
            .sorted { $0.setIndex < $1.setIndex }
    }

    /// Рекорд: тази седмица има по-тежка серия или по-висок 1RM от предишните седмици и от „най-добро до сега“.
    private func isRecordWeek(_ item: TemplateExercise, week: Int) -> Bool {
        let current = sets(for: item, week: week).filter { $0.reps > 0 }
        guard !current.isEmpty else { return false }
        var baseWeight = 0.0
        var baseOneRM = 0.0
        for target in item.targets {
            if let w = target.bestWeight, let r = target.bestReps {
                baseWeight = max(baseWeight, w)
                baseOneRM = max(baseOneRM, WorkoutMath.epley(weight: w, reps: Int(r.rounded())))
            }
        }
        if week > 1 {
            for earlier in 1..<week {
                for entry in sets(for: item, week: earlier) where entry.reps > 0 {
                    baseWeight = max(baseWeight, entry.weight)
                    baseOneRM = max(baseOneRM, entry.estimatedOneRepMax)
                }
            }
        }
        guard baseWeight > 0 else { return false }
        return current.contains { $0.weight > baseWeight + 0.001 || $0.estimatedOneRepMax > baseOneRM + 0.001 }
    }

    /// Загряващи серии 40/60/80 % от работната тежест (въведената, от предишната седмица или планираната).
    private func addWarmups(to item: TemplateExercise, week: Int) {
        var base = sets(for: item, week: week).first(where: { $0.weight > 0 })?.weight ?? 0
        if base == 0, week > 1 {
            for earlier in (1..<week).reversed() {
                if let found = sets(for: item, week: earlier).first(where: { $0.weight > 0 }) {
                    base = found.weight
                    break
                }
            }
        }
        if base == 0 { base = item.targets.first?.plannedWeight ?? 0 }
        guard base > 0 else { return }
        let session = ensureSession(week: week)
        let group = ExerciseGroup(order: item.order, exercise: item.exercise, sets: allSets(for: item, week: week))
        WorkoutService.addWarmups(to: group, baseWeight: base, session: session, in: context)
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
                if restTimerOn && set.reps > 0 { timer.start(seconds: item.restSeconds) }
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
    let onDetail: (Int) -> Void
    let isRecord: (Int) -> Bool
    let sets: (Int) -> [SetEntry]
    let volume: (Int) -> Double
    let previousWeek: (Int) -> Int?
    let binding: (Int, Int) -> (weight: Binding<Double>, reps: Binding<Int?>)

    private let weekWidth: CGFloat = 40
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
                Text("Натисни номера на седмицата за RIR, загрявки, плочи и бележка.")
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
                            Button { onDetail(week) } label: {
                                VStack(spacing: 0) {
                                    HStack(spacing: 1) {
                                        Text("\(week)").font(.subheadline.weight(.bold))
                                        Image(systemName: "ellipsis.circle").font(.caption2)
                                    }
                                    if isRecord(week) { Text("🏆").font(.caption2) }
                                }
                                .frame(width: weekWidth)
                            }
                            .buttonStyle(.plain)
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

/// Допълнителни опции за упражнение в дадена седмица: RIR, загрявки, плочи, бележка.
private struct WeekDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: TemplateExercise
    let week: Int
    let entries: () -> [SetEntry]
    let onWarmups: () -> Void
    @State private var plate: PlateRequest?

    private func workingWeight() -> Double {
        entries().first(where: { !$0.isWarmup && $0.weight > 0 })?.weight ?? 0
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(entries()) { entry in
                        DetailSetRow(set: entry)
                    }
                    if entries().isEmpty {
                        Text("Първо въведи кг и повторения в таблицата.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Седмица \(week)")
                }
                Section {
                    Button { onWarmups() } label: {
                        Label("Добави загрявки (40 / 60 / 80 %)", systemImage: "flame")
                    }
                    Button { plate = PlateRequest(weight: workingWeight()) } label: {
                        Label("Калкулатор на плочите", systemImage: "circle.grid.cross")
                    }
                }
                Section {
                    TextField("Бележка за упражнението", text: $item.note, axis: .vertical)
                } header: {
                    Text("Бележка")
                } footer: {
                    Text("Бележката е за упражнението във всички седмици.")
                }
            }
            .navigationTitle(item.exercise?.name ?? "Упражнение")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .sheet(item: $plate) { request in
                PlateCalculatorView(weight: request.weight)
            }
        }
    }
}

private struct DetailSetRow: View {
    @Bindable var set: SetEntry

    private var repsBinding: Binding<Int?> {
        Binding(get: { set.reps > 0 ? set.reps : nil },
                set: { set.reps = $0 ?? 0; set.isDone = set.reps > 0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if set.isWarmup {
                Label("Загрявка", systemImage: "flame")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Text("Серия \(set.setIndex + 1)").font(.subheadline.weight(.semibold))
            }
            HStack(spacing: 10) {
                DecimalField(placeholder: "кг", value: $set.weight)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                Text("×").foregroundStyle(.secondary)
                TextField("повт.", value: repsBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
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
        }
        .padding(.vertical, 2)
    }
}
