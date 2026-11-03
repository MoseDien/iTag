import CoreClients
import SwiftUI

/// fullScreenCover 的 item 需 Identifiable。
struct PhotoViewerItem: Identifiable {
    let photoID: String
    var id: String { photoID }
}

/// 全屏照片查看：黑底 aspectFit，点击任意处或 ✕ 关闭。
struct PhotoViewer: View {
    let photoID: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = PhotoStore.image(for: photoID) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(20)
                }
                Spacer()
            }
        }
        .onTapGesture {
            dismiss()
        }
    }
}
