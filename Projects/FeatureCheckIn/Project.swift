import ProjectDescription
import ProjectDescriptionHelpers

let project = ProjectFactory.framework(
    name: "FeatureCheckIn",
    dependencies: [
        .project(target: "Domain", path: "../Domain"),
        .project(target: "CoreClients", path: "../CoreClients"),
        .external(name: "ComposableArchitecture"),
    ],
    // 静态库结构下测试 bundle 独立持有全部符号（各归档仅合并一次），直链安全。
    testDependencies: [
        .project(target: "Domain", path: "../Domain"),
        .project(target: "CoreClients", path: "../CoreClients"),
        .external(name: "ComposableArchitecture"),
    ]
)
