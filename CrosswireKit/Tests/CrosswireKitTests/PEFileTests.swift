//
//  PEFileTests.swift
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

/// Exercises the PE parser against a real (tiny) PE binary. The fixture
/// `Fixtures/minimal-pe.exe` is a 16 KB x86-64 console exe built once with
/// mingw (`x86_64-w64-mingw32-gcc -O2 -s` of a one-line `GetTickCount()` main),
/// so it imports KERNEL32 + the UCRT `api-ms-win-crt-*` stubs and carries no
/// icon resource — exactly the "needs no runtimes, no icon" shape the parser
/// and `RuntimeDetector` have to handle correctly.
final class PEFileTests: XCTestCase {

    private func fixture() throws -> PEFile {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "minimal-pe", withExtension: "exe"),
            "minimal-pe.exe fixture missing from the test bundle"
        )
        return try PEFile(url: url)
    }

    func testParsesArchitectureAsX64() throws {
        XCTAssertEqual(try fixture().architecture, .x64)
    }

    func testImportsKernel32() throws {
        let dlls = try fixture().importedDLLs
        XCTAssertTrue(dlls.contains("kernel32.dll"),
                      "expected kernel32.dll among imports, got \(dlls)")
    }

    /// `importedDLLs` must return lowercased names — `RuntimeDetector`'s rules
    /// compare against lowercase literals, so dropping the `.lowercased()` would
    /// silently break runtime detection for any PE that spells its imports in
    /// upper/mixed case (most do: `KERNEL32.dll`).
    func testImportNamesAreLowercased() throws {
        let dlls = try fixture().importedDLLs
        XCTAssertFalse(dlls.isEmpty)
        XCTAssertEqual(dlls, dlls.map { $0.lowercased() })
    }

    func testNoIconReturnsNil() throws {
        XCTAssertNil(try fixture().bestIcon())
    }

    /// Integration: a plain UCRT exe imports nothing in the curated catalogue,
    /// so the end-to-end `detect(at:)` path must offer no runtimes — the
    /// conservative guarantee proven against a real binary, not a synthetic set.
    func testDetectOnPlainExeOffersNoRuntimes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "minimal-pe", withExtension: "exe"))
        XCTAssertEqual(RuntimeDetector.detect(at: url), [])
    }

    func testNonPEFileThrows() throws {
        let bogus = FileManager.default.temporaryDirectory
            .appending(path: "not-a-pe-\(UUID().uuidString).txt")
        try "this is plainly not a portable executable".write(
            to: bogus, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: bogus) }
        XCTAssertThrowsError(try PEFile(url: bogus))
    }
}
