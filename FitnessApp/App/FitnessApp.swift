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
        ])
    }
}
