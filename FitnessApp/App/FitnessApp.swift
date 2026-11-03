import SwiftUI
import SwiftData

@main
struct FitnessApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
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
