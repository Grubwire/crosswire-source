//
//  Bottle+Extensions.swift
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
import os.log

// swiftlint:disable file_length

extension Bottle {
    func openCDrive() {
        NSWorkspace.shared.open(url.appending(path: "drive_c"))
    }

    func openTerminal() {
        let crosswireCmdURL = Bundle.main.url(forResource: "CrosswireCmd", withExtension: nil)
        if let crosswireCmdURL = crosswireCmdURL {
            let crosswireCmd = crosswireCmdURL.path(percentEncoded: false)
            let cmd = "eval \\\"$(\\\"\(crosswireCmd)\\\" shellenv \\\"\(settings.name)\\\")\\\""

            let script = """
            tell application "Terminal"
            activate
            do script "\(cmd)"
            end tell
            """

            Task(priority: .userInitiated) {
                var error: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else { return }
                appleScript.executeAndReturnError(&error)

                if let error = error {
                    Logger.wineKit.error("Failed to run terminal script \(error)")
                    guard let description = error["NSAppleScriptErrorMessage"] as? String else { return }
                    self.showRunError(message: String(describing: description))
                }
            }
        }
    }

    @discardableResult
    func getStartMenuPrograms() -> [Program] {
        let globalStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "ProgramData")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        let userStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: "crossover")
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        var startMenuPrograms: [Program] = []
        var linkURLs: [URL] = []
        let globalEnumerator = FileManager.default.enumerator(at: globalStartMenu,
                                                              includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles])
        while let url = globalEnumerator?.nextObject() as? URL {
            if url.pathExtension == "lnk" {
                linkURLs.append(url)
            }
        }

        let userEnumerator = FileManager.default.enumerator(at: userStartMenu,
                                                            includingPropertiesForKeys: [.isRegularFileKey],
                                                            options: [.skipsHiddenFiles])
        while let url = userEnumerator?.nextObject() as? URL {
            if url.pathExtension == "lnk" {
                linkURLs.append(url)
            }
        }

        linkURLs.sort(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() })

        for link in linkURLs {
            do {
                if let program = ShellLinkHeader.getProgram(url: link,
                                                            handle: try FileHandle(forReadingFrom: link),
                                                            bottle: self) {
                    if !startMenuPrograms.contains(where: { $0.url == program.url }) {
                        startMenuPrograms.append(program)
                        try FileManager.default.removeItem(at: link)
                    }
                }
            } catch {
                print(error)
            }
        }

        return startMenuPrograms
    }

    func updateInstalledPrograms() {
        let driveC = url.appending(path: "drive_c")
        var programs: [Program] = []
        var foundURLS: Set<URL> = []

        for folderName in ["Program Files", "Program Files (x86)"] {
            let folderURL = driveC.appending(path: folderName)
            let enumerator = FileManager.default.enumerator(
                at: folderURL, includingPropertiesForKeys: [.isExecutableKey], options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard !url.hasDirectoryPath && url.pathExtension == "exe" else { continue }
                guard !settings.blocklist.contains(url) else { continue }
                // Wine's own helpers (iexplore.exe, wmplayer.exe, etc.) and
                // installer leftovers (uninstall.exe, *updater.exe) are not
                // user-facing apps; hide them from the row's program list.
                if Bottle.isStockWineApp(url) { continue }
                if Bottle.isNoiseEntryName(url.deletingPathExtension().lastPathComponent) { continue }
                foundURLS.insert(url)
                programs.append(Program(url: url, bottle: self))
            }
        }

        // Add missing programs from pins
        for pin in settings.pins {
            guard let url = pin.url else { continue }
            guard !foundURLS.contains(url) else { continue }
            programs.append(Program(url: url, bottle: self))
        }

        self.programs = programs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// A user-facing entry the installer registered with Windows. Display
    /// name comes from the Start Menu .lnk filename; URL is the .lnk's
    /// target.
    struct DetectedAppEntry {
        let displayName: String
        let url: URL
    }

    /// Non-destructive Start Menu scan. Returns entries with their display
    /// names, filtered to exclude obvious noise (uninstallers, updaters,
    /// help/website shortcuts, anything pointing into the Windows
    /// directory). Unlike `getStartMenuPrograms()` this does not delete the
    /// .lnk files, so it can run repeatedly.
    func scanStartMenuEntries() -> [DetectedAppEntry] {
        let startMenus = [
            url.appending(path: "drive_c/ProgramData/Microsoft/Windows/Start Menu"),
            url.appending(path: "drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu")
        ]

        var linkURLs: [URL] = []
        for root in startMenus {
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let candidate = enumerator?.nextObject() as? URL {
                if candidate.pathExtension.lowercased() == "lnk" {
                    linkURLs.append(candidate)
                }
            }
        }

        let windowsDir = url.appending(path: "drive_c/windows").path
        var seenTargets: Set<URL> = []
        var entries: [DetectedAppEntry] = []

        for link in linkURLs.sorted(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }) {
            let displayName = link.deletingPathExtension().lastPathComponent
            if Bottle.isNoiseEntryName(displayName) { continue }
            guard let handle = try? FileHandle(forReadingFrom: link) else { continue }
            defer { try? handle.close() }
            guard let program = ShellLinkHeader.getProgram(url: link, handle: handle, bottle: self) else { continue }
            let target = program.url
            if seenTargets.contains(target) { continue }
            if target.path.hasPrefix(windowsDir) { continue }
            if Bottle.isNoiseEntryName(target.deletingPathExtension().lastPathComponent) { continue }
            seenTargets.insert(target)
            entries.append(DetectedAppEntry(displayName: displayName, url: target))
        }

        return entries
    }

    private static func isNoiseEntryName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if Bottle.stockWineExeNames.contains(lower) { return true }
        let patterns = [
            "uninstall", "unins000", "unins001",
            "setup", "installer",
            "update", "updater", "gup",
            "readme", "read me", "help", "user manual", "manual",
            "website", "on the web", "homepage",
            "change log", "changelog", "release notes",
            "register", "activation",
            "crash", "report",
            "vc_redist", "vcredist", "dxsetup", "directx",
            "winetricks"
        ]
        return patterns.contains { lower.contains($0) }
    }

    /// Wine's built-in helper executables. We hide these whether they're
    /// found via Start Menu shortcuts, Program Files sweeps, or any other
    /// path. Matched by basename (lowercased, no extension).
    private static let stockWineExeNames: Set<String> = [
        "iexplore", "wmplayer", "wordpad", "winemine", "winhlp32",
        "control", "regedit", "explorer", "notepad", "winecfg",
        "winefile", "winemenubuilder", "winedbg", "wineboot",
        "winetricks", "winepath", "winecheck"
    ]

    /// Subpaths of every wineprefix that hold Wine's own bundled apps
    /// (Internet Explorer, Windows Media Player, etc). Anything under
    /// these is not user-installed content and must never be chosen as a
    /// bottle's primary launchable app, even when the real installer
    /// left nothing behind.
    private static let stockWineProgramSubpaths: [String] = [
        "/Program Files/Internet Explorer/",
        "/Program Files/Windows Media Player/",
        "/Program Files/Windows NT/",
        "/Program Files/Common Files/",
        "/Program Files (x86)/Internet Explorer/",
        "/Program Files (x86)/Windows Media Player/",
        "/Program Files (x86)/Windows NT/",
        "/Program Files (x86)/Common Files/"
    ]

    private static func isStockWineApp(_ url: URL) -> Bool {
        stockWineProgramSubpaths.contains { url.path.contains($0) }
    }

    /// Run after an install completes. Picks the app's display name and
    /// primary launcher from Start Menu entries (or falls back to a
    /// filtered Program Files sweep when the installer left no shortcuts).
    /// Persists both on the bottle settings.
    func finalizeAppIdentity() {
        let startMenu = scanStartMenuEntries()
        if !startMenu.isEmpty {
            settings.userVisibleProgramURLs = startMenu.map(\.url)
            if settings.primaryProgramURL == nil
                || !startMenu.contains(where: { $0.url == settings.primaryProgramURL }) {
                settings.primaryProgramURL = startMenu[0].url
            }
            // Name preference: VERSIONINFO -> registry uninstall name -> Start
            // Menu shortcut name. Bug #92 was that the Start Menu shortcut
            // name (often just the .lnk stem) always won and VERSIONINFO
            // never had a chance to produce the polished ProductName.
            settings.appDisplayName = identityName(for: settings.primaryProgramURL)
                ?? startMenu[0].displayName
            updateInstalledPrograms()
            return
        }

        // No Start Menu entries. Fall back to filtering Program Files,
        // skipping uninstallers, updaters, and Wine's own bundled apps
        // (iexplore.exe etc). Used for installers that never created
        // shortcuts and for portable .exes.
        updateInstalledPrograms()
        let visible = programs
            .map(\.url)
            .filter { url in
                if Bottle.isNoiseEntryName(url.deletingPathExtension().lastPathComponent) {
                    return false
                }
                return !Bottle.isStockWineApp(url)
            }

        guard !visible.isEmpty else {
            // Nothing the user can plausibly launch was found. Clear
            // any stale primary pointer so the row stays empty rather
            // than launching a Wine built-in by mistake.
            settings.userVisibleProgramURLs = []
            if let primary = settings.primaryProgramURL, Bottle.isStockWineApp(primary) {
                settings.primaryProgramURL = nil
            }
            return
        }

        settings.userVisibleProgramURLs = visible
        let primaryStillVisible = settings.primaryProgramURL.map { visible.contains($0) } ?? false
        if !primaryStillVisible {
            // Bug #95: blindly picking `visible[0]` chose deep runtime
            // binaries over the user-facing app .exe — a SWG install with
            // no Start Menu shortcut named the bottle "Java(TM) Platform SE
            // 8" because the bundled `lib/jre/bin/javaw.exe` outranked
            // `Program Files (x86)/SWG Legends/SWGLegendsLauncher.exe`.
            // Heuristic: rank shallower paths above deeper ones; among same
            // depth, prefer .exes outside known runtime directories.
            settings.primaryProgramURL = Self.pickUserFacingPrimary(from: visible)
        }

        // Same VERSIONINFO -> registry preference (no Start Menu fallback
        // available in this branch since scanStartMenuEntries was empty).
        if let name = identityName(for: settings.primaryProgramURL) {
            settings.appDisplayName = name
        }
    }

    /// Try to derive a polished display name for `primary` from, in order:
    ///   1. PE VS_VERSIONINFO (ProductName -> FileDescription -> InternalName)
    ///   2. Registry uninstall DisplayName
    /// Returns nil if neither produced a usable value, so the caller can
    /// fall back further (e.g. to a Start Menu shortcut name).
    private func identityName(for primary: URL?) -> String? {
        guard let primary else { return nil }
        if let peFile = try? PEFile(url: primary),
           let viName = peFile.displayName(), !viName.isEmpty {
            return viName
        }
        if let regName = registryDisplayName(for: primary) {
            return regName
        }
        return nil
    }

    /// Rank-by-heuristic primary picker for the no-Start-Menu branch. Returns
    /// the .exe most likely to be the user-facing app:
    ///
    ///   1. Drop URLs whose path traverses a known runtime/bundled directory
    ///      (`lib/`, `jre/`, `jdk/`, `runtime/`, `redist/`, `vendor/`,
    ///      `node_modules/`, or a nested `bin/` under another folder). These
    ///      are JRE/JDK/.NET/Node payloads, never the headline launcher.
    ///   2. Among the rest, prefer the shallowest path (fewest /-segments
    ///      inside drive_c). Top-level `Program Files (x86)/Foo/Foo.exe` is
    ///      depth 4 from drive_c; `Program Files (x86)/Foo/lib/jre/bin/javaw.exe`
    ///      is depth 7. Shallower wins.
    ///   3. Ties broken by case-insensitive alphabetical order on the basename
    ///      so the choice is deterministic across runs.
    ///   4. If filtering removes every candidate (an app whose primary .exe
    ///      *is* in a runtime-shaped path, unusual but possible), fall back
    ///      to the same ranking applied to the unfiltered list.
    static func pickUserFacingPrimary(from candidates: [URL]) -> URL {
        guard let head = candidates.first else {
            preconditionFailure("pickUserFacingPrimary called with empty candidates")
        }
        let runtimeMarkers: Set<String> = [
            "lib", "jre", "jdk", "runtime", "redist", "vendor", "node_modules"
        ]
        func isRuntimePath(_ url: URL) -> Bool {
            let lowered = url.pathComponents.map { $0.lowercased() }
            if lowered.contains(where: { runtimeMarkers.contains($0) }) { return true }
            // A `bin` dir that is nested under another non-drive-root folder
            // is almost always a runtime payload. drive_c top-level `bin` is
            // not a thing we ship; this only catches `app/server/bin/util.exe`
            // style nestings.
            if let binIdx = lowered.firstIndex(of: "bin"), binIdx >= 2 { return true }
            return false
        }
        func rank(_ url: URL) -> (Int, String) {
            return (url.pathComponents.count, url.lastPathComponent.lowercased())
        }
        let filtered = candidates.filter { !isRuntimePath($0) }
        let pool = filtered.isEmpty ? candidates : filtered
        return pool.min(by: { rank($0) < rank($1) }) ?? head
    }

    /// Programs the user should see in the main UI. Built from the
    /// detected user-visible URLs when available, otherwise the full
    /// program list (legacy bottles or fresh installs that have not yet
    /// completed detection).
    var userVisiblePrograms: [Program] {
        guard let visible = settings.userVisibleProgramURLs else { return programs }
        return programs.filter { visible.contains($0.url) }
    }

    /// Name shown in the main app list. Prefer the app's own identity over
    /// the installer's filename.
    var displayName: String {
        settings.appDisplayName ?? settings.name
    }

    @MainActor
    func move(destination: URL) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
                for index in 0..<bottle.settings.pins.count {
                    let pin = bottle.settings.pins[index]
                    if let url = pin.url {
                        bottle.settings.pins[index].url = url.updateParentBottle(old: url,
                                                                                 new: destination)
                    }
                }

                for index in 0..<bottle.settings.blocklist.count {
                    let blockedUrl = bottle.settings.blocklist[index]
                    bottle.settings.blocklist[index] = blockedUrl.updateParentBottle(old: url,
                                                                                     new: destination)
                }
            }
            try FileManager.default.moveItem(at: url, to: destination)
            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths[path] = destination
            }
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to move bottle")
        }
    }

    func exportAsArchive(destination: URL) {
        do {
            try Tar.tar(folder: url, toURL: destination)
        } catch {
            print("Failed to export bottle")
        }
    }

    @MainActor
    func remove(delete: Bool) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
            }

            if delete {
                try FileManager.default.removeItem(at: url)
            }

            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths.remove(at: path)
            }
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to remove bottle")
        }
    }

    @MainActor
    func rename(newName: String) {
        settings.name = newName
    }

    private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
