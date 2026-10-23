import SwiftUI
import VKSITCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if model.profile == nil {
            OnboardingView()
        } else {
            MainTabView()
                .task(id: scenePhase) {
                    // Refresh on launch, on return to foreground and every
                    // 5 minutes while visible; the server polls the PDFs
                    // every 2 minutes and 304s keep this cheap.
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await model.refresh()
                        try? await Task.sleep(for: .seconds(300))
                    }
                }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab(L("tab.home"), systemImage: "house") {
                HomeView()
            }
            Tab(L("tab.schedule"), systemImage: "calendar") {
                ScheduleView()
            }
            Tab(L("tab.profile"), systemImage: "person.crop.circle") {
                ProfileView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
