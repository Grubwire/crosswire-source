//
//  EngineManifest.swift
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

import CryptoKit
import Foundation

// MARK: - Manifest model

/// Describes a signed engine release fetched from download.grubwire.io.
public struct EngineManifest: Codable {
    /// Manifest schema version. Currently 1.
    public let schemaVersion: Int
    /// Crosswire engine version string used for update comparison (e.g. "11.9").
    public let engineVersion: String
    /// Upstream Gcenx release tag (e.g. "11.9"). Never shown to users.
    public let upstreamTag: String
    /// Direct download URL for the .tar.xz archive.
    public let url: String
    /// Lowercase hex SHA-256 of the archive (verified before extraction).
    public let sha256: String
    /// Uncompressed engine size in bytes. Used for disk space pre-check before extraction.
    public let sizeBytes: Int64
    /// Minimum app version that can use this engine. App aborts setup if its version is older.
    public let minAppVersion: String
}

// MARK: - Errors

public enum EngineManifestError: Error, Equatable {
    case invalidSignature
    case sha256Mismatch
}

// MARK: - Manifest client

public enum EngineManifestClient {
    // Ed25519 public key (32 raw bytes, hex).
    // The corresponding private key (ENGINE_MANIFEST_SIGNING_KEY CI secret) signs
    // manifests at release time. Run `scripts/sign-manifest.sh` to produce a .sig file.
    // Key generated 2026-05-24. Replace both key and CI secret together if rotating.
    private static let publicKeyHex =
        "51c6ffe71ee5c92539aeb87c3b348e9b5914f7c03c3811da09be60b06cd822fc"

    // MARK: - Manifest URL (channel-aware; see UpdateChannel)
    // The manifest + signature URLs follow the user's update channel:
    // stable → engine/prod, beta → engine/beta. Default is stable.
    private static var engineManifestURL: URL { UpdateChannel.current.engineManifestURL }
    private static var engineManifestSigURL: URL { UpdateChannel.current.engineManifestSigURL }

    /// Fetches, signature-verifies, and decodes the engine manifest.
    public static func fetch() async throws -> EngineManifest {
        let (manifestData, _) = try await URLSession.shared.data(from: engineManifestURL)
        let (sigData, _) = try await URLSession.shared.data(from: engineManifestSigURL)

        guard verifySignature(manifestData: manifestData, signatureData: sigData) else {
            throw EngineManifestError.invalidSignature
        }

        return try JSONDecoder().decode(EngineManifest.self, from: manifestData)
    }

    /// Verifies a manifest's Ed25519 signature against the embedded public key.
    /// Extracted from `fetch()` so the security-critical verification can be
    /// unit-tested offline (no network). Returns false on any malformed input.
    static func verifySignature(manifestData: Data, signatureData: Data) -> Bool {
        guard let publicKey = try? Curve25519.Signing.PublicKey(
            rawRepresentation: Data(hexString: publicKeyHex)
        ) else { return false }
        return publicKey.isValidSignature(signatureData, for: manifestData)
    }

    /// Streams the archive at `url` and verifies its SHA-256 matches the manifest.
    /// Throws `EngineManifestError.sha256Mismatch` if verification fails.
    public static func verifyArchive(at url: URL, against manifest: EngineManifest) throws {
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let chunkSize = 1024 * 1024
        while true {
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard hex == manifest.sha256 else {
            throw EngineManifestError.sha256Mismatch
        }
    }
}

// MARK: - Hex decoding

private extension Data {
    init(hexString: String) {
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            if let byte = UInt8(hexString[index..<next], radix: 16) {
                data.append(byte)
            }
            index = next
        }
        self = data
    }
}
