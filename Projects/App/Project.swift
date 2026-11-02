import ProjectDescription
import ProjectDescriptionHelpers

let project = ProjectFactory.app(
    name: "iTag",
    dependencies: [
        .project(target: "FeatureCheckIn", path: "../FeatureCheckIn"),
        .project(target: "FeatureHistory", path: "../FeatureHistory"),
        .project(target: "Domain", path: "../Domain"),
        .project(target: "CoreClients", path: "../CoreClients"),
        .external(name: "ComposableArchitecture"),
    ]
)
