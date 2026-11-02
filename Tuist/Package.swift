// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    // 外部包保持默认的静态产品，配合各模块的 .staticLibrary：
    // 所有归档只在最终可执行文件 / 测试 bundle 中链接一次，全进程单份。
    let packageSettings = PackageSettings(
        productTypes: [:]
    )
#endif

let package = Package(
    name: "iTagPackages",
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.25.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.8.0"),
    ]
)
