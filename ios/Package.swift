// swift-tools-version: 6.2

import Foundation
import PackageDescription

// The manifest is evaluated on the Linux host even when xtool cross-compiles,
// so `#if os(Linux)` cannot tell the two apart. `VKSIT_CORE_ONLY=1 swift test`
// builds just the SwiftUI-free core and its tests.
let coreOnly = ProcessInfo.processInfo.environment["VKSIT_CORE_ONLY"] != nil

var targets: [Target] = [
    .target(name: "VKSITCore"),
    .testTarget(name: "VKSITCoreTests", dependencies: ["VKSITCore"]),
]
if !coreOnly {
    targets.append(.target(
        name: "VKSIT",
        dependencies: ["VKSITCore"],
        resources: [.process("Resources")]
    ))
}

let package = Package(
    name: "VKSIT",
    defaultLocalization: "ru",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: coreOnly ? [] : [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(name: "VKSIT", targets: ["VKSIT"]),
    ],
    targets: targets
)
