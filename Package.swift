// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FocusedDayPlanner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FocusedDayPlanner", targets: ["FocusedDayPlanner"])
    ],
    targets: [
        .executableTarget(
            name: "FocusedDayPlanner",
            path: "Sources/FocusedDayPlanner"
        ),
        .testTarget(
            name: "FocusedDayPlannerTests",
            dependencies: ["FocusedDayPlanner"],
            path: "Tests/FocusedDayPlannerTests"
        )
    ]
)
