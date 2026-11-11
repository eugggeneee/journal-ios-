import SwiftUI

@main
struct JournalApp: App {
    @State private var store: AppStore
    @State private var repo: ScheduleRepo
    @State private var router = Router()
    @State private var toaster = Toaster()

    init() {
        let s = DemoMode.makeStore()
        _store = State(initialValue: s)
        _repo = State(initialValue: ScheduleRepo(store: s))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(repo)
                .environment(router)
                .environment(toaster)
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
    }
}
