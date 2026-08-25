//
//  UninstallSizeSummaryTests.swift
//  CrosswireKitTests
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

import XCTest
@testable import CrosswireKit

/// `UninstallSizeSummary.summary` formats the Tier 2 uninstall confirmation's
/// "what's about to be deleted" line. `ByteCountFormatter` has no `locale`
/// override, so its exact digit/unit rendering can vary by system Region
/// settings -- expected size strings are composed from the same formatter
/// rather than hardcoded, keeping the tests focused on the "X across Y"
/// composition and singular/plural/fallback behavior this type owns.
final class UninstallSizeSummaryTests: XCTestCase {

    private func expectedSizeString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func testKnownSizeAcrossMultipleApps() {
        let result = UninstallSizeSummary.summary(totalBytes: 13_300_000_000, appCount: 3)
        XCTAssertEqual(result, "\(expectedSizeString(13_300_000_000)) across 3 apps")
    }

    func testKnownSizeSingularApp() {
        let result = UninstallSizeSummary.summary(totalBytes: 500_000_000, appCount: 1)
        XCTAssertEqual(result, "\(expectedSizeString(500_000_000)) across 1 app")
    }

    /// `du` failed for every bottle (nil) -- fall back to a name count, no size.
    func testUnknownSizeFallsBackToCountOnly() {
        let result = UninstallSizeSummary.summary(totalBytes: nil, appCount: 3)
        XCTAssertEqual(result, "3 apps")
    }

    /// `du` succeeded but reported zero bytes -- treat the same as unknown
    /// rather than claiming "0 bytes across 3 apps".
    func testZeroSizeFallsBackToCountOnly() {
        let result = UninstallSizeSummary.summary(totalBytes: 0, appCount: 2)
        XCTAssertEqual(result, "2 apps")
    }

    func testSingularAppWordWithUnknownSize() {
        let result = UninstallSizeSummary.summary(totalBytes: nil, appCount: 1)
        XCTAssertEqual(result, "1 app")
    }
}
