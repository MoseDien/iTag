import ProjectDescription
import ProjectDescriptionHelpers

let project = ProjectFactory.framework(
    name: "FeatureHistory",
    dependencies: [
        .project(target: "Domain", path: "../Domain"),
        .project(target: "CoreClients", path: "../CoreClients"),
        .external(name: "ComposableArchitecture"),
    ],
    testDependencies: [
        .project(target: "Domain", path: "../Domain"),
        .project(target: "CoreClients", path: "../CoreClients"),
        .project(target: "CloudSync", path: "../CloudSync"),
        .external(name: "ComposableArchitecture"),
    ]
)
