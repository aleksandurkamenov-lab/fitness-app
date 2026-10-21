import Foundation
import SwiftData

/// Сглобява контекста от данните в приложението, говори с Claude и изпълнява записванията.
enum AIAssistant {
    static var tools: [[String: Any]] {
        [
            [
                "name": "log_food",
                "description": "Записва изядена храна в дневника. Викай го по веднъж за всяка храна.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Име на храната на български"],
                        "grams": ["type": "number", "description": "Изядени грамове"],
                        "kcal": ["type": "number", "description": "Калории за изядените грамове"],
                        "protein": ["type": "number", "description": "Протеин в грамове за изядените грамове"],
                        "carbs": ["type": "number", "description": "Въглехидрати в грамове"],
                        "fat": ["type": "number", "description": "Мазнини в грамове"],
                        "meal": ["type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"]],
                        "date": ["type": "string", "description": "Дата YYYY-MM-DD, ако не е днес"],
                    ],
                    "required": ["name", "grams", "kcal", "protein", "carbs", "fat", "meal"],
                ],
            ],
            [
                "name": "log_weight",
                "description": "Записва телесно тегло в кг.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "kg": ["type": "number"],
                        "date": ["type": "string", "description": "Дата YYYY-MM-DD, ако не е днес"],
                    ],
                    "required": ["kg"],
                ],
            ],
        ]
    }

    /// Изпраща разговора и изпълнява действията, докато Claude не върне текст.
    static func run(history: [AIMessage], model: String, context: ModelContext,
                    healthDays: [Date: NutritionDay],
                    images: [(label: String, data: Data)] = []) async throws -> (reply: String, actions: [String]) {
        let system = systemPrompt(context: context, healthDays: healthDays)
        var messages = apiMessages(history)
        // Снимките се прикачват към последното съобщение на потребителя.
        if !images.isEmpty, let last = messages.last, (last["role"] as? String) == "user",
           let text = last["content"] as? String {
            var blocks: [[String: Any]] = []
            for image in images {
                blocks.append(["type": "text", "text": image.label])
                blocks.append(["type": "image", "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": image.data.base64EncodedString(),
                ]])
            }
            blocks.append(["type": "text", "text": text])
            messages[messages.count - 1] = ["role": "user", "content": blocks]
        }
        var actions: [String] = []
        for _ in 0..<5 {
            let result = try await ClaudeService.send(model: model, system: system, messages: messages, tools: tools)
            guard result.stopReason == "tool_use" else {
                let text = result.content
                    .compactMap { block -> String? in
                        (block["type"] as? String) == "text" ? block["text"] as? String : nil
                    }
                    .joined(separator: "\n")
                if text.isEmpty && actions.isEmpty { throw ClaudeError(message: "Няма отговор, опитай пак.") }
                return (text, actions)
            }
            messages.append(["role": "assistant", "content": result.content])
            var results: [[String: Any]] = []
            for block in result.content where (block["type"] as? String) == "tool_use" {
                let id = (block["id"] as? String) ?? ""
                let name = (block["name"] as? String) ?? ""
                let input = (block["input"] as? [String: Any]) ?? [:]
                let outcome = execute(name: name, input: input, context: context)
                actions.append(outcome)
                // Записва се веднага, за да го има в историята и при грешка в следващата заявка.
                context.insert(AIMessage(role: "action", text: outcome))
                try? context.save()
                results.append(["type": "tool_result", "tool_use_id": id, "content": outcome])
            }
            messages.append(["role": "user", "content": results])
        }
        return ("", actions)
    }

    /// Последните съобщения като редуващи се user/assistant, започващи с user.
    private static func apiMessages(_ history: [AIMessage]) -> [[String: Any]] {
        var turns: [(role: String, text: String)] = []
        for message in history.suffix(20) {
            let role = message.role == "user" ? "user" : "assistant"
            let text = message.role == "action" ? "[" + message.text + "]" : message.text
            if let last = turns.last, last.role == role {
                turns[turns.count - 1].text += "\n" + text
            } else {
                turns.append((role: role, text: text))
            }
        }
        while let first = turns.first, first.role != "user" { turns.removeFirst() }
        return turns.map { ["role": $0.role, "content": $0.text] }
    }

    /// За всяка поза: последната снимка и предишната поне 6 дни по-стара, смалени до 800 px.
    static func weeklyPhotos(context: ModelContext) -> [(label: String, data: Data)] {
        let photos = (try? context.fetch(FetchDescriptor<ProgressPhoto>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        var result: [(label: String, data: Data)] = []
        for pose in PhotoPose.allCases {
            let posePhotos = photos.filter { $0.pose == pose }
            guard let latest = posePhotos.first else { continue }
            let cutoff = latest.date.addingTimeInterval(-6 * 86_400)
            var picked = [latest]
            if let previous = posePhotos.first(where: { $0.date <= cutoff }) { picked.insert(previous, at: 0) }
            for photo in picked {
                guard let data = PhotoImport.downscaled(photo.imageData, maxPixels: 800) else { continue }
                result.append((label: "Снимка \(pose.title), \(key(photo.date)):", data: data))
            }
        }
        return result
    }

    // MARK: - Действия

    static func execute(name: String, input: [String: Any], context: ModelContext) -> String {
        switch name {
        case "log_food":
            let food = ((input["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let grams = number(input["grams"]),
                  let kcal = number(input["kcal"]),
                  let protein = number(input["protein"]),
                  let carbs = number(input["carbs"]),
                  let fat = number(input["fat"]),
                  isValidFoodInput(name: food, grams: grams, kcal: kcal, protein: protein, carbs: carbs, fat: fat) else {
                return "Невалидни данни за храната; нищо не е записано."
            }
            let meal = Meal(rawValue: (input["meal"] as? String) ?? "") ?? mealByHour()
            context.insert(FoodEntry(date: date(input["date"]), meal: meal, name: food, grams: grams,
                                     kcal: kcal, protein: protein, carbs: carbs, fat: fat))
            let saved = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
            if let item = saved.first(where: { $0.name.lowercased() == food.lowercased() }) {
                item.lastUsed = .now
            } else {
                let factor = 100 / grams
                let item = FoodItem(name: food, kcalPer100: kcal * factor, proteinPer100: protein * factor,
                                    carbsPer100: carbs * factor, fatPer100: fat * factor, servingG: grams)
                item.lastUsed = .now
                context.insert(item)
            }
            try? context.save()
            return "Записано: \(food) \(short(grams)) г, \(Int(kcal.rounded())) ккал (\(meal.title))"
        case "log_weight":
            guard let kg = number(input["kg"]), kg > 20, kg < 400 else { return "Невалидно тегло, нищо не е записано" }
            context.insert(WeightEntry(date: date(input["date"]), kg: kg))
            try? context.save()
            return "Записано тегло: \(short(kg)) кг"
        default:
            return "Непознато действие"
        }
    }

    static func isValidFoodInput(name: String, grams: Double, kcal: Double,
                                 protein: Double, carbs: Double, fat: Double) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && grams.isFinite && grams > 0
            && [kcal, protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 }
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    /// Дата от "YYYY-MM-DD": днес е сега, друг ден е по обяд.
    private static func date(_ value: Any?) -> Date {
        guard let text = value as? String else { return .now }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .now }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        let calendar = Calendar.current
        guard let day = calendar.date(from: components) else { return .now }
        return calendar.isDateInToday(day) ? .now : day
    }

    private static func mealByHour() -> Meal {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 11 { return .breakfast }
        if hour < 16 { return .lunch }
        if hour < 21 { return .dinner }
        return .snack
    }

    // MARK: - Контекст

    private static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func short(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    /// Текст за Claude приложението (без API ключ): данните, списък на снимките и задачата.
    static func exportText(task: String, context: ModelContext, healthDays: [Date: NutritionDay],
                           photoLabels: [String]) -> String {
        var text = systemPrompt(context: context, healthDays: healthDays, forExport: true)
        if !photoLabels.isEmpty {
            text += "\nПрикачени снимки по ред: " + photoLabels.joined(separator: "; ")
        }
        return text + "\n\nЗадача: " + task
    }

    static func systemPrompt(context: ModelContext, healthDays: [Date: NutritionDay], forExport: Bool = false) -> String {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        var lines: [String] = []
        lines.append("Ти си личен треньор и хранителен помощник във фитнес приложението на потребителя. Отговаряй на български, кратко и конкретно (английски термини са ок). Числата за здраве и хранене са ориентировъчни, не са медицински съвет; казвай го, когато даваш такива препоръки.")
        lines.append("Като треньор следиш съня, възстановяването (WHOOP), тренировките и прогреса по упражненията, теглото спрямо целта и оставащите макроси за деня. Свързвай ги: при ниско възстановяване или лош сън предлагай по-леко натоварване; при застой в упражнение предлагай промяна; при отклонение на теглото от целевото темпо предлагай корекция на калориите. За оставащите макроси давай конкретни храни и ястия с грамове, по възможност от запазените храни.")
        if forExport {
            lines.append("Данните по-долу са от моето фитнес приложение.")
        } else {
            lines.append("Когато потребителят каже какво е ял, запиши всяка храна с log_food. Ако храната я има в запазените храни, сметни от нейните стойности на 100 г, иначе оцени разумно. Когато каже теглото си, ползвай log_weight. Ако само пита, не записвай нищо.")
        }
        lines.append("Когато потребителят поиска седмичен анализ: прегледай теглото и тренда, мерките, снимките (сравни всяка поза с предишната, ако са прикачени), тренировките, обема по мускулни групи и прогреса по упражненията, храненето спрямо целите, съня и възстановяването. Сравни тази седмица с предишните. Завърши с 3 конкретни препоръки за следващата седмица.")
        lines.append("Днес е \(key(today)), \(now.formatted(.dateTime.weekday(.wide))), часът е \(now.formatted(date: .omitted, time: .shortened)).")

        var dailyTargets: BodyMath.Targets?
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        if let profile = profiles.first {
            let rate = profile.goal == .lose ? profile.lossRateKg : profile.gainRateKg
            let pace = profile.goal == .maintain ? "" : " с " + short(rate) + " кг седмично"
            lines.append("Профил: \(profile.sex.title), \(profile.age) г., \(Int(profile.heightCm)) см, цел: \(profile.goal.title)\(pace), коефициент на активност \(profile.activityFactor).")
            if let kg = weights.last?.kg, var targets = BodyMath.targets(profile: profile, kg: kg) {
                let custom = profile.customProteinG > 0 || profile.customFatG > 0 || profile.customCarbsG > 0
                if profile.customProteinG > 0 { targets.protein = profile.customProteinG }
                if profile.customFatG > 0 { targets.fat = profile.customFatG }
                if profile.customCarbsG > 0 { targets.carbs = profile.customCarbsG }
                if custom { targets.kcal = targets.protein * 4 + targets.carbs * 4 + targets.fat * 9 }
                dailyTargets = targets
                lines.append("Дневна цел: \(Int(targets.kcal)) ккал, протеин \(Int(targets.protein)) г, въглехидрати \(Int(targets.carbs)) г, мазнини \(Int(targets.fat)) г.")
                if profile.variableCalories {
                    lines.append("Променлив прием е включен: в тренировъчен ден целта е +\(Int(profile.trainingDayBoostPercent)) %, в почивен е по-ниска; разликата е във въглехидратите. Тренировъчни дни седмично: \(profile.trainingDaysPerWeek).")
                }
            }
        }

        let monthAgo = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let recentWeights = weights.filter { $0.date >= monthAgo }
        if !recentWeights.isEmpty {
            lines.append("Тегло за последните 30 дни: " + recentWeights.map { "\(key($0.date)) \(short($0.kg)) кг" }.joined(separator: ", "))
        }

        // Хранене: записаното в приложението плюс това от Apple Health.
        let twoWeeks = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let foods = (try? context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { $0.date >= twoWeeks },
            sortBy: [SortDescriptor(\.date)]))) ?? []
        var totals: [Date: NutritionDay] = [:]
        for food in foods {
            let day = calendar.startOfDay(for: food.date)
            var total = totals[day] ?? NutritionDay()
            total.kcal += food.kcal
            total.protein += food.protein
            total.carbs += food.carbs
            total.fat += food.fat
            totals[day] = total
        }
        for (day, health) in healthDays where day >= twoWeeks {
            var total = totals[day] ?? NutritionDay()
            total.kcal += health.kcal
            total.protein += health.protein
            total.carbs += health.carbs
            total.fat += health.fat
            totals[day] = total
        }
        if !totals.isEmpty {
            lines.append("Хранене по дни (ккал / П / В / М в г):")
            for day in totals.keys.sorted() {
                if let t = totals[day] {
                    lines.append("\(key(day)): \(Int(t.kcal)) / \(Int(t.protein)) / \(Int(t.carbs)) / \(Int(t.fat))")
                }
            }
        }
        if let targets = dailyTargets {
            let eaten = totals[today] ?? NutritionDay()
            lines.append("Остава за днес: \(Int(targets.kcal - eaten.kcal)) ккал, протеин \(Int(targets.protein - eaten.protein)) г, въглехидрати \(Int(targets.carbs - eaten.carbs)) г, мазнини \(Int(targets.fat - eaten.fat)) г (отрицателно значи над целта).")
        }
        let todayFoods = foods.filter { calendar.isDate($0.date, inSameDayAs: today) }
        if !todayFoods.isEmpty {
            lines.append("Днес записано: " + todayFoods.map {
                "\($0.meal.title): \($0.name) \(short($0.grams)) г (\(Int($0.kcal)) ккал, П \(Int($0.protein)))"
            }.joined(separator: "; "))
        }

        // Тренировки за последните 4 седмици.
        let fourWeeks = calendar.date(byAdding: .day, value: -28, to: today) ?? today
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.date >= fourWeeks },
            sortBy: [SortDescriptor(\.date)]))) ?? []
        if !sessions.isEmpty { lines.append("Тренировки (кг×повторения на завършените работни серии, RIR = повторения в резерв):") }
        for session in sessions {
            let done = session.sortedSets.filter { $0.isWorkSet }
            guard !done.isEmpty else { continue }
            var byExercise: [(name: String, sets: [String])] = []
            for set in done {
                let name = set.exercise?.name ?? "?"
                let rir = set.rir >= 0 ? " RIR\(set.rir)" : ""
                let text = "\(short(set.weight))×\(set.repsText)\(rir)"
                if let index = byExercise.firstIndex(where: { $0.name == name }) {
                    byExercise[index].sets.append(text)
                } else {
                    byExercise.append((name: name, sets: [text]))
                }
            }
            lines.append("\(key(session.date)) \(session.title): " + byExercise.map {
                "\($0.name) \($0.sets.joined(separator: ", "))"
            }.joined(separator: "; "))
        }

        // Мерки за последните 8 седмици.
        let eightWeeks = calendar.date(byAdding: .day, value: -56, to: today) ?? today
        let measurements = (try? context.fetch(FetchDescriptor<MeasurementEntry>(
            predicate: #Predicate<MeasurementEntry> { $0.date >= eightWeeks },
            sortBy: [SortDescriptor(\.date)]))) ?? []
        if !measurements.isEmpty {
            lines.append("Мерки в см (последни 8 седмици):")
            var byDay: [(day: Date, parts: [String])] = []
            for entry in measurements {
                let day = calendar.startOfDay(for: entry.date)
                var title = MeasurementKind(rawValue: entry.kindRaw)?.title ?? entry.kindRaw
                if entry.sideRaw == "left" { title += " ляво" }
                if entry.sideRaw == "right" { title += " дясно" }
                if entry.isFlexed { title += " стегнато" }
                let text = "\(title) \(short(entry.cm))"
                if let index = byDay.firstIndex(where: { $0.day == day }) {
                    byDay[index].parts.append(text)
                } else {
                    byDay.append((day: day, parts: [text]))
                }
            }
            for item in byDay { lines.append("\(key(item.day)): " + item.parts.joined(separator: ", ")) }
        }

        // Седмичен обем за последните 6 седмици.
        var weekCalendar = Calendar.current
        weekCalendar.firstWeekday = 2
        let thisWeek = weekCalendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let sixWeeks = weekCalendar.date(byAdding: .day, value: -35, to: thisWeek) ?? thisWeek
        let volumeSessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.date >= sixWeeks }))) ?? []
        var weeks: [Date: [SetEntry]] = [:]
        for session in volumeSessions {
            let week = weekCalendar.dateInterval(of: .weekOfYear, for: session.date)?.start ?? calendar.startOfDay(for: session.date)
            weeks[week, default: []].append(contentsOf: session.sets)
        }
        if !weeks.isEmpty {
            lines.append("Седмичен обем (седмица от понеделник: тонаж кг; серии по мускулни групи, второстепенните броят 0.5):")
            for week in weeks.keys.sorted() {
                let sets = weeks[week] ?? []
                let groups = WorkoutMath.weeklySets(sets)
                    .sorted { $0.value > $1.value }
                    .map { "\($0.key.title) \(short($0.value))" }
                    .joined(separator: ", ")
                lines.append("\(key(week)): \(Int(WorkoutMath.totalVolume(sets))) кг; \(groups)")
            }
        }

        // WHOOP и Health за последните 7 дни.
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let metrics = (try? context.fetch(FetchDescriptor<DailyMetric>(
            predicate: #Predicate<DailyMetric> { $0.day >= weekAgo }))) ?? []
        var chosen: [Date: [MetricKind: DailyMetric]] = [:]
        for metric in metrics {
            guard let kind = metric.kind else { continue }
            let day = calendar.startOfDay(for: metric.day)
            let preferred = kind.preferHealth ? MetricSource.health.rawValue : MetricSource.whoop.rawValue
            if let existing = chosen[day]?[kind], existing.sourceRaw == preferred { continue }
            chosen[day, default: [:]][kind] = metric
        }
        if !chosen.isEmpty { lines.append("Възстановяване и активност:") }
        for day in chosen.keys.sorted() {
            let parts = MetricKind.allCases.compactMap { kind -> String? in
                guard let metric = chosen[day]?[kind] else { return nil }
                let value = String(format: "%.\(kind.digits)f", metric.value)
                return kind.unit.isEmpty ? "\(kind.title) \(value)" : "\(kind.title) \(value) \(kind.unit)"
            }
            lines.append("\(key(day)): " + parts.joined(separator: ", "))
        }

        var savedDescriptor = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.lastUsed, order: .reverse)])
        savedDescriptor.fetchLimit = 40
        let saved = (try? context.fetch(savedDescriptor)) ?? []
        if !saved.isEmpty {
            lines.append("Запазени храни (на 100 г: ккал / П / В / М):")
            for item in saved {
                lines.append("\(item.name): \(Int(item.kcalPer100)) / \(short(item.proteinPer100)) / \(short(item.carbsPer100)) / \(short(item.fatPer100))")
            }
        }
        return lines.joined(separator: "\n")
    }
}
