//
//  FileHandleExtractTests.swift
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

/// `FileHandle.extract<T>` backs every field read in the PE and LNK parsers, which
/// process untrusted, attacker-controllable files. It must never hand `loadUnaligned`
/// a buffer shorter than `T` requires -- doing so is an out-of-bounds heap read in
/// Release builds, since `loadUnaligned`'s bounds check is a `_debugPrecondition`
/// that compiles out under `-O`. A full-miss short read (offset entirely past EOF)
/// already returns nil safely; the gap is a *partial* short read, where some but
/// not all of the requested bytes exist.
final class FileHandleExtractTests: XCTestCase {

    private func tempFile(bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cw-extract-test-\(UUID().uuidString).bin")
        try Data(bytes).write(to: url)
        return url
    }

    /// The exact vulnerability: 2 bytes on disk, a 4-byte read requested. This must
    /// return nil, not hand a 2-byte buffer to `loadUnaligned(as: UInt32.self)`.
    func testExtractReturnsNilOnPartialShortRead() throws {
        let url = try tempFile(bytes: [0xAA, 0xBB])
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        XCTAssertNil(handle.extract(UInt32.self, offset: 0))
    }

    /// A read starting exactly one byte before EOF for a multi-byte type is the
    /// tightest partial-read case (1 of 4 bytes available).
    func testExtractReturnsNilWhenOneByteShort() throws {
        let url = try tempFile(bytes: [0x01, 0x02, 0x03])
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        XCTAssertNil(handle.extract(UInt32.self, offset: 0))
    }

    /// Sanity check: a fully-present field at a valid offset must still extract
    /// correctly. This guards against a fix that's simply too strict.
    func testExtractReturnsValueWhenFullyPresent() throws {
        let url = try tempFile(bytes: [0x78, 0x56, 0x34, 0x12])
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        XCTAssertEqual(handle.extract(UInt32.self, offset: 0), 0x12345678)
    }

    /// Existing full-miss behavior (offset entirely past EOF) must remain nil, not
    /// regress into throwing or crashing.
    func testExtractReturnsNilWhenOffsetPastEOF() throws {
        let url = try tempFile(bytes: [0x01, 0x02, 0x03, 0x04])
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        XCTAssertNil(handle.extract(UInt32.self, offset: 100))
    }
}
