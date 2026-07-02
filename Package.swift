// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SystemInfo",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SystemInfo",
            targets: ["SystemInfo"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pkh0225/DragAbleView.git", from: "0.1.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SystemInfo",
            dependencies: [
                .product(name: "DragAbleView", package: "DragAbleView"),
            ]
        ),
        .testTarget(
            name: "SystemInfoTests",
            dependencies: ["SystemInfo"]
        ),
    ]
)
