import SwiftUI
import SwiftData

@main
struct FitnessApp: App {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.bg.rawValue

    init() {
        UserDefaults.standard.set([AppLanguage.current.rawValue], forKey: "AppleLanguages")
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.locale, (AppLanguage(rawValue: language) ?? .bg).locale)
                .id(language)
        }
        .modelContainer(for: [
            Exercise.self,
            Mesocycle.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            WorkoutSession.self,
            SetEntry.self,
            UserProfile.self,
            WeightEntry.self,
            BodyScan.self,
            MeasurementEntry.self,
            DailyMetric.self,
            FoodItem.self,
            FoodEntry.self,
            ProgressPhoto.self,
            AIMessage.self,
        ])
    }
}
