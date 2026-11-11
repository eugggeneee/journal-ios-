import SwiftUI

/// Корень приложения: онбординг или основные вкладки.
struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.onboarded && store.hasGroup {
            MainTabs()
        } else {
            OnboardingView(startAtGroup: store.onboarded)
        }
    }
}

struct MainTabs: View {
    @Environment(ScheduleRepo.self) private var repo
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("Расписание", systemImage: "calendar") { SchedulePage() }
            Tab("Оценки", systemImage: "star") { GradesPage() }
            Tab("Пропуски", systemImage: "calendar.badge.minus") { AbsencesPage() }
            Tab("Профиль", systemImage: "person.crop.circle") { ProfilePage() }
        }
        .sheetHost()
        .task { await repo.prefetch() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await repo.prefetch() } }
        }
    }
}
