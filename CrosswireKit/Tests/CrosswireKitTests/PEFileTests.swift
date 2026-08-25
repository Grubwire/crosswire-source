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

    /// `bestIcon()` must decode an embedded icon resource into an image — the
    /// path that drives real app icons in the library. Fixture `icon-pe.exe` is
    /// a mingw-built exe with a single 16x16 icon embedded via windres (the
    /// no-icon case is covered by `testNoIconReturnsNil`).
    func testBestIconDecodesEmbeddedIcon() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "icon-pe", withExtension: "exe"))
        let icon = try PEFile(url: url).bestIcon()
        let image = try XCTUnwrap(icon, "bestIcon should decode the embedded icon resource")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// `biClrUsed == 0` is BMP-spec shorthand for "the full palette implied
    /// by the bit depth is present" (2^biBitCount entries), not "no palette".
    /// Fixture `icon-clrused-zero-pe.exe` embeds a real 16x16, 8bpp indexed
    /// icon, built with mingw + windres from a hand-crafted `icon.ico` whose
    /// BITMAPINFOHEADER sets `biClrUsed = 0` while a real 256-entry color
    /// table is physically present, mirroring the common (and spec-legal)
    /// way real encoders write this header. Before the `effectiveClrUsed`
    /// fix, reading `clrUsed` verbatim built an empty color table and every
    /// pixel decoded as fully-transparent black — this is the exact "blank
    /// icon" symptom hit on `SwgClient_r.exe`.
    func testBestIconDecodesClrUsedZeroIndexedIcon() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "icon-clrused-zero-pe", withExtension: "exe"))
        let icon = try PEFile(url: url).bestIcon()
        let image = try XCTUnwrap(icon, "bestIcon should decode the embedded icon resource")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)

        let cgImage = try XCTUnwrap(
            image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            "decoded icon should convert to a CGImage for pixel inspection"
        )
        let pixelData = try XCTUnwrap(cgImage.dataProvider?.data as Data?)
        XCTAssertFalse(pixelData.isEmpty)

        // ColorQuad is (red, green, blue, alpha); alpha is every 4th byte.
        // None of the fixture's first 16 palette entries are pure black, so
        // every decoded pixel must be opaque. An empty color table (the bug)
        // makes every pixel fully transparent (alpha 0) instead.
        let alphaBytes = stride(from: 3, to: pixelData.count, by: 4).map { pixelData[pixelData.startIndex + $0] }
        XCTAssertFalse(alphaBytes.isEmpty)
        XCTAssertTrue(alphaBytes.allSatisfy { $0 != 0 },
                      "expected every pixel opaque (clrUsed=0 palette applied), found a transparent pixel")
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
