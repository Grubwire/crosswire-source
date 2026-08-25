//
//  DiscImage.swift
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

/// Mounting and inspecting disc images (.iso) so disc-era Windows installers
/// can run through the normal install flow. Mounting uses hdiutil (read-only,
/// not surfaced in Finder); installer discovery follows what a real disc would
/// do: honor autorun.inf first, then the conventional setup executable names.
public enum DiscImage {

    public enum DiscImageError: LocalizedError {
        case mountFailed(String)

        public var errorDescription: String? {
            switch self {
            case .mountFailed(let detail):
                return "The disc image could not be opened. \(detail)"
            }
        }
    }

    /// Mount a disc image read-only without showing it in Finder.
    /// Returns the mount point.
    public static func mount(_ imageURL: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "attach", imageURL.path(percentEncoded: false),
            "-readonly", "-nobrowse", "-plist"
        ]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DiscImageError.mountFailed("It may be damaged or not a disc image.")
        }
        // hdiutil -plist output: system-entities array; the mount point is the
        // entry that has a mount-point key.
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let entities = dict["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw DiscImageError.mountFailed("No mountable volume was found inside.")
        }
        return URL(fileURLWithPath: mountPoint, isDirectory: true)
    }

    /// Detach a previously mounted disc image. Best-effort; a volume that is
    /// still busy is left for the system to clean up.
    public static func unmount(_ mountPoint: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path(percentEncoded: false), "-quiet"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    /// Locate the installer a real disc would launch, in order of fidelity:
    /// 1. The executable named by `autorun.inf`'s `open=`/`shellexecute=` line.
    /// 2. A conventional installer name at the volume root (setup.exe,
    ///    install.exe, autorun.exe, …), case-insensitive.
    /// 3. The sole .exe at the volume root, if there is exactly one.
    /// Returns nil when nothing plausible is found (the caller surfaces that).
    public static func findInstaller(in volume: URL) -> URL? {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: volume, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return nil }

        // 1. autorun.inf
        if let autorun = entries.first(where: { $0.lastPathComponent.lowercased() == "autorun.inf" }),
           let target = autorunTarget(autorun, volume: volume),
           fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
            return target
        }

        let exes = entries.filter { $0.pathExtension.lowercased() == "exe" }

        // 2. Conventional names.
        let conventional = ["setup.exe", "install.exe", "autorun.exe", "start.exe", "setup32.exe"]
        for name in conventional {
            if let hit = exes.first(where: { $0.lastPathComponent.lowercased() == name }) {
                return hit
            }
        }

        // 3. A single unambiguous exe.
        if exes.count == 1 { return exes[0] }
        return nil
    }

    /// Parse autorun.inf's `open=` (or `shellexecute=`) value into a URL on the
    /// volume. Handles backslash paths and quoted values; ignores arguments
    /// after the executable. Windows .inf files are typically Latin-1/UTF-8.
    private static func autorunTarget(_ autorunURL: URL, volume: URL) -> URL? {
        guard let raw = (try? String(contentsOf: autorunURL, encoding: .utf8))
            ?? (try? String(contentsOf: autorunURL, encoding: .isoLatin1)) else { return nil }
        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            guard lower.hasPrefix("open=") || lower.hasPrefix("shellexecute=") else { continue }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            var value = String(trimmed[trimmed.index(after: equals)...])
                .trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") {
                value = String(value.dropFirst())
                if let endQuote = value.firstIndex(of: "\"") { value = String(value[..<endQuote]) }
            } else if let space = value.firstIndex(of: " ") {
                // Unquoted: arguments follow the first space.
                value = String(value[..<space])
            }
            guard !value.isEmpty else { continue }
            let relative = value.replacingOccurrences(of: "\\", with: "/")
            return volume.appending(path: relative)
        }
        return nil
    }
}
