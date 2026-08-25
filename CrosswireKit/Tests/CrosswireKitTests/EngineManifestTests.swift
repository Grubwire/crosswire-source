//
//  EngineManifestTests.swift
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
import CryptoKit
@testable import CrosswireKit

// Test fixtures embed base64 blobs and force-unwrap them; both are fine in tests.
// swiftlint:disable force_unwrapping line_length

/// Guards the security-critical engine-download path: the Ed25519 manifest
/// signature check and the SHA-256 archive check. The signature fixture below is
/// the REAL prod manifest + `.sig` from download.grubwire.io, so these exercise
/// the actual embedded public key offline (no network, CI-safe).
final class EngineManifestTests: XCTestCase {

    // Real prod manifest bytes + their Ed25519 signature (base64). Captured from
    // https://download.grubwire.io/engine/prod/engine-manifest.json{,.sig}.
    private static let manifestB64 = """
    ewogICJzY2hlbWFWZXJzaW9uIjogMSwKICAiZW5naW5lVmVyc2lvbiI6ICIxMS45LjEiLAogICJ1cHN0cmVhbVRhZyI6ICIxMS45IiwKICAidXJsIjogImh0dHBzOi8vZG93bmxvYWQuZ3J1YndpcmUuaW8vZW5naW5lL3Byb2QvYXJjaGl2ZXMvQ3Jvc3N3aXJlLWVuZ2luZS0xMS45LnRhci54eiIsCiAgInNoYTI1NiI6ICI5MWMzYjRkMTMwYmNjZTA3Nzc0MzRkMmM1NDc2NzE5NGQzOWY0NDgxODk3MWQ0NjQ1YjkzYmI2NDIzZGExMWMwIiwKICAic2l6ZUJ5dGVzIjogNzY0MjUyMTYwLAogICJtaW5BcHBWZXJzaW9uIjogIjEuMC4wIgp9Cg==
    """
    private static let signatureB64 =
        "CFXLuv184PMQQ2vkalSiKEas0ezSYZkjpxczWeQJVTUjceYQ+PpjL1o0lkMFA+UQqwURmo3q6iq4QhYb7NlTBg=="

    private var manifestData: Data { Data(base64Encoded: Self.manifestB64.trimmingCharacters(in: .whitespacesAndNewlines))! }
    private var signatureData: Data { Data(base64Encoded: Self.signatureB64)! }

    // MARK: Ed25519 signature verification

    func testRealManifestVerifiesAgainstEmbeddedKey() {
        XCTAssertTrue(
            EngineManifestClient.verifySignature(manifestData: manifestData, signatureData: signatureData),
            "the real prod manifest + sig must verify against the embedded public key"
        )
    }

    func testTamperedManifestFailsVerification() {
        var tampered = manifestData
        tampered[tampered.count / 2] ^= 0xFF   // flip a byte
        XCTAssertFalse(
            EngineManifestClient.verifySignature(manifestData: tampered, signatureData: signatureData),
            "a modified manifest must NOT verify (this is the supply-chain guard)"
        )
    }

    func testWrongSignatureFailsVerification() {
        var badSig = signatureData
        badSig[0] ^= 0xFF
        XCTAssertFalse(
            EngineManifestClient.verifySignature(manifestData: manifestData, signatureData: badSig),
            "a corrupted signature must NOT verify"
        )
    }

    func testEmptyInputsDoNotVerify() {
        XCTAssertFalse(EngineManifestClient.verifySignature(manifestData: Data(), signatureData: Data()))
    }

    // MARK: Manifest decoding

    func testManifestDecodesToExpectedFields() throws {
        let manifest = try JSONDecoder().decode(EngineManifest.self, from: manifestData)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.engineVersion, "11.9.1")
        XCTAssertEqual(manifest.upstreamTag, "11.9")
        XCTAssertTrue(manifest.url.hasPrefix("https://download.grubwire.io/"))
        XCTAssertEqual(manifest.sha256.count, 64)
        XCTAssertGreaterThan(manifest.sizeBytes, 0)
    }

    // MARK: SHA-256 archive verification

    func testVerifyArchiveAcceptsMatchingHash() throws {
        let payload = Data("crosswire-engine-archive-bytes".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cw-archive-\(UUID().uuidString).bin")
        try payload.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let hex = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let manifest = try manifest(withSHA256: hex)
        XCTAssertNoThrow(try EngineManifestClient.verifyArchive(at: url, against: manifest))
    }

    func testVerifyArchiveRejectsWrongHash() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cw-archive-\(UUID().uuidString).bin")
        try Data("some other bytes".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let manifest = try manifest(withSHA256: String(repeating: "00", count: 32))
        XCTAssertThrowsError(try EngineManifestClient.verifyArchive(at: url, against: manifest)) { error in
            XCTAssertEqual(error as? EngineManifestError, .sha256Mismatch)
        }
    }

    private func manifest(withSHA256 sha: String) throws -> EngineManifest {
        let json = """
        {"schemaVersion":1,"engineVersion":"11.9.1","upstreamTag":"11.9",
         "url":"https://download.grubwire.io/x.tar.xz","sha256":"\(sha)",
         "sizeBytes":123,"minAppVersion":"1.0.0"}
        """
        return try JSONDecoder().decode(EngineManifest.self, from: Data(json.utf8))
    }
}
// swiftlint:enable force_unwrapping line_length
