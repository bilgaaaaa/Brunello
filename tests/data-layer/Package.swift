// swift-tools-version:6.1
import PackageDescription

// Linux check of the app's data layer: the real models and DiaryService, built against the Supabase SDK.
// The app sources are copied in by tests/run.sh; only main.swift and LoggerShim.swift live here.
let package = Package(
    name: "DataLayerCheck",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/supabase/supabase-swift", exact: "2.55.8")],
    targets: [
        .executableTarget(
            name: "DataLayerCheck",
            dependencies: [.product(name: "Supabase", package: "supabase-swift")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
