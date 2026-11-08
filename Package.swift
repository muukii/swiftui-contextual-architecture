// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ContextualArchitectureDemo",
  platforms: [.macOS(.v14)],
  targets: [
    .target(
      name: "ContextualArchitectureDemo",
      path: "ModelArchitecture",
      exclude: [
        "Assets.xcassets", "Developer", "ModelArchitectureApp.swift",
        "App/AppRootView.swift", "App/SessionRootView.swift",
        "Features/Main/MainViews.swift", "Features/Session/SessionViews.swift",
        "Features/Tabs/TabViews.swift",
      ]
    ),
    .testTarget(name: "ContextualArchitectureDemoTests", dependencies: ["ContextualArchitectureDemo"]),
  ]
)
