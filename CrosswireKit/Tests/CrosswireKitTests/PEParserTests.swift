//
//  PEParserTests.swift
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

// MARK: - Architecture detection (PE32 vs PE32+)

/// Tests for PE32 (32-bit / x86) parsing using a synthetic minimal binary built by
/// the Fixtures generator. Covers the `baseOfData`-present / 4-byte `imageBase` path
/// in `OptionalHeader` that the real fixtures (both PE32+) never exercise.
final class PEParserPE32Tests: XCTestCase {

    private func fixture() throws -> PEFile {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "minimal-pe32", withExtension: "exe"),
            "minimal-pe32.exe fixture missing from the test bundle"
        )
        return try PEFile(url: url)
    }

    /// Parser must detect the PE32 magic (0x010B) and report 32-bit architecture.
    func testPE32DetectedAsX32() throws {
        XCTAssertEqual(try fixture().architecture, .x32)
    }

    /// `optionalHeader` must be populated (sizeOfOptionalHeader = 96 in the fixture).
    func testPE32HasOptionalHeader() throws {
        XCTAssertNotNil(try fixture().optionalHeader)
    }

    /// The optional header magic must be `.pe32`.
    func testPE32OptionalHeaderMagicIsPE32() throws {
        XCTAssertEqual(try fixture().optionalHeader?.magic, .pe32)
    }

    /// PE32 carries a `baseOfData` field; PE32+ does not. The parser sets it to
    /// `nil` for PE32+, so a non-nil value here confirms the correct branch was taken.
    func testPE32BaseOfDataIsPresent() throws {
        XCTAssertNotNil(try fixture().optionalHeader?.baseOfData)
    }

    /// PE32 `imageBase` is a 4-byte field promoted to UInt64. Our fixture stores
    /// 0x00400000 (standard 32-bit default load address).
    func testPE32ImageBaseMatchesFixture() throws {
        XCTAssertEqual(try fixture().optionalHeader?.imageBase, 0x00400000)
    }

    /// A synthetic PE32 with no sections should produce an empty section table.
    func testPE32NoSectionsYieldsEmptyTable() throws {
        XCTAssertTrue(try fixture().sections.isEmpty)
    }

    /// COFF machine field for i386 is 0x014C.
    func testPE32MachineIsI386() throws {
        XCTAssertEqual(try fixture().coffFileHeader.machine, 0x014C)
    }

    /// `importedDLLs` must return an empty array when there are no sections
    /// (and therefore no .idata to walk).
    func testPE32NoSectionsYieldsNoImports() throws {
        XCTAssertTrue(try fixture().importedDLLs.isEmpty)
    }

    /// `displayName()` must return nil when there is no .rsrc section.
    func testPE32NoRsrcDisplayNameIsNil() throws {
        XCTAssertNil(try fixture().displayName())
    }
}

// MARK: - PE32+ synthetic fixture

/// Tests for PE32+ (64-bit / x86_64) using a second synthetic minimal binary,
/// independent of `minimal-pe.exe` (which is a real compiler output). This
/// validates that the pure-field-layout path works on a hand-crafted file.
final class PEParserPE32PlusTests: XCTestCase {

    private func fixture() throws -> PEFile {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "minimal-pe32plus", withExtension: "exe"),
            "minimal-pe32plus.exe fixture missing from the test bundle"
        )
        return try PEFile(url: url)
    }

    /// Parser must detect the PE32+ magic (0x020B) and report 64-bit architecture.
    func testPE32PlusDetectedAsX64() throws {
        XCTAssertEqual(try fixture().architecture, .x64)
    }

    /// `optionalHeader` must be populated (sizeOfOptionalHeader = 112 in the fixture).
    func testPE32PlusHasOptionalHeader() throws {
        XCTAssertNotNil(try fixture().optionalHeader)
    }

    /// The optional header magic must be `.pe32Plus`.
    func testPE32PlusOptionalHeaderMagicIsPE32Plus() throws {
        XCTAssertEqual(try fixture().optionalHeader?.magic, .pe32Plus)
    }

    /// PE32+ has no `baseOfData` field; the parser must report nil for it.
    func testPE32PlusBaseOfDataIsAbsent() throws {
        XCTAssertNil(try fixture().optionalHeader?.baseOfData)
    }

    /// PE32+ `imageBase` is an 8-byte field. Our fixture stores 0x140000000 (the
    /// standard 64-bit default load address).
    func testPE32PlusImageBaseMatchesFixture() throws {
        XCTAssertEqual(try fixture().optionalHeader?.imageBase, 0x0000000140000000)
    }

    /// COFF machine field for x86_64 is 0x8664.
    func testPE32PlusMachineIsX8664() throws {
        XCTAssertEqual(try fixture().coffFileHeader.machine, 0x8664)
    }
}

// MARK: - Missing / nil optional header

/// When `sizeOfOptionalHeader` is zero the parser should succeed but leave
/// `optionalHeader` nil, which causes `architecture` to return `.unknown`.
final class PEParserNoOptionalHeaderTests: XCTestCase {

    private func fixture() throws -> PEFile {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "pe-no-optional-header", withExtension: "exe"),
            "pe-no-optional-header.exe fixture missing from the test bundle"
        )
        return try PEFile(url: url)
    }

    /// The parser must not throw even though there is no optional header.
    func testParseSucceedsWithNoOptionalHeader() throws {
        XCTAssertNoThrow(try fixture())
    }

    /// With no optional header, `optionalHeader` must be nil.
    func testOptionalHeaderIsNilWhenSizeIsZero() throws {
        XCTAssertNil(try fixture().optionalHeader)
    }

    /// Architecture must fall through to `.unknown` when there is no optional header.
    func testArchitectureIsUnknownWithNoOptionalHeader() throws {
        XCTAssertEqual(try fixture().architecture, .unknown)
    }

    /// `Architecture.unknown` maps to nil string representation.
    func testArchitectureUnknownToStringReturnsNil() {
        XCTAssertNil(Architecture.unknown.toString())
    }
}

// MARK: - Unknown optional header magic

/// A PE file whose optional header carries magic 0x0000 should parse without
/// error; `architecture` should be `.unknown` and `optionalHeader` should be
/// present but hold `.unknown` magic.
final class PEParserUnknownMagicTests: XCTestCase {

    private func fixture() throws -> PEFile {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "pe-unknown-magic", withExtension: "exe"),
            "pe-unknown-magic.exe fixture missing from the test bundle"
        )
        return try PEFile(url: url)
    }

    func testParseSucceedsWithUnknownMagic() throws {
        XCTAssertNoThrow(try fixture())
    }

    func testOptionalHeaderIsPresentWithUnknownMagic() throws {
        XCTAssertNotNil(try fixture().optionalHeader)
    }

    func testArchitectureIsUnknownForUnknownMagic() throws {
        XCTAssertEqual(try fixture().architecture, .unknown)
    }

    func testMagicFieldIsUnknownForZeroMagicValue() throws {
        XCTAssertEqual(try fixture().optionalHeader?.magic, .unknown)
    }
}

// MARK: - Malformed / non-PE files

/// All of these files are expected to throw `PEError.invalidPEFile` because they
/// lack a valid PE signature at the location the DOS stub points to.
final class PEParserMalformedFileTests: XCTestCase {

    private func url(forResource name: String) throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "exe"),
            "\(name).exe fixture missing from the test bundle"
        )
    }

    // MARK: Non-PE plain-text file (written by this test, not a fixture)

    /// A plain UTF-8 text file must throw because the bytes at 0x3C are random
    /// ASCII and will point to a garbage PE offset that either reads garbage or
    /// produces a wrong signature.
    func testPlainTextFileThrows() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "cw-pe-test-plain-\(UUID().uuidString).exe")
        try "Hello, not a PE file!".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertThrowsError(try PEFile(url: tmp))
    }

    /// A zero-byte file must throw because there is nothing to read at 0x3C.
    func testEmptyFileThrows() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "cw-pe-test-empty-\(UUID().uuidString).exe")
        try Data().write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertThrowsError(try PEFile(url: tmp))
    }

    /// File is only 4 bytes (MZ magic only) so reading UInt32 at offset 0x3C fails.
    func testTruncatedTooShortThrows() throws {
        XCTAssertThrowsError(try PEFile(url: url(forResource: "truncated-too-short")))
    }

    /// File has a valid DOS stub but the PE offset points past the end of the file,
    /// so reading the PE signature fails.
    func testPEOffsetPastEOFThrows() throws {
        XCTAssertThrowsError(try PEFile(url: url(forResource: "pe-offset-past-eof")))
    }

    /// File has a valid DOS stub with a valid PE offset, but the four bytes at
    /// that offset are not the PE signature (NE\0\0 instead of PE\0\0).
    func testBadPESignatureThrows() throws {
        XCTAssertThrowsError(try PEFile(url: url(forResource: "pe-bad-signature")))
    }

    /// The error thrown must be a `PEError`; its message content is an
    /// implementation detail but it must not be a different error type.
    func testThrowsIsPEError() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "cw-pe-test-err-type-\(UUID().uuidString).exe")
        try Data(repeating: 0, count: 64).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertThrowsError(try PEFile(url: tmp)) { error in
            XCTAssertTrue(error is PEError, "expected PEError, got \(type(of: error))")
        }
    }

    // MARK: Failable URL initializer

    /// `PEFile.init?(url:)` with nil input must return nil without throwing.
    func testFallibleInitWithNilURLReturnsNil() throws {
        let result = try PEFile(url: nil as URL?)
        XCTAssertNil(result)
    }
}

// MARK: - Architecture.toString()

/// `Architecture.toString()` has three cases; the existing tests only reach them
/// indirectly through fixture parsing. Pin all three here to guard against
/// accidental string changes.
final class PEArchitectureToStringTests: XCTestCase {

    func testX32ToStringIs32Bit() {
        XCTAssertEqual(Architecture.x32.toString(), "32-bit")
    }

    func testX64ToStringIs64Bit() {
        XCTAssertEqual(Architecture.x64.toString(), "64-bit")
    }

    func testUnknownToStringIsNil() {
        XCTAssertNil(Architecture.unknown.toString())
    }
}

// MARK: - Magic.description

/// `PEFile.Magic` is `CustomStringConvertible`; pin the description values so a
/// rename doesn't silently change diagnostic output.
final class PEMagicDescriptionTests: XCTestCase {

    func testPE32DescriptionIsPE32() {
        XCTAssertEqual(PEFile.Magic.pe32.description, "PE32")
    }

    func testPE32PlusDescriptionIsPE32Plus() {
        XCTAssertEqual(PEFile.Magic.pe32Plus.description, "PE32+")
    }

    func testUnknownMagicDescriptionIsUnknown() {
        XCTAssertEqual(PEFile.Magic.unknown.description, "unknown")
    }
}

// MARK: - Section parsing

/// Validates that the parser correctly reads section names and fields from the
/// real `minimal-pe.exe` fixture (9 sections, no .rsrc). Using the real binary
/// here gives confidence that section parsing works on actual linker output,
/// not just zeros.
final class PEParserSectionTests: XCTestCase {

    private func fixture() throws -> PEFile {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "minimal-pe", withExtension: "exe"))
        return try PEFile(url: url)
    }

    func testMinimalPEHasNineSections() throws {
        XCTAssertEqual(try fixture().sections.count, 9)
    }

    func testFirstSectionIsText() throws {
        XCTAssertEqual(try fixture().sections.first?.name, ".text")
    }

    func testSectionNamesDoNotContainNullBytes() throws {
        for section in try fixture().sections {
            XCTAssertFalse(section.name.contains("\0"),
                           "section name \(section.name.debugDescription) contains null bytes")
        }
    }

    func testSectionsHaveNonZeroVirtualAddresses() throws {
        // Every section in a loadable image has a nonzero virtual address.
        for section in try fixture().sections {
            XCTAssertGreaterThan(section.virtualAddress, 0,
                                 "section \(section.name) has zero virtualAddress")
        }
    }

    /// The .idata section (import table) should be present; its absence would
    /// mean either `importedDLLs` silently returns nothing or we have a parser bug.
    func testIdataSectionIsPresentForImportingPE() throws {
        let names = try fixture().sections.map(\.name)
        XCTAssertTrue(names.contains(".idata"),
                      "expected .idata section in \(names)")
    }
}

// MARK: - importedDLLs edge cases

/// Covers edge cases in `importedDLLs` that `PEFileTests` (which uses
/// `minimal-pe.exe`) cannot easily exercise in isolation.
final class PEImportedDLLsTests: XCTestCase {

    /// A PE file with no optional header has no data directories; `importedDLLs`
    /// must short-circuit and return an empty array (not crash).
    func testNoOptionalHeaderYieldsNoImports() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "pe-no-optional-header", withExtension: "exe")
        )
        let peFile = try PEFile(url: url)
        XCTAssertTrue(peFile.importedDLLs.isEmpty)
    }

    /// A PE with no sections has nothing to resolve RVAs against; even if an
    /// import table RVA were present, `resolveRVAtoFileOffset` would return nil
    /// for all sections. The synthetic no-opt fixture has zero sections, so this
    /// is the simplest proof of that path.
    func testNoSectionsYieldsNoImports() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "minimal-pe32", withExtension: "exe")
        )
        let peFile = try PEFile(url: url)
        XCTAssertTrue(peFile.importedDLLs.isEmpty)
    }
}
