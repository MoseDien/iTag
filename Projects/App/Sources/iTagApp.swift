import ComposableArchitecture
import SwiftUI

@main
struct iTagApp: App {
    private let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}
