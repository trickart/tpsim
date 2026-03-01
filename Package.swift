// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "tpsim",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
    ],
    dependencies: [
        .package(path: "../ThermalPrinterCommand"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .target(
            name: "Communication",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]
        ),
        .executableTarget(
            name: "tpsim",
            dependencies: [
                .product(name: "ThermalPrinterCommand", package: "ThermalPrinterCommand"),
                .product(name: "PrinterSimulator", package: "ThermalPrinterCommand"),
                "Communication",
            ]
        ),
    ]
)
