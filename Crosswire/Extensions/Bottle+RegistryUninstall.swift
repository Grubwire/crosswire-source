//
//  Bottle+RegistryUninstall.swift
//  Crosswire
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
import CrosswireKit

extension Bottle {
    /// Walks the bottle's `system.reg` and `user.reg` files for
    /// `...\Uninstall\...` entries and returns the `DisplayName` of the
    /// entry whose `InstallLocation` is an ancestor of `exeURL`. Returns
    /// nil if no plausible match exists.
    ///
    /// This is the Registry-uninstall fallback in the app-identity chain:
    /// Start Menu → (this) → exe filename.
    func registryDisplayName(for exeURL: URL) -> String? {
        let driveC = url.appending(path: "drive_c").path(percentEncoded: false)
        let entries = parseUninstallEntries()
        let exePath = exeURL.path(percentEncoded: false)

        // Sort by descending InstallLocation length so the most specific
        // ancestor wins (e.g. "C:\Program Files\Foo\Sub" over "C:\Program Files").
        let sorted = entries
            .filter { !$0.installLocation.isEmpty && !$0.displayName.isEmpty }
            .sorted { $0.installLocation.count > $1.installLocation.count }

        for entry in sorted {
            let hostPath = Bottle.winePathToHostPath(entry.installLocation, driveCHostPath: driveC)
            guard !hostPath.isEmpty else { continue }
            if exePath.hasPrefix(hostPath) {
                return entry.displayName
            }
        }
        return nil
    }

    struct UninstallEntry {
        let displayName: String
        let installLocation: String
    }

    /// Parses `system.reg` and `user.reg` in the bottle root and yields one
    /// `UninstallEntry` per registry key whose path contains `Uninstall\`.
    /// Reads `DisplayName` and `InstallLocation` values; everything else is
    /// ignored. Whitespace-tolerant, accepts both keystore files even if one
    /// is missing.
    func parseUninstallEntries() -> [UninstallEntry] {
        var entries: [UninstallEntry] = []
        for regFile in ["system.reg", "user.reg"] {
            let regURL = url.appending(path: regFile)
            guard let content = try? String(contentsOf: regURL, encoding: .utf8) else { continue }

            var inUninstallSection = false
            var displayName: String?
            var installLocation: String?

            func flush() {
                if inUninstallSection, let name = displayName {
                    entries.append(UninstallEntry(
                        displayName: name,
                        installLocation: installLocation ?? ""
                    ))
                }
                displayName = nil
                installLocation = nil
            }

            for rawLine in content.components(separatedBy: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("[") {
                    flush()
                    // Strip the timestamp suffix some Wine .reg files emit
                    let closeIdx = line.firstIndex(of: "]") ?? line.endIndex
                    let key = String(line[line.index(after: line.startIndex)..<closeIdx])
                    // Wine .reg sections use double-backslash to encode one
                    // backslash. Match the file form directly.
                    inUninstallSection = key.contains("Uninstall\\\\")
                } else if line.hasPrefix("\""), inUninstallSection {
                    if let parsed = Bottle.parseRegValueLine(line) {
                        switch parsed.name.lowercased() {
                        case "displayname":
                            displayName = parsed.value
                        case "installlocation":
                            installLocation = parsed.value
                        default:
                            break
                        }
                    }
                }
            }
            flush()
        }
        return entries
    }

    /// Splits a `"name"="value"` Wine-reg line into its components and
    /// unescapes C-style backslash sequences in the value (`\\` → `\`,
    /// `\"` → `"`). Returns nil for lines that don't fit the pattern
    /// (DWORDs, comments, blank lines).
    static func parseRegValueLine(_ line: String) -> (name: String, value: String)? {
        guard line.hasPrefix("\"") else { return nil }
        let afterOpenQuote = line.index(after: line.startIndex)
        guard let (name, afterName) = parseRegQuotedName(in: line, startingAt: afterOpenQuote) else {
            return nil
        }
        guard let valueStart = expectEqualsQuote(in: line, at: afterName) else { return nil }
        let value = parseRegQuotedValue(in: line, startingAt: valueStart)
        return (name, value)
    }

    /// Reads characters until the closing `"`, honoring backslash escapes
    /// literally (the name field doesn't decode C-style escapes). Returns
    /// the parsed name and the index after the closing quote, or nil if
    /// the quote was never found.
    private static func parseRegQuotedName(
        in line: String, startingAt start: String.Index
    ) -> (String, String.Index)? {
        var idx = start
        var name = ""
        while idx < line.endIndex {
            let char = line[idx]
            if char == "\\", line.index(after: idx) < line.endIndex {
                name.append(line[line.index(after: idx)])
                idx = line.index(idx, offsetBy: 2)
            } else if char == "\"" {
                return (name, line.index(after: idx))
            } else {
                name.append(char)
                idx = line.index(after: idx)
            }
        }
        return nil
    }

    /// After the name's closing quote, the line must read `="`. Returns
    /// the index of the first value character, or nil if the separator
    /// doesn't match.
    private static func expectEqualsQuote(in line: String, at start: String.Index) -> String.Index? {
        var idx = start
        guard idx < line.endIndex, line[idx] == "=" else { return nil }
        idx = line.index(after: idx)
        guard idx < line.endIndex, line[idx] == "\"" else { return nil }
        return line.index(after: idx)
    }

    /// Reads value characters until the closing `"`, decoding C-style
    /// backslash escapes (`\\`, `\"`, `\n`, `\t`, `\r`, `\0`). Unknown
    /// escapes are passed through as the literal following character, to
    /// match Wine's tolerant reader.
    private static func parseRegQuotedValue(
        in line: String, startingAt start: String.Index
    ) -> String {
        var idx = start
        var value = ""
        while idx < line.endIndex {
            let char = line[idx]
            if char == "\\", line.index(after: idx) < line.endIndex {
                let next = line[line.index(after: idx)]
                value.append(unescapeRegChar(next))
                idx = line.index(idx, offsetBy: 2)
            } else if char == "\"" {
                break
            } else {
                value.append(char)
                idx = line.index(after: idx)
            }
        }
        return value
    }

    private static func unescapeRegChar(_ char: Character) -> Character {
        switch char {
        case "\\": return "\\"
        case "\"": return "\""
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "0": return "\0"
        default: return char
        }
    }

    /// Converts a Windows-format install path (e.g. `C:\Program Files\App\`)
    /// to the corresponding host filesystem path under the given drive_c.
    /// Drops the drive-letter prefix and rewrites separators.
    static func winePathToHostPath(_ winePath: String, driveCHostPath: String) -> String {
        var path = winePath
        if path.count >= 2 {
            let second = path.index(path.startIndex, offsetBy: 1)
            if path[second] == ":" {
                path = String(path.suffix(from: path.index(after: second)))
            }
        }
        path = path.replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("/") { path.removeFirst() }
        var root = driveCHostPath
        if !root.hasSuffix("/") { root.append("/") }
        return root + path
    }
}
