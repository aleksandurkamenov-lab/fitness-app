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
