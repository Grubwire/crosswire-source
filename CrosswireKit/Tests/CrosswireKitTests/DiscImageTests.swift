//
//  DiscImageTests.swift
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

/// Covers the disc-image install path: the installer-discovery heuristics
/// (pure directory inspection — autorun.inf, conventional names, sole-exe)
/// and a real hdiutil mount/unmount round trip against an ISO built at test
/// time with `hdiutil makehybrid` (no binary fixture committed).
final class DiscImageTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appending(path: "disc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func touch(_ name: String, _ contents: String = "x") throws {
        try contents.write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
    }

    // MARK: - findInstaller heuristics

    func testAutorunOpenWins() throws {
        try touch("autorun.inf", "[autorun]\nopen=GameSetup.exe\nicon=disc.ico\n")
        try touch("GameSetup.exe")
        try touch("setup.exe") // would match conventionally, autorun must win
        XCTAssertEqual(DiscImage.findInstaller(in: dir)?.lastPathComponent, "GameSetup.exe")
    }

    func testAutorunQuotedAndBackslashPath() throws {
        try FileManager.default.createDirectory(
            at: dir.appending(path: "bin"), withIntermediateDirectories: true)
        try "x".write(to: dir.appending(path: "bin/inst.exe"), atomically: true, encoding: .utf8)
        try touch("autorun.inf", "[autorun]\nOPEN=\"bin\\inst.exe\" /silent\n")
        XCTAssertEqual(DiscImage.findInstaller(in: dir)?.lastPathComponent, "inst.exe")
    }

    func testAutorunPointingAtMissingFileFallsBack() throws {
        try touch("autorun.inf", "[autorun]\nopen=GONE.exe\n")
        try touch("setup.exe")
        XCTAssertEqual(DiscImage.findInstaller(in: dir)?.lastPathComponent, "setup.exe")
    }

    func testConventionalNameCaseInsensitive() throws {
        try touch("SETUP.EXE")
        try touch("readme.txt")
        XCTAssertEqual(DiscImage.findInstaller(in: dir)?.lastPathComponent, "SETUP.EXE")
    }

    func testSoleExeWins() throws {
        try touch("AOESETUP.EXE")
        try touch("manual.pdf")
        XCTAssertEqual(DiscImage.findInstaller(in: dir)?.lastPathComponent, "AOESETUP.EXE")
    }

    func testAmbiguousExesReturnNil() throws {
        try touch("a.exe")
        try touch("b.exe")
        XCTAssertNil(DiscImage.findInstaller(in: dir))
    }

    func testEmptyVolumeReturnsNil() {
        XCTAssertNil(DiscImage.findInstaller(in: dir))
    }

    // MARK: - mount / unmount round trip

    func testMountFindUnmountRoundTrip() throws {
        // Build a real ISO at test time.
        try touch("setup.exe", "MZ-ish")
        let iso = FileManager.default.temporaryDirectory
            .appending(path: "disc-\(UUID().uuidString).iso")
        defer { try? FileManager.default.removeItem(at: iso) }
        let make = Process()
        make.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        make.arguments = [
            "makehybrid", "-iso", "-joliet",
            "-o", iso.path(percentEncoded: false), dir.path(percentEncoded: false)
        ]
        make.standardOutput = Pipe(); make.standardError = Pipe()
        try make.run(); make.waitUntilExit()
        guard make.terminationStatus == 0 else {
            throw XCTSkip("hdiutil makehybrid unavailable in this environment")
        }

        let volume = try DiscImage.mount(iso)
        defer { DiscImage.unmount(volume) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: volume.path(percentEncoded: false)))
        XCTAssertEqual(DiscImage.findInstaller(in: volume)?.lastPathComponent.lowercased(), "setup.exe")
    }

    func testMountOfGarbageThrows() throws {
        let bogus = dir.appending(path: "not-a-disc.iso")
        try Data(repeating: 0x42, count: 4096).write(to: bogus)
        XCTAssertThrowsError(try DiscImage.mount(bogus))
    }
}
