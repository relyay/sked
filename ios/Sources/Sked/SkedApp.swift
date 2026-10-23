import SwiftUI

@main
struct SkedApp: App {
    @State private var model: AppModel

    init() {
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
            UserDefaults.standard.removeObject(forKey: "profile")
            ScheduleCache().removeAll()
        }
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, Format.locale)
        }
    }
}
