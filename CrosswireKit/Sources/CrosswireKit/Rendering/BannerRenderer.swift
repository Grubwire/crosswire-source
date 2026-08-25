//
//  BannerRenderer.swift
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
import AppKit
import CryptoKit

/// Produces a wide banner image for a title from the icon embedded in its `.exe`.
///
/// This is the cached, app-facing wrapper around `BannerImagePipeline`. It
/// mirrors `AppIconExtractor`: an in-memory memo keyed off the request, results
/// computed off the main actor. It adds a disk cache, since a banner render
/// (palette sample + blur + composite) is materially more expensive than an
/// icon decode and the output is stable for a given exe and size.
///
/// The cache key is an exe fingerprint combined with the target pixel size, so
/// different display sizes never collide and a patched or replaced exe misses
/// the stale entry. The fingerprint is a SHA-256 of the exe's path, byte size,
/// and modification date rather than its full contents: launcher exes routinely
/// run to hundreds of megabytes, and content-hashing one on every request would
/// dominate the cost the cache exists to avoid. Size plus mtime changes exactly
/// when the icon could have changed (the exe was rewritten), which is when we
/// want to invalidate.
@MainActor
public enum BannerRenderer {

    private static var memo: [String: NSImage] = [:]

    /// Render (or fetch a cached) banner for the title whose primary exe is at
    /// `url`, at `size` in pixels.
    /// - Returns: nil if the exe has no renderable icon or rendering fails.
    public static func banner(forExe url: URL, size: CGSize) async -> NSImage? {
        let key: String
        if let fingerprint = fingerprint(for: url) {
            key = "\(fingerprint)-\(Int(size.width))x\(Int(size.height))"
        } else {
            key = "\(url.path)-\(Int(size.width))x\(Int(size.height))"
        }

        if let cached = memo[key] { return cached }

        if let onDisk = loadFromDisk(key: key) {
            memo[key] = onDisk
            return onDisk
        }

        // The render runs off the main actor, but NSImage is not Sendable and
        // cannot cross the actor boundary. Carry the result back as PNG Data
        // (which is Sendable) and rebuild the image here on the main actor.
        let pngData = await Task.detached(priority: .utility) { () -> Data? in
            guard let peFile = try? PEFile(url: url),
                  let icon = peFile.bestIcon(),
                  icon.isValid, icon.size.width > 0,
                  let banner = BannerImagePipeline.render(icon: icon, size: size) else { return nil }
            return BannerImagePipeline.pngData(from: banner)
        }.value

        guard let pngData, let rendered = NSImage(data: pngData) else { return nil }
        memo[key] = rendered
        saveToDisk(pngData, key: key)
        return rendered
    }

    /// Drop the in-memory memo. The disk cache is left intact.
    public static func clearMemory() {
        memo.removeAll()
    }

    // MARK: - Fingerprint

    private static func fingerprint(for url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values?.fileSize else { return nil }
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let material = "\(url.path)|\(size)|\(modified)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Disk cache

    private static func cacheDirectory() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches
            .appending(path: Bundle.CrosswireBundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "Banners", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir
    }

    private static func diskURL(key: String) -> URL? {
        cacheDirectory()?.appending(path: "\(key).png", directoryHint: .notDirectory)
    }

    private static func loadFromDisk(key: String) -> NSImage? {
        guard let url = diskURL(key: key),
              FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url),
              image.isValid else { return nil }
        return image
    }

    private static func saveToDisk(_ pngData: Data, key: String) {
        guard let url = diskURL(key: key) else { return }
        try? pngData.write(to: url, options: .atomic)
    }
}
