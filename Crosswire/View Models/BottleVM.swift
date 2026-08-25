//
//  BottleVM.swift
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
import SemanticVersion
import CrosswireKit
import os.log

@MainActor
final class BottleVM: ObservableObject {
    static let shared = BottleVM()

    var bottlesList = BottleData()
    @Published var bottles: [Bottle] = []

    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        return bottles.filter { $0.isAvailable == true }.count
    }

    func createNewBottle(bottleName: String, winVersion: WinVersion, bottleURL: URL) -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)
        // Diagnostic tag for the provisioning-stall investigation: correlates
        // every step of one createNewBottle run in Console/log files. Remove
        // once the stall (system.reg written but this Task never reaching
        // loadBottles(), leaving the bottle unpersisted and later orphaned)
        // is root-caused and fixed.
        let tag = newBottleDir.lastPathComponent

        Task {
            var bottleId: Bottle?
            do {
                // NOTE: these use .error, not .info, purely so the unified
                // logging system actually retains them for a post-hoc `log
                // show` — Info-level entries are not reliably persisted to
                // disk (confirmed empirically: only the .error timeout line
                // below survived a real stalled repro; the rest were gone).
                // Not a real error condition; remove once root-caused.
                Logger.wineKit.error("[provision \(tag, privacy: .public)] start: \(bottleName, privacy: .public)")
                try FileManager.default.createDirectory(atPath: newBottleDir.path(percentEncoded: false),
                                                        withIntermediateDirectories: true)
                let bottle = Bottle(bottleUrl: newBottleDir, inFlight: true)
                bottleId = bottle
                bottles.append(bottle)

                bottle.settings.windowsVersion = winVersion
                bottle.settings.name = bottleName

                Logger.wineKit.error("[provision \(tag, privacy: .public)] changeWinVersion: begin")
                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
                Logger.wineKit.error("[provision \(tag, privacy: .public)] changeWinVersion: returned")

                Logger.wineKit.error("[provision \(tag, privacy: .public)] wineVersion: begin")
                let wineVer = try await Wine.wineVersion()
                Logger.wineKit.error(
                    "[provision \(tag, privacy: .public)] wineVersion: returned (\(wineVer, privacy: .public))"
                )
                bottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)

                // Crash-storm prevention: stop Wine from spawning winedbg
                // --auto on in-process crashes. Important for any JVM/JIT
                // app — leaks stuck debugger procs otherwise.
                Logger.wineKit.error("[provision \(tag, privacy: .public)] disableCrashDebugger: begin")
                try? await Wine.disableCrashDebugger(bottle: bottle)
                Logger.wineKit.error("[provision \(tag, privacy: .public)] disableCrashDebugger: returned")

                Logger.wineKit.error("[provision \(tag, privacy: .public)] configureBrowserDedup: begin")
                try? await Wine.configureBrowserDedup(bottle: bottle)
                Logger.wineKit.error("[provision \(tag, privacy: .public)] configureBrowserDedup: returned")

                // Add record
                bottlesList.paths.append(newBottleDir)
                loadBottles()
                Logger.wineKit.error("[provision \(tag, privacy: .public)] done: persisted")
            } catch {
                Logger.wineKit.error(
                    "[provision \(tag, privacy: .public)] failed: \(error, privacy: .public)"
                )
                if let bottle = bottleId {
                    if let index = bottles.firstIndex(of: bottle) {
                        bottles.remove(at: index)
                    }
                }
            }
        }
        return newBottleDir
    }
}
