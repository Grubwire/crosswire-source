// swift-tools-version: 5.9
//
//  SentryBinary — local wrapper that vends sentry-cocoa as a PREBUILT XCFramework.
//
//  Why a local binaryTarget instead of the upstream SPM source package: resolving
//  the getsentry/sentry-cocoa *source* package makes Xcode's SPM git-fetch the repo,
//  which trips the macOS osxkeychain credential prompt and HANGS non-interactive
//  builds (it wedged CI). A binaryTarget downloads the prebuilt .xcframework zip over
//  HTTPS (no git) and SPM embeds it — no keychain prompt, no source compile.
//
//  Update: bump the version in the URL and replace `checksum` with the output of
//  `swift package compute-checksum Sentry-Dynamic.xcframework.zip`.
//
import PackageDescription

let package = Package(
    name: "SentryBinary",
    products: [
        .library(name: "Sentry", targets: ["Sentry"])
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/9.16.1/Sentry-Dynamic.xcframework.zip",
            checksum: "d5a23c79ab69703a3818f885989a60349a67aa2e096a914c352bb26f51b97936"
        )
    ]
)
