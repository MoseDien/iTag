import ProjectDescription
import ProjectDescriptionHelpers

let project = ProjectFactory.framework(
    name: "CoreClients",
    dependencies: [
        .project(target: "Domain", path: "../Domain"),
        .external(name: "ComposableArchitecture"),
        .external(name: "DependenciesMacros"),
    ],
    includeTests: false
)
