import CloudSync
import ComposableArchitecture
import CoreClients
import Domain
import SwiftUI

/// 历史页：记录 / 地图 两种查看方式切换。
public struct HistoryView: View {
    private let store: StoreOf<HistoryFeature>

    /// 全屏查看的照片（临时 UI 状态，不入 Store）。
    @State private var selectedPhoto: PhotoViewerItem?

    public init(store: StoreOf<HistoryFeature>) {
        self.store = store
    }

    public var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            Picker("查看方式", selection: $store.viewMode) {
                ForEach(HistoryFeature.ViewMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            switch store.viewMode {
            case .list:
                recordList
            case .map:
                HistoryMapView(store: store)
            }
        }
        .task { store.send(.onTask) }
        .alert($store.scope(state: \.alert, action: \.alert))
        .sheet(item: $store.scope(state: \.editing, action: \.editing)) { detailStore in
            CheckInDetailView(store: detailStore)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                cloudStatusView
            }
        }
        .fullScreenCover(item: $selectedPhoto) { item in
            PhotoViewer(photoID: item.photoID)
        }
    }

    // MARK: - 云同步状态

    @ViewBuilder
    private var cloudStatusView: some View {
        switch store.cloudStatus {
        case .syncing:
            ProgressView()
                .controlSize(.small)
        case .ok:
            Image(systemName: "checkmark.icloud")
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(.orange)
        case .disabled:
            Image(systemName: "icloud.slash")
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    // MARK: - 记录列表

    private var recordList: some View {
        Group {
            if store.isLoading && store.records.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.records.isEmpty {
                ContentUnavailableView(
                    "还没有打卡记录",
                    systemImage: "map",
                    description: Text("去「打卡」页完成第一次打卡吧")
                )
            } else {
                List {
                    ForEach(store.records.elements.groupedByDay()) { group in
                        Section(Self.dayFormatter.string(from: group.day)) {
                            ForEach(group.items) { record in
                                row(record)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        store.send(.editTapped(record.id))
                                    }
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    store.send(.deleteCheckIn(id: group.items[index].id))
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func row(_ record: CheckIn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.timeFormatter.string(from: record.date))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
            if let placeName = record.placeName {
                Text(placeName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !record.note.isEmpty {
                Text(record.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !record.photoIDs.isEmpty {
                HStack(spacing: 8) {
                    ForEach(record.photoIDs, id: \.self) { id in
                        PhotoStore.image(for: id).map {
                            Image(uiImage: $0)
                                .resizable()
                                .scaledToFill()
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            selectedPhoto = PhotoViewerItem(photoID: id)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Formatters

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    HistoryView(
        store: Store(initialState: HistoryFeature.State()) {
            HistoryFeature()
                .dependency(\.checkInClient, .previewValue)
        }
    )
}
