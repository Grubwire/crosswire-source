//
//  ProgramRunReport.swift
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

/// Outcome of a single `Wine.runProgram` invocation. Produced after the
/// process exits and posted via `NotificationCenter` so the app can decide
/// whether to surface a failure-report dialog.
public struct ProgramRunReport: Sendable {
    /// The .exe / .bat file the user launched.
    public let executableURL: URL
    /// The bottle the program ran in.
    public let bottleURL: URL
    /// Display name of the bottle/app at launch time.
    public let bottleDisplayName: String
    /// Wine's exit status. Zero is success by convention; anything else is
    /// abnormal and is what the failure-report dialog watches for.
    public let exitCode: Int32
    /// Wall-clock time between exec and exit.
    public let duration: TimeInterval
    /// Path to the run log written by `Wine.runWineProcess`. Used to attach
    /// the tail of the log to a GitHub issue.
    public let logFileURL: URL?

    /// Crashes / failed exits. Currently a simple non-zero-exit check; the
    /// "exits within 10s with no window" heuristic is documented in the
    /// failure-reporting spec but not yet implemented (needs window count
    /// from wineserver). Non-zero exit covers the bulk of real crash cases.
    public var isAbnormal: Bool { exitCode != 0 }

    public init(
        executableURL: URL,
        bottleURL: URL,
        bottleDisplayName: String,
        exitCode: Int32,
        duration: TimeInterval,
        logFileURL: URL?
    ) {
        self.executableURL = executableURL
        self.bottleURL = bottleURL
        self.bottleDisplayName = bottleDisplayName
        self.exitCode = exitCode
        self.duration = duration
        self.logFileURL = logFileURL
    }
}

public extension Notification.Name {
    /// Posted after every `Wine.runProgram` invocation. The notification
    /// `object` is the `ProgramRunReport`. UI layers subscribe to decide
    /// whether to show a failure-report dialog.
    static let crosswireProgramDidExit = Notification.Name("crosswireProgramDidExit")
}
