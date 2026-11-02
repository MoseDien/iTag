import ProjectDescription
import ProjectDescriptionHelpers

let project = ProjectFactory.framework(
    name: "CloudSync",
    dependencies: [
        .project(target: "Domain", path: "../Domain"),
        .project(target: "CoreClients", path: "../CoreClients"),
        .external(name: "ComposableArchitecture"),
        .external(name: "DependenciesMacros"),
    ],
    testDependencies: [
        .project(target: "Domain", path: "../Domain"),
        .external(name: "ComposableArchitecture"),
    ]
)
