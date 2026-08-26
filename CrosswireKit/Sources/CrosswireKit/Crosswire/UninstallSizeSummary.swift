//
//  UninstallSizeSummary.swift
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

/// Human-readable "what's about to be deleted" summary for the uninstall
/// flow's Tier 2 confirmation (#110), e.g. "12.4 GB across 3 apps". Pure
/// formatting, no I/O, so it's testable independently of the `du` call
/// (`BottleDiskUsage`) that produces `totalBytes`.
public enum UninstallSizeSummary {
    public static func summary(totalBytes: Int64?, appCount: Int) -> String {
        let appWord = appCount == 1 ? "app" : "apps"
        guard let totalBytes, totalBytes > 0 else {
            return "\(appCount) \(appWord)"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let sizeString = formatter.string(fromByteCount: totalBytes)
        return "\(sizeString) across \(appCount) \(appWord)"
    }
}
