// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_network_doctor",
    platforms: [.macOS("10.15")],
    products: [
        .library(name: "flutter-network-doctor", targets: ["flutter_network_doctor"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_network_doctor",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
