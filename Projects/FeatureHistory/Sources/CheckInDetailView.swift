import ComposableArchitecture
import CoreClients
import Domain
import PhotosUI
import SwiftUI

/// 编辑打卡记录：备注 + 照片管理。
public struct CheckInDetailView: View {
    private let store: StoreOf<CheckInDetailFeature>

    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var showNoteField = false

    public init(store: StoreOf<CheckInDetailFeature>) {
        self.store = store
    }

    public var body: some View {
        @Bindable var store = store

        return NavigationStack {
            Form {
                Section("位置") {
                    LabeledContent(
                        "时间",
                        value: Self.dateTimeFormatter.string(from: store.original.date)
                    )
                    LabeledContent("地点", value: store.original.placeName ?? "—")
                    LabeledContent(
                        "坐标",
                        value: String(
                            format: "%.5f, %.5f",
                            store.original.latitude, store.original.longitude
                        )
                    )
                }

                Section("备注") {
                    // 默认不显示编辑框，用户点击后才出现（原记录有备注则直接显示）
                    if !store.note.isEmpty || showNoteField {
                        TextEditor(text: $store.note)
                            .frame(minHeight: 88)
                    } else {
                        Button {
                            showNoteField = true
                        } label: {
                            Label("添加备注", systemImage: "square.and.pencil")
                        }
                    }
                }

                Section("照片（最多 \(CheckInPolicy.photoLimit) 张）") {
                    photoRow
                }
            }
            .navigationTitle("编辑打卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        store.send(.cancelTapped)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.send(.saveTapped)
                    }
                    .disabled(!store.isDirty)
                }
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
                    if let id = try? PhotoStore.save(data) {
                        store.send(.addPhoto(id))
                    }
                }
            }
        }
    }

    // MARK: - 照片

    private var photoRow: some View {
        HStack(spacing: 10) {
            ForEach(store.photoIDs, id: \.self) { id in
                photoThumb(id) {
                    store.send(.removePhoto(id))
                }
            }
            if store.photoIDs.count < CheckInPolicy.photoLimit {
                PhotosPicker(
                    selection: $pickerSelection,
                    maxSelectionCount: CheckInPolicy.photoLimit - store.photoIDs.count,
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .frame(width: 64, height: 64)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("添加照片")
            }
            if store.photoIDs.isEmpty {
                Text("没有照片，可添加")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    CheckInDetailView(
        store: Store(
            initialState: CheckInDetailFeature.State(
                checkIn: CheckIn(
                    latitude: 39.9,
                    longitude: 116.4,
                    date: .now,
                    placeName: "北京市朝阳区",
                    note: "示例备注"
                )
            )
        ) {
            CheckInDetailFeature()
        }
    )
}
