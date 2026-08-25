//
//  BottleData.swift
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

import Foundation
import SemanticVersion

public struct BottleData: Codable {
    public static let containerDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library")
        .appending(path: "Containers")
        .appending(path: Bundle.CrosswireBundleIdentifier)

    public static let bottleEntriesDir = containerDir
        .appending(path: "BottleVM")
        .appendingPathExtension("plist")

    public static let defaultBottleDir = containerDir
        .appending(path: "Bottles")

    static let currentVersion = SemanticVersion(1, 0, 0)

    private var fileVersion: SemanticVersion
    public var paths: [URL] = [] {
        didSet {
            persist(newPaths: paths, oldPaths: oldValue)
        }
    }

    public init() {
        fileVersion = Self.currentVersion

        if !decode() {
            encode(paths: paths)
        }
    }

    @MainActor public mutating func loadBottles() -> [Bottle] {
        var bottles: [Bottle] = []

        for path in paths {
            let bottleMetadata = path
                .appending(path: "Metadata")
                .appendingPathExtension("plist")
                .path(percentEncoded: false)

            if FileManager.default.fileExists(atPath: bottleMetadata) {
                bottles.append(Bottle(bottleUrl: path, isAvailable: true))
            } else {
                bottles.append(Bottle(bottleUrl: path))
            }
        }

        return bottles
    }

    @discardableResult
    private mutating func decode() -> Bool {
        let decoder = PropertyListDecoder()
        do {
            let data = try Data(contentsOf: Self.bottleEntriesDir)
            self = try decoder.decode(BottleData.self, from: data)
            if self.fileVersion != Self.currentVersion {
                print("Invalid file version \(self.fileVersion)")
                return false
            }
            return true
        } catch {
            return false
        }
    }

    /// Reconciles this mutation against whatever is currently on disk before
    /// persisting, rather than trusting this instance's in-memory `paths` as
    /// authoritative. `didSet` fires with the full resulting array, and a
    /// plain re-encode of that array would silently drop any entry disk has
    /// but this instance's memory doesn't -- e.g. a second Crosswire process
    /// wrote a path after this instance last loaded, or this instance was
    /// initialized from a stale read. Diffing `oldPaths` against `newPaths`
    /// recovers what this mutation actually intended (add this one path, or
    /// remove that one path) and replays only that delta against a fresh
    /// read of disk, so an out-of-sync in-memory list can no longer clobber
    /// entries neither side asked to touch.
    private func persist(newPaths: [URL], oldPaths: [URL]) {
        let added = newPaths.filter { !oldPaths.contains($0) }
        let removed = oldPaths.filter { !newPaths.contains($0) }

        var reconciled = Self.readPathsFromDisk() ?? oldPaths
        reconciled.removeAll { removed.contains($0) }
        for path in added where !reconciled.contains(path) {
            reconciled.append(path)
        }

        encode(paths: reconciled)
    }

    /// Reads just the paths currently on disk, independent of this
    /// instance's in-memory state. Decoding a fresh `BottleData` does not
    /// trigger `paths`' `didSet` (Swift's synthesized `init(from:)` sets
    /// stored properties directly, bypassing property observers, the same
    /// way `decode()` below already relies on for app-launch loads), so this
    /// is safe to call from within `persist` without recursing.
    private static func readPathsFromDisk() -> [URL]? {
        let decoder = PropertyListDecoder()
        guard let data = try? Data(contentsOf: bottleEntriesDir) else { return nil }
        guard let decoded = try? decoder.decode(BottleData.self, from: data) else { return nil }
        guard decoded.fileVersion == currentVersion else { return nil }
        return decoded.paths
    }

    @discardableResult
    private func encode(paths: [URL]) -> Bool {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        do {
            try FileManager.default.createDirectory(at: Self.containerDir, withIntermediateDirectories: true)
            let payload = Payload(fileVersion: fileVersion, paths: paths)
            let data = try encoder.encode(payload)
            try data.write(to: Self.bottleEntriesDir)
            return true
        } catch {
            return false
        }
    }

    /// Mirrors `BottleData`'s own two stored properties for encoding only.
    /// Encoding a `BottleData` value directly would require assigning to its
    /// `paths` property to set the reconciled array, which would re-trigger
    /// `didSet` -> `persist` recursively. This has the identical property
    /// names and types, so its synthesized Codable output is byte-identical
    /// to `BottleData`'s own, keeping the on-disk plist format unchanged.
    private struct Payload: Codable {
        var fileVersion: SemanticVersion
        var paths: [URL]
    }
}
