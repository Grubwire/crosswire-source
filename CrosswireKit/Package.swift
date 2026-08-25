// swift-tools-version: 5.9
//
//  Package.swift
//  CrosswireKit
//
//  This file is part of Crosswire.
//
//  Crosswire is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Crosswire is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Crosswire.
//  If not, see https://www.gnu.org/licenses/.
//

import PackageDescription

let package = Package(
    name: "CrosswireKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CrosswireKit",
            targets: ["CrosswireKit"]
        )
    ],
    dependencies: [
      .package(url: "https://github.com/SwiftPackageIndex/SemanticVersion.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "CrosswireKit",
            dependencies: ["SemanticVersion"]
        ),
        .testTarget(
            name: "CrosswireKitTests",
            dependencies: ["CrosswireKit"],
            resources: [
                .copy("Fixtures/minimal-pe.exe"),
                .copy("Fixtures/icon-pe.exe"),
                .copy("Fixtures/icon-clrused-zero-pe.exe"),
                .copy("Fixtures/minimal-pe32.exe"),
                .copy("Fixtures/minimal-pe32plus.exe"),
                .copy("Fixtures/pe-no-optional-header.exe"),
                .copy("Fixtures/truncated-too-short.exe"),
                .copy("Fixtures/pe-offset-past-eof.exe"),
                .copy("Fixtures/pe-bad-signature.exe"),
                .copy("Fixtures/pe-unknown-magic.exe")
            ]
        )
    ],
    swiftLanguageVersions: [.version("6")]
)
