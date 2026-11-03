// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Arca",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ArcaCore", targets: ["ArcaCore"]),
        .library(name: "ArcaCrypto", targets: ["ArcaCrypto"]),
        .library(name: "ArcaPersistence", targets: ["ArcaPersistence"]),
        .library(name: "ArcaArchive", targets: ["ArcaArchive"]),
        .library(name: "ArcaSync", targets: ["ArcaSync"]),
        .library(name: "ArcaBilling", targets: ["ArcaBilling"]),
        .library(name: "ArcaCloudAdapters", targets: ["ArcaCloudAdapters"]),
        .library(name: "ArcaUI", targets: ["ArcaUI"]),
        .executable(name: "ArcaApp", targets: ["ArcaApp"]),
        .executable(name: "ArcaVerificationRunner", targets: ["ArcaVerificationRunner"])
    ],
    targets: [
        .target(
            name: "ArcaCore",
            dependencies: []
        ),
        .target(
            name: "ArcaCrypto",
            dependencies: ["ArcaCore"]
        ),
        .target(
            name: "ArcaPersistence",
            dependencies: ["ArcaCore", "ArcaCrypto"]
        ),
        .target(
            name: "ArcaArchive",
            dependencies: ["ArcaCore", "ArcaCrypto", "ArcaPersistence"]
        ),
        .target(
            name: "ArcaSync",
            dependencies: ["ArcaCore", "ArcaCrypto", "ArcaPersistence", "ArcaBilling"]
        ),
        .target(
            name: "ArcaBilling",
            dependencies: ["ArcaCore"]
        ),
        .target(
            name: "ArcaCloudAdapters",
            dependencies: ["ArcaCore", "ArcaCrypto", "ArcaArchive"]
        ),
        .target(
            name: "ArcaUI",
            dependencies: [
                "ArcaCore",
                "ArcaCrypto",
                "ArcaPersistence",
                "ArcaArchive",
                "ArcaSync",
                "ArcaBilling",
                "ArcaCloudAdapters"
            ]
        ),
        .executableTarget(
            name: "ArcaApp",
            dependencies: ["ArcaUI"]
        ),
        .executableTarget(
            name: "ArcaVerificationRunner",
            dependencies: [
                "ArcaCore",
                "ArcaCrypto",
                "ArcaPersistence",
                "ArcaArchive",
                "ArcaSync",
                "ArcaBilling",
                "ArcaCloudAdapters",
                "ArcaUI"
            ]
        ),
        .testTarget(
            name: "ArcaTests",
            dependencies: [
                "ArcaCore",
                "ArcaCrypto",
                "ArcaPersistence",
                "ArcaArchive",
                "ArcaSync",
                "ArcaBilling",
                "ArcaCloudAdapters",
                "ArcaUI"
            ]
        )
    ]
)

