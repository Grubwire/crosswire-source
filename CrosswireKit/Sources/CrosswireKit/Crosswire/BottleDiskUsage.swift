//
//  BottleDiskUsage.swift
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

/// Best-effort on-disk size for a bottle directory. Used only by the
/// uninstall flow's "here's what you're about to delete" summary (#110) --
/// a one-time `du` per bottle at the moment a user has already asked to
/// uninstall, never a hot path.
public enum BottleDiskUsage {
    /// Runs `du -sk` against `url` and returns the total size in bytes, or
    /// nil if the command fails (missing directory, permission issue,
    /// `du` not found). Callers should treat nil as "size unknown" and
    /// degrade gracefully, not surface it as an error.
    public static func approximateSize(of url: URL) -> Int64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        // `du -sk` output is "<kilobytes><tab><path>".
        let firstField = output
            .split(whereSeparator: { $0 == "\t" || $0 == " " })
            .first
            .map(String.init) ?? ""
        guard let kilobytes = Int64(firstField) else { return nil }
        return kilobytes * 1024
    }
}
