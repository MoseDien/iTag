import ComposableArchitecture
import CoreClients
import CoreLocation
import Domain
import MapKit
import SwiftUI

/// 历史地图：按 周/月/季/年 展示该时段内的全部打卡点。
/// 有照片的打卡点直接以照片缩略图作注点，点击可全屏查看原图。
public struct HistoryMapView: View {
    private let store: StoreOf<HistoryFeature>

    /// 相机位置与全屏照片均为临时 UI 状态，不入 Store。
    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedPhoto: PhotoViewerItem?

    public init(store: StoreOf<HistoryFeature>) {
        self.store = store
    }

    public var body: some View {
        @Bindable var store = store

        let filtered = store.filteredForMap

        VStack(spacing: 0) {
            Picker("时间范围", selection: $store.timeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.title)
                        .tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Map(position: $camera) {
                ForEach(filtered) { record in
                    if record.photoIDs.isEmpty {
                        Marker(
                            record.placeName ?? "打卡",
                            coordinate: CLLocationCoordinate2D(
                                latitude: record.latitude, longitude: record.longitude
                            )
                        )
                    } else {
                        // 有照片的打卡点：照片缩略图即注点（中心对准坐标）
                        Annotation(
                            record.placeName ?? "打卡",
                            coordinate: CLLocationCoordinate2D(
                                latitude: record.latitude, longitude: record.longitude
                            )
                        ) {
                            HStack(spacing: 2) {
                                ForEach(record.photoIDs, id: \.self) { photoID in
                                    mapThumb(photoID)
                                        .onTapGesture {
                                            selectedPhoto = PhotoViewerItem(photoID: photoID)
                                        }
                                }
                            }
                        }
                    }
                }
                UserAnnotation()
            }
            .mapStyle(.standard)
            .ignoresSafeArea(edges: .bottom)

            // 当前时段所有打卡照片；点击照片把相机飞到对应打卡点
            let anchors = photoAnchors(in: filtered)

            if !anchors.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(anchors, id: \.photoID) { anchor in
                            PhotoStore.image(for: anchor.photoID).map {
                                Image(uiImage: $0)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                camera = .region(
                                    MKCoordinateRegion(
                                        center: CLLocationCoordinate2D(
                                            latitude: anchor.latitude,
                                            longitude: anchor.longitude
                                        ),
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    )
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 76)
                .padding(.top, 6)
            }

            Text("该时段共 \(filtered.count) 次打卡")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
        .onAppear {
            fitCamera(to: filtered)
        }
        .onChange(of: filtered) { _, newValue in
            fitCamera(to: newValue)
        }
        .fullScreenCover(item: $selectedPhoto) { item in
            PhotoViewer(photoID: item.photoID)
        }
    }

    // MARK: - 照片注点与查看器

    /// 地图注点上的缩略图（带描边与投影，保证在地图上可辨识）。
    private func mapThumb(_ photoID: String) -> some View {
        PhotoStore.image(for: photoID).map {
            Image(uiImage: $0)
                .resizable()
                .scaledToFill()
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .accessibilityLabel("打卡照片")
    }

    // MARK: - Camera

    private struct PhotoAnchor {
        let photoID: String
        let latitude: Double
        let longitude: Double
    }

    /// 时段内全部照片及其所属打卡点坐标。
    private func photoAnchors(in records: [CheckIn]) -> [PhotoAnchor] {
        records.flatMap { record in
            record.photoIDs.map {
                PhotoAnchor(photoID: $0, latitude: record.latitude, longitude: record.longitude)
            }
        }
    }

    /// 用所有打卡点的包围盒自适应相机（带向外留白）。
    private func fitCamera(to records: [CheckIn]) {
        guard !records.isEmpty else { return }
        let rects = records.map { record in
            MKMapRect(
                origin: MKMapPoint(
                    CLLocationCoordinate2D(latitude: record.latitude, longitude: record.longitude)
                ),
                size: MKMapSize(width: 1000, height: 1000)
            )
        }
        let union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        camera = .rect(union.insetBy(dx: -2000, dy: -2000))
    }
}
