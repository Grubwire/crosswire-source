//
//  Winetricks.swift
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
import AppKit
import CrosswireKit

enum WinetricksCategories: String {
    case apps
    case benchmarks
    case dlls
    case fonts
    case games
    case settings
}

struct WinetricksVerb: Identifiable {
    var id = UUID()

    var name: String
    var description: String
}

struct WinetricksCategory {
    var category: WinetricksCategories
    var verbs: [WinetricksVerb]
}

class Winetricks {
    /// The winetricks script, shipped in the app bundle's Resources next to
    /// cabextract. Repointed off the old `Libraries/winetricks` (which nothing
    /// ever provisioned) and off the hardcoded `/opt/homebrew/bin/winetricks`
    /// dev path, so dependency installs work for users without Homebrew.
    static let winetricksURL: URL? = Bundle.main.url(forResource: "winetricks", withExtension: nil)

    @MainActor static func runCommand(command: String, bottle: Bottle) async {
        guard let winetricksURL,
              let resourcesURL = Bundle.main.url(forResource: "cabextract", withExtension: nil)?
            .deletingLastPathComponent() else {
            // Both are bundled app resources, so a nil here is a build/packaging
            // fault, not a runtime condition — but log it so the manual verb
            // install doesn't fail silently with zero user-visible signal.
            print("Winetricks.runCommand: missing bundled winetricks/cabextract resource")
            return
        }
        // swiftlint:disable:next line_length
        let winetricksCmd = #"PATH=\"\#(CrosswireEngine.binFolder.path):\#(resourcesURL.path(percentEncoded: false)):$PATH\" WINE=Crosswire64 WINEPREFIX=\"\#(bottle.url.path)\" \"\#(winetricksURL.path(percentEncoded: false))\" \#(command)"#

        let script = """
        tell application "Terminal"
            activate
            do script "\(winetricksCmd)"
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error = error {
                print(error)
                if let description = error["NSAppleScriptErrorMessage"] as? String {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "alert.message")
                        alert.informativeText = String(localized: "alert.info")
                            + " \(command): "
                            + description
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: String(localized: "button.ok"))
                        alert.runModal()
                    }
                }
            }
        }
    }

    /// Streaming progress signal from `runVerbs(:bottle:onProgress:)`. Each
    /// value names the verb that's *currently* being installed, or `nil`
    /// when the runner finishes a verb and there isn't a new one queued yet.
    public typealias ProgressCallback = @MainActor (_ currentVerb: String?) -> Void

    /// Run a list of winetricks verbs in-process (no Terminal AppleScript
    /// bridge), streaming per-verb progress to a callback. Used by the
    /// runtime-detector flow to show an in-app progress sheet.
    ///
    /// Returns `true` on a clean exit, `false` on any non-zero exit.
    /// The full winetricks log is preserved at the returned path so the
    /// user can inspect what happened on failure.
    ///
    /// - Note: `runCommand(:bottle:)` still exists for the user-driven
    ///   manual Winetricks browser; that path keeps the Terminal bridge
    ///   so users can interact with click-through installer dialogs.
    @discardableResult
    @MainActor static func runVerbs(
        _ verbs: [String], bottle: Bottle,
        onProgress: @escaping ProgressCallback = { _ in }
    ) async -> (success: Bool, logURL: URL) {
        let logURL = FileManager.default.temporaryDirectory
            .appending(path: "crosswire-winetricks-\(UUID().uuidString).log")
        guard !verbs.isEmpty else { return (true, logURL) }

        let cabextractDir = Bundle.main.url(forResource: "cabextract", withExtension: nil)?
            .deletingLastPathComponent().path(percentEncoded: false) ?? ""

        let process = Process()
        // Bundled winetricks (Resources) is the shipping path — users have no
        // Homebrew. Fall back to a Homebrew install only as a dev convenience.
        process.executableURL = winetricksURL
            ?? URL(fileURLWithPath: "/opt/homebrew/bin/winetricks")
        process.arguments = ["--unattended"] + verbs
        process.environment = [
            "PATH": "\(CrosswireEngine.binFolder.path):\(cabextractDir):/opt/homebrew/bin:/usr/bin:/bin",
            "WINE": "Crosswire64",
            "WINEPREFIX": bottle.url.path(percentEncoded: false),
            "WINEDEBUG": "-all",
            "HOME": NSHomeDirectory()
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let logHandle: FileHandle?
        FileManager.default.createFile(atPath: logURL.path(percentEncoded: false), contents: nil)
        logHandle = try? FileHandle(forWritingTo: logURL)

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            logHandle?.write(data)
            if let text = String(data: data, encoding: .utf8) {
                for rawLine in text.split(separator: "\n") {
                    let line = String(rawLine)
                    // Look for the "Executing load_<verb>" pattern that
                    // winetricks emits when it starts processing each verb.
                    if let verb = extractActiveVerb(from: line, knownVerbs: verbs) {
                        Task { @MainActor in onProgress(verb) }
                    }
                }
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? logHandle?.close()
            return (false, logURL)
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        try? logHandle?.close()
        return (process.terminationStatus == 0, logURL)
    }

    /// Parse the active verb from a winetricks output line. Matches
    /// `Executing load_<verb>` (the function name winetricks calls per
    /// verb) — falls back to looking for any of the known verbs as a
    /// substring so we still get *something* for verbs that have
    /// non-`load_*`-style runners.
    private static func extractActiveVerb(from line: String, knownVerbs: [String]) -> String? {
        if let range = line.range(of: "Executing load_") {
            let tail = line[range.upperBound...]
            // verb name runs up to whitespace, paren, or end
            if let endIdx = tail.firstIndex(where: { $0.isWhitespace || $0 == "(" }) {
                return String(tail[..<endIdx])
            }
            return String(tail)
        }
        for verb in knownVerbs where line.contains(verb) {
            return verb
        }
        return nil
    }

    static func parseVerbs() async -> [WinetricksCategory] {
        // Grab the verbs file
        let verbsURL = CrosswireEngine.libraryFolder.appending(path: "verbs.txt")
        let verbs: String = await { () async -> String in
            do {
                let (data, _) = try await URLSession.shared.data(from: verbsURL)
                return String(data: data, encoding: .utf8) ?? String()
            } catch {
                return String()
            }
        }()

        // Read the file line by line
        let lines = verbs.components(separatedBy: "\n")
        var categories: [WinetricksCategory] = []
        var currentCategory: WinetricksCategory?

        for line in lines {
            // Categories are label as "===== <name> ====="
            if line.starts(with: "=====") {
                // If we have a current category, add it to the list
                if let currentCategory = currentCategory {
                    categories.append(currentCategory)
                }

                // Create a new category
                // Capitalize the first letter of the category name
                let categoryName = line.replacingOccurrences(of: "=====", with: "").trimmingCharacters(in: .whitespaces)
                if let cateogry = WinetricksCategories(rawValue: categoryName) {
                    currentCategory = WinetricksCategory(category: cateogry,
                                                         verbs: [])
                } else {
                    currentCategory = nil
                }
            } else {
                guard currentCategory != nil else {
                    continue
                }

                // If we have a current category, add the verb to it
                // Verbs eg. "3m_library               3M Cloud Library (3M Company, 2015) [downloadable]"
                let verbName = line.components(separatedBy: " ")[0]
                let verbDescription = line.replacingOccurrences(of: "\(verbName) ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentCategory?.verbs.append(WinetricksVerb(name: verbName, description: verbDescription))
            }
        }

        // Add the last category
        if let currentCategory = currentCategory {
            categories.append(currentCategory)
        }

        return categories
    }
}
