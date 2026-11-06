import SwiftUI
import SwiftData

@main
struct FitnessApp: App {
    init() {
        UserDefaults.standard.set([AppLanguage.current.rawValue], forKey: "AppleLanguages")
    }

    var body: some Scene {
        WindowGroup {
            LanguageRoot()
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

/// Следи езика и пресъздава целия интерфейс при смяна, за да няма смесен български и английски.
private struct LanguageRoot: View {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.bg.rawValue

    var body: some View {
        RootTabView()
            .environment(\.locale, (AppLanguage(rawValue: language) ?? .bg).locale)
            .id(language)
    }
}
