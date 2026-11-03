import ComposableArchitecture
import CoreClients
import Domain
import PhotosUI
import SwiftUI

/// 编辑打卡记录：备注 + 照片管理。
/// 照片区采用 Form 标准形态：每张照片独立一行，避免 Section 内横向多按钮的交互冲突。
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
                    ForEach(store.photoIDs, id: \.self) { photoID in
                        photoRow(photoID)
                    }
                    if store.photoIDs.count < CheckInPolicy.photoLimit {
                        addPhotoRow
                    }
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
                // 处理完成后再复位选择，避免与 PhotosPicker 内部状态同步重入
                pickerSelection = []
            }
        }
    }

    // MARK: - 照片行

    private func photoRow(_ photoID: String) -> some View {
        HStack {
            if let image = PhotoStore.image(for: photoID) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 60, height: 60)
            }
            Spacer()
            Button {
                store.send(.removePhoto(photoID))
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除照片")
        }
    }

    private var addPhotoRow: some View {
        PhotosPicker(
            selection: $pickerSelection,
            maxSelectionCount: CheckInPolicy.photoLimit - store.photoIDs.count,
            matching: .images
        ) {
            Label("添加照片", systemImage: "photo.on.rectangle.angled")
        }
        .accessibilityLabel("添加照片")
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
