// swift-tools-version: 6.0
//
// Этот манифест нужен только для сборки и тестирования «движка решения» отдельно от
// приложения (в том числе на Linux и в CI): `swift test`.
// Само приложение открывается через AIHomework.xcodeproj.

import PackageDescription

let package = Package(
    name: "HomeworkEngine",
    targets: [
        .target(
            name: "HomeworkEngine",
            path: "AIHomework/Engine"
        ),
        .testTarget(
            name: "HomeworkEngineTests",
            dependencies: ["HomeworkEngine"],
            path: "EngineTests"
        ),
    ]
)
