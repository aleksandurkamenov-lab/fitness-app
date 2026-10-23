import Foundation
import SwiftData

/// Начална библиотека с упражнения. Добавя се само веднъж; после потребителят я допълва.
enum ExerciseLibrary {
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        guard count == 0 else { return }
        for exercise in defaults {
            context.insert(exercise)
        }
        try? context.save()
    }

    /// Добавя разширената библиотека веднъж; не връща упражнения, които си изтрил после, и не дублира имена.
    static func addExtrasIfNeeded(_ context: ModelContext) {
        let key = "exerciseLibraryExtrasV1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let existing = Set(((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map { $0.name.lowercased() })
        for exercise in extras where !existing.contains(exercise.name.lowercased()) {
            context.insert(exercise)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    private static var extras: [Exercise] {
        [
            // Гърди
            Exercise(name: "Лежанка с дъмбели", primary: .chest, secondary: [.triceps, .shoulders]),
            Exercise(name: "Лежанка с щанга под наклон", primary: .chest, secondary: [.shoulders, .triceps]),
            Exercise(name: "Лежанка на машина", primary: .chest, secondary: [.triceps]),
            Exercise(name: "Пек дек", primary: .chest),
            Exercise(name: "Разпери с дъмбели", primary: .chest),
            Exercise(name: "Кросоувър отдолу нагоре", primary: .chest),
            Exercise(name: "Лицеви опори", primary: .chest, secondary: [.triceps, .shoulders]),
            // Гръб
            Exercise(name: "Мъртва тяга", primary: .back, secondary: [.hamstrings, .glutes]),
            Exercise(name: "Гребане с дъмбел", primary: .back, secondary: [.biceps]),
            Exercise(name: "Гребане на машина", primary: .back, secondary: [.biceps]),
            Exercise(name: "Гребане Т-щанга", primary: .back, secondary: [.biceps]),
            Exercise(name: "Пулъвър с изправени ръце", primary: .back),
            Exercise(name: "Вертикален скрипец тесен хват", primary: .back, secondary: [.biceps]),
            Exercise(name: "Набирания с обратен хват", primary: .back, secondary: [.biceps]),
            Exercise(name: "Хиперекстензия", primary: .back, secondary: [.glutes, .hamstrings]),
            Exercise(name: "Шрагс с щанга", primary: .back),
            Exercise(name: "Шрагс с дъмбели", primary: .back),
            // Рамене
            Exercise(name: "Раменна преса с щанга", primary: .shoulders, secondary: [.triceps]),
            Exercise(name: "Раменна преса на машина", primary: .shoulders, secondary: [.triceps]),
            Exercise(name: "Странично повдигане на скрипец", primary: .shoulders),
            Exercise(name: "Задно рамо на пек дек", primary: .shoulders),
            Exercise(name: "Задно рамо с дъмбели", primary: .shoulders),
            Exercise(name: "Предно повдигане", primary: .shoulders),
            Exercise(name: "Вертикално гребане", primary: .shoulders, secondary: [.back]),
            // Бицепс
            Exercise(name: "Бицепсово сгъване с щанга", primary: .biceps, secondary: [.forearms]),
            Exercise(name: "Бицепсово сгъване със Z-щанга", primary: .biceps),
            Exercise(name: "Бицепсово сгъване на скрипец", primary: .biceps),
            Exercise(name: "Бицепсово сгъване на пулт Скот", primary: .biceps),
            Exercise(name: "Бицепсово сгъване седнал под наклон", primary: .biceps),
            Exercise(name: "Концентрирано сгъване", primary: .biceps),
            // Трицепс
            Exercise(name: "Трицепсово разгъване с въже", primary: .triceps),
            Exercise(name: "Трицепсово разгъване над глава", primary: .triceps),
            Exercise(name: "Тесен лег с щанга", primary: .triceps, secondary: [.chest, .shoulders]),
            Exercise(name: "Кофички на успоредка", primary: .triceps, secondary: [.chest]),
            Exercise(name: "Разгъване с дъмбел зад главата", primary: .triceps),
            // Предмишници
            Exercise(name: "Сгъване на китки", primary: .forearms),
            Exercise(name: "Обратно сгъване с щанга", primary: .forearms, secondary: [.biceps]),
            Exercise(name: "Фермерска разходка", primary: .forearms, secondary: [.back]),
            // Крака
            Exercise(name: "Преден клек", primary: .quads, secondary: [.glutes]),
            Exercise(name: "Гоблет клек", primary: .quads, secondary: [.glutes]),
            Exercise(name: "Клек на машина Смит", primary: .quads, secondary: [.glutes]),
            Exercise(name: "Напади с дъмбели", primary: .quads, secondary: [.glutes, .hamstrings]),
            Exercise(name: "Напади в движение", primary: .quads, secondary: [.glutes, .hamstrings]),
            Exercise(name: "Степ ъп", primary: .quads, secondary: [.glutes]),
            Exercise(name: "Мъртва тяга с изправени крака", primary: .hamstrings, secondary: [.glutes, .back]),
            Exercise(name: "Румънска мъртва тяга с дъмбели", primary: .hamstrings, secondary: [.glutes, .back]),
            Exercise(name: "Добро утро", primary: .hamstrings, secondary: [.glutes, .back]),
            Exercise(name: "Нордик сгъване", primary: .hamstrings),
            Exercise(name: "Хип тръст с щанга", primary: .glutes, secondary: [.hamstrings]),
            Exercise(name: "Глутеус бридж", primary: .glutes, secondary: [.hamstrings]),
            Exercise(name: "Отвличане на бедро на машина", primary: .glutes),
            Exercise(name: "Задно отпускане на скрипец", primary: .glutes),
            Exercise(name: "Повдигане на пръсти на преса", primary: .calves),
            Exercise(name: "Повдигане на пръсти с дъмбел", primary: .calves),
            // Корем
            Exercise(name: "Коремни преси", primary: .abs),
            Exercise(name: "Планк", primary: .abs),
            Exercise(name: "Колело за корем", primary: .abs, secondary: [.shoulders]),
            Exercise(name: "Руски завои", primary: .abs),
            Exercise(name: "Повдигане на крака легнал", primary: .abs),
            Exercise(name: "Странични преси", primary: .abs),
        ]
    }

    private static var defaults: [Exercise] {
        [
            Exercise(name: "Лежанка с щанга", primary: .chest, secondary: [.triceps, .shoulders]),
            Exercise(name: "Лежанка с дъмбели под наклон", primary: .chest, secondary: [.shoulders, .triceps]),
            Exercise(name: "Кросоувър на скрипец", primary: .chest),
            Exercise(name: "Кофички", primary: .chest, secondary: [.triceps]),
            Exercise(name: "Набирания", primary: .back, secondary: [.biceps]),
            Exercise(name: "Вертикален скрипец", primary: .back, secondary: [.biceps]),
            Exercise(name: "Гребане с щанга", primary: .back, secondary: [.biceps]),
            Exercise(name: "Гребане на хоризонтален скрипец", primary: .back, secondary: [.biceps]),
            Exercise(name: "Раменна преса с дъмбели", primary: .shoulders, secondary: [.triceps]),
            Exercise(name: "Странично повдигане", primary: .shoulders),
            Exercise(name: "Face pull", primary: .shoulders, secondary: [.back]),
            Exercise(name: "Бицепсово сгъване с дъмбели", primary: .biceps),
            Exercise(name: "Чук", primary: .biceps, secondary: [.forearms]),
            Exercise(name: "Трицепсово разгъване на скрипец", primary: .triceps),
            Exercise(name: "Френско разгъване", primary: .triceps),
            Exercise(name: "Клек с щанга", primary: .quads, secondary: [.glutes]),
            Exercise(name: "Хакен клек", primary: .quads, secondary: [.glutes]),
            Exercise(name: "Преса за крака", primary: .quads, secondary: [.glutes]),
            Exercise(name: "Бедрено разгъване", primary: .quads),
            Exercise(name: "Румънска мъртва тяга", primary: .hamstrings, secondary: [.glutes, .back]),
            Exercise(name: "Бедрено сгъване седнал", primary: .hamstrings),
            Exercise(name: "Бедрено сгъване легнал", primary: .hamstrings),
            Exercise(name: "Хип тръст", primary: .glutes, secondary: [.hamstrings]),
            Exercise(name: "Български клек", primary: .quads, secondary: [.glutes]),
            Exercise(name: "Повдигане на пръсти прав", primary: .calves),
            Exercise(name: "Повдигане на пръсти седнал", primary: .calves),
            Exercise(name: "Коремни преси на скрипец", primary: .abs),
            Exercise(name: "Повдигане на крака от вис", primary: .abs),
        ]
    }
}
