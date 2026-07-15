//
//  RosettaCheck.swift
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

public enum RosettaCheck {
    public static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value != 0
    }

    public static var isInstalled: Bool {
        FileManager.default.fileExists(
            atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        )
    }

    /// Ensures Rosetta 2 is present. No-op on Intel or when already installed.
    /// Returns true if Rosetta is present (either pre-existing or newly installed).
    @discardableResult
    public static func ensureInstalled() async throws -> Bool {
        guard isAppleSilicon else { return true }
        guard !isInstalled else { return true }
        return try await install()
    }

    @discardableResult
    private static func install() async throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
        process.arguments = ["--install-rosetta", "--agree-to-license"]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
