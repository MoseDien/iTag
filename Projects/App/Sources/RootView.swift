import ComposableArchitecture
import FeatureCheckIn
import FeatureHistory
import SwiftUI

/// 根视图：打卡 / 历史 双 Tab。
public struct RootView: View {
    private let store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        TabView {
            NavigationStack {
                CheckInView(store: store.scope(state: \.checkIn, action: \.checkIn))
                    .navigationTitle("打卡")
            }
            .tabItem {
                Label("打卡", systemImage: "location.circle.fill")
            }

            NavigationStack {
                HistoryView(store: store.scope(state: \.history, action: \.history))
                    .navigationTitle("历史")
            }
            .tabItem {
                Label("历史", systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

#Preview {
    RootView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
                .dependency(\.locationClient, .previewValue)
                .dependency(\.geocodingClient, .previewValue)
                .dependency(\.checkInClient, .previewValue)
        }
    )
}
