import SwiftUI
import VKSITCore

@main
struct VKSITApp: App {
    @State private var model: AppModel

    init() {
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
            UserDefaults.standard.removeObject(forKey: "profile")
            ScheduleCache().removeAll()
        }
        let model = AppModel()
        let env = ProcessInfo.processInfo.environment
        if let host = env["VKSIT_SERVER_HOST"], let port = env["VKSIT_SERVER_PORT"],
           case .success(let address) = ServerAddress.validate(host: host, port: port) {
            model.save(server: address)
        }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
