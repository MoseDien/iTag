import ProjectDescription

/// 共享的工程构造工厂：统一 destinations、部署版本、bundleId 与构建设置。
public enum ProjectFactory {
    public static let organizationName = "belldien"

    /// App 的 Bundle Identifier —— 项目唯一标识。
    /// 上架 App Store、配置推送/URL Scheme/关联域名等能力时均以此为准。
    /// 各模块与测试 target 的 bundle ID 也由它派生（如 com.belldien.itag.Domain）。
    public static let appBundleId = "com.belldien.itag"

    public static let destinations: Destinations = [.iPhone, .iPad]
    public static let deploymentTargets: DeploymentTargets = .iOS("17.0")

    static let baseSettings: Settings = .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            // Xcode 26 的 Debug Dylib 会把代码拆进 *.debug.dylib，
            // 与跨模块泛型 Reducer 组合的惰性 witness table 实例化冲突导致启动崩溃，
            // 故关闭（代价仅是增量构建稍慢）。
            "ENABLE_DEBUG_DYLIB": "NO",
        ]
    )

    /// 生成一个静态库模块工程（Domain / CoreClients / Feature*）。
    ///
    /// 用 `.staticLibrary` 而非 `.framework`：静态库归档之间不互相拷贝对象，
    /// 全部符号只在最终可执行文件（或测试 bundle）中链接一次，
    /// 避免共享依赖（TCA 等）产生多份副本导致的类型 metadata 分裂。
    public static func framework(
        name: String,
        dependencies: [TargetDependency] = [],
        includeTests: Bool = true,
        testDependencies: [TargetDependency] = []
    ) -> Project {
        var targets: [Target] = [
            .target(
                name: name,
                destinations: destinations,
                product: .staticLibrary,
                bundleId: "\(appBundleId).\(name)",
                deploymentTargets: deploymentTargets,
                sources: ["Sources/**"],
                dependencies: dependencies
            )
        ]
        if includeTests {
            targets.append(
                .target(
                    name: "\(name)Tests",
                    destinations: destinations,
                    product: .unitTests,
                    bundleId: "\(appBundleId).\(name)Tests",
                    deploymentTargets: deploymentTargets,
                    sources: ["Tests/**"],
                    dependencies: [.target(name: name)] + testDependencies
                )
            )
        }
        return Project(
            name: name,
            organizationName: organizationName,
            settings: baseSettings,
            targets: targets
        )
    }

    /// 生成 App 主工程。
    public static func app(
        name: String,
        dependencies: [TargetDependency]
    ) -> Project {
        Project(
            name: name,
            organizationName: organizationName,
            settings: .settings(
                base: baseSettings.base.merging([
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                ])
            ),
            targets: [
                .target(
                    name: name,
                    destinations: destinations,
                    product: .app,
                    bundleId: appBundleId,
                    deploymentTargets: deploymentTargets,
                    infoPlist: .extendingDefault(
                        with: [
                            "CFBundleDisplayName": "iTag",
                            "NSLocationWhenInUseUsageDescription": "iTag 需要访问你的位置，用于在当前位置打卡并记录。",
                            "UILaunchScreen": [:],
                        ]
                    ),
                    sources: ["Sources/**"],
                    resources: ["Resources/**"],
                    dependencies: dependencies
                ),
            ]
        )
    }
}
