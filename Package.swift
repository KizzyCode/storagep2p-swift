// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "StorageP2P",
    products: [
        .library(
            name: "StorageP2P",
            targets: ["StorageP2P"]),
        .executable(
            name: "FuzzStorageP2P",
            targets: ["FuzzStorageP2P"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/KizzyCode/asn1der-swift",
            .branch("master"))
    ],
    targets: [
        .target(
            name: "StorageP2P",
            dependencies: ["Asn1Der"]),
        .target(
            name: "FuzzStorageP2P",
            dependencies: ["StorageP2P"]),
        .testTarget(
            name: "StorageP2PTests",
            dependencies: ["StorageP2P"])
    ]
)
