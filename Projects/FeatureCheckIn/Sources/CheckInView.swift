import ComposableArchitecture
import CoreClients
import Domain
import MapKit
import PhotosUI
import SwiftUI

/// 打卡页：全屏地图（拖动选点）+ 底部打卡卡片。
public struct CheckInView: View {
    private let store: StoreOf<CheckInFeature>

    /// 相机位置是临时 UI 状态，不入 Store。
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    /// 照片选择器的当前选择（onChange 后立即清空并异步落盘）。
    @State private var pickerSelection: [PhotosPickerItem] = []

    public init(store: StoreOf<CheckInFeature>) {
        self.store = store
    }

    public var body: some View {
        @Bindable var store = store

        return VStack(spacing: 0) {
            // 地图只占卡片上方区域：图钉即位于可视区域正中心，
            // 其对准的坐标与 onMapCameraChange 上报的地图中心一致，选点不会错位。
            ZStack {
                Map(position: $camera) {
                    UserAnnotation()
                }
                .mapStyle(.standard)
                .onMapCameraChange(frequency: .onEnd) { context in
                    store.send(
                        .mapCenterChanged(
                            Location(
                                latitude: context.region.center.latitude,
                                longitude: context.region.center.longitude,
                                timestamp: .now
                            )
                        )
                    )
                }

                // 中央固定图钉：拖动地图即选点
                Image(systemName: "mappin")
                    .font(.system(size: 38, weight: .semibold))
                    .symbolRenderingMode(.multicolor)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
                    .offset(y: -19)  // 针尖对准地图中心
                    .allowsHitTesting(false)
            }

            card
        }
        .task { store.send(.onTask) }
        .alert($store.scope(state: \.alert, action: \.alert))
    }

    // MARK: - Subviews

    private var card: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "location.circle.fill")
                    .foregroundStyle(.tint)
                placeTitle
                Spacer()
                // 回到当前位置
                Button {
                    camera = .userLocation(fallback: .automatic)
                } label: {
                    Image(systemName: "location.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("回到当前位置")
            }

            if let target = store.target {
                Text(
                    "\(target.latitude, format: .number.precision(.fractionLength(5))), \(target.longitude, format: .number.precision(.fractionLength(5)))"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if let last = store.lastCheckIn {
                Text("上次打卡：\(Self.timeFormatter.string(from: last.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 备注默认隐藏，用户点击后才显示输入框（已有内容时保持显示）
            if store.noteFieldVisible || !store.note.isEmpty {
                TextField("备注（可选）", text: $store.note)
                    .textFieldStyle(.roundedBorder)
            } else {
                Button {
                    store.send(.noteFieldTapped)
                } label: {
                    Label("添加备注", systemImage: "square.and.pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            photoRow

            Button {
                store.send(.checkInTapped)
            } label: {
                HStack(spacing: 8) {
                    if store.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(store.isWorking ? "处理中…" : "打卡")
                        .font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isWorking)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - 照片选择（最多 2 张）

    private var photoRow: some View {
        HStack(spacing: 10) {
            ForEach(store.pendingPhotoIDs, id: \.self) { id in
                photoThumb(id) {
                    store.send(.photoRemoved(id))
                }
            }
            if store.pendingPhotoIDs.count < CheckInPolicy.photoLimit {
                PhotosPicker(
                    selection: $pickerSelection,
                    maxSelectionCount: CheckInPolicy.photoLimit - store.pendingPhotoIDs.count,
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .frame(width: 64, height: 64)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("添加照片")
            }
        }
        .onChange(of: pickerSelection) { _, items in
            pickerSelection = []
            guard !items.isEmpty else { return }
            Task { @MainActor in
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        continue
                    }
                    // 落盘后登记 ID；超额部分由 reducer 兜底忽略
                    if let id = try? PhotoStore.save(data) {
                        store.send(.photoAdded(id))
                    }
                }
            }
        }
    }

    private func photoThumb(_ id: String, onRemove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = PhotoStore.image(for: id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                    .frame(width: 64, height: 64)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.multicolor)
                    .background(Circle().fill(.thinMaterial))
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel("移除照片")
        }
    }

    @ViewBuilder
    private var placeTitle: some View {
        if let placeName = store.placeName {
            Text(placeName)
                .font(.headline)
        } else if store.target != nil {
            Text("正在获取地名…")
                .font(.headline)
                .foregroundStyle(.secondary)
        } else if store.isWorking {
            Text("正在定位…")
                .font(.headline)
                .foregroundStyle(.secondary)
        } else {
            Text("拖动地图选择打卡位置")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    CheckInView(
        store: Store(initialState: CheckInFeature.State()) {
            CheckInFeature()
                .dependency(\.locationClient, .previewValue)
                .dependency(\.geocodingClient, .previewValue)
                .dependency(\.checkInClient, .previewValue)
        }
    )
}
