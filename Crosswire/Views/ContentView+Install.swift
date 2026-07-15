//
//  ContentView+Install.swift
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

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CrosswireKit

// swiftlint:disable file_length
extension ContentView {
    /// Delay before the "Finish Setup" escape hatch appears on the installer
    /// overlay — real installers usually finish faster, so we don't offer the
    /// out prematurely during a quick install (which could finalize mid-run).
    static let installerFinishHintDelay: Duration = .seconds(20)
    /// Long backstop so a walked-away portable-app install eventually finalizes
    /// rather than hanging on "Running installer…" forever.
    static let installerBackstopTimeout: Duration = .seconds(600)

    /// Wait for the installer task to exit, OR for the user to tap "Finish
    /// Setup", OR a long backstop — whichever comes first. Returns true ONLY if
    /// the installer actually exited. On an early finish the launched process is
    /// left running (it's the user's app); the caller finalizes + adopts it.
    /// This is what keeps a portable GUI app (which never exits) from trapping
    /// the UI on "Running installer…". Everything runs on the main actor, so the
    /// `done` guard needs no extra synchronization.
    @MainActor
    func waitForInstallerOrFinish(_ task: Task<Error?, Never>) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            var done = false
            func finish(installerExited: Bool) {
                guard !done else { return }
                done = true
                finishInstallerWait = nil
                cont.resume(returning: installerExited)
            }
            // The installer exited on its own (normal installer path).
            Task { @MainActor in _ = await task.value; finish(installerExited: true) }
            // After a short delay, surface the "Finish Setup" escape hatch.
            Task { @MainActor in
                try? await Task.sleep(for: Self.installerFinishHintDelay)
                if !done { finishInstallerWait = { finish(installerExited: false) } }
            }
            // Hard backstop so it can never hang forever.
            Task { @MainActor in
                try? await Task.sleep(for: Self.installerBackstopTimeout)
                finish(installerExited: false)
            }
        }
    }

    /// Await the bottle's wineserver teardown, but never longer than `timeout`.
    /// `Wine.killBottleAndWait` runs `wineserver -k -w`, which a stuck/zombie
    /// wine client (one that survives the kill) can make wait forever — and an
    /// unbounded wait would freeze the post-install flow with no escape. This
    /// races the teardown against a backstop and returns on whichever lands
    /// first; on timeout the teardown task is left to finish on its own (a
    /// harmlessly-waiting wineserver) while the caller proceeds. Same
    /// main-actor `done`-guard pattern as `waitForInstallerOrFinish` — no extra
    /// synchronization needed.
    @MainActor
    func killBottleBounded(_ bottle: Bottle, timeout: Duration = .seconds(20)) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var done = false
            func finish() {
                guard !done else { return }
                done = true
                cont.resume()
            }
            Task { @MainActor in
                try? await Wine.killBottleAndWait(bottle: bottle)
                finish()
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                finish()
            }
        }
    }

    func installWindowsApp() {
        // Concurrent-install guard. provisionAndInstall is @MainActor and
        // its `await`s suspend the main actor. Two of these in flight at
        // the same time deadlocked the UI on 2026-05-28 when bug #94's
        // wineserver-await held the first install open and the second
        // install was started. provisioningMessage is set synchronously on
        // entry and cleared on exit, so it's a reliable in-flight signal.
        if provisioningMessage != nil {
            showInstallAlert(
                title: "Install already in progress",
                body: "Wait for the current install to finish before starting a new one. "
                    + "You can see its progress in the status row at the bottom of the window."
            )
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.exe,
            UTType(exportedAs: "com.microsoft.msi-installer"),
            UTType(exportedAs: "com.microsoft.bat")
        ]
        panel.begin { result in
            guard result == .OK, let pickedURL = panel.urls.first else { return }
            // Defense in depth: re-check at the actual Task entry in case
            // the user re-opened the panel via a different code path while
            // the previous panel was open.
            Task { @MainActor in
                if provisioningMessage != nil {
                    showInstallAlert(
                        title: "Install already in progress",
                        body: "Wait for the current install to finish."
                    )
                    return
                }
                await provisionAndInstall(pickedURL: pickedURL)
            }
        }
    }

    /// Handle files dropped onto the library — treat the first dropped Windows
    /// installer/executable (.exe / .msi / .bat) exactly like one picked via
    /// the "Install" button. Anything else is ignored.
    @MainActor
    func handleDrop(of urls: [URL]) -> Bool {
        let installable = urls.first {
            ["exe", "msi", "bat"].contains($0.pathExtension.lowercased())
        }
        guard let pickedURL = installable else { return false }
        if provisioningMessage != nil {
            showInstallAlert(
                title: "Install already in progress",
                body: "Wait for the current install to finish before starting a new one."
            )
            return false
        }
        Task { @MainActor in await provisionAndInstall(pickedURL: pickedURL) }
        return true
    }

    // swiftlint:disable function_body_length
    @MainActor
    func provisionAndInstall(pickedURL: URL) async {
        let bottleName = pickedURL.deletingPathExtension().lastPathComponent
        let defaultLocation = UserDefaults.standard.url(forKey: "defaultBottleLocation")
            ?? BottleData.defaultBottleDir

        provisioningMessage = "Setting up..."
        let newBottleURL = bottleVM.createNewBottle(
            bottleName: bottleName,
            winVersion: .win10,
            bottleURL: defaultLocation
        )

        let bottle = await waitForBottle(url: newBottleURL)
        guard let bottle else {
            provisioningMessage = nil
            showInstallAlert(
                title: "Could not set up \(bottleName)",
                body: "Crosswire was unable to prepare a new environment for this app. "
                    + "See the latest run log for details: ~/Library/Logs/app.Crosswire.Crosswire/."
            )
            return
        }

        // Apply a matching recipe (known-good prerequisites + overrides for this
        // specific title) before anything else — see CrosswireKit/Recipe.swift.
        // Generic PE-import runtime detection below still runs as a complement.
        await applyRecipeIfMatched(pickedURL, into: bottle)

        // Static-analyze the picked exe's PE imports BEFORE running it. If we
        // detect runtimes the bottle doesn't have (vcrun, dotnet, d3dx, etc.),
        // surface a confirmation sheet that installs them via winetricks
        // first. .msi / .bat get skipped because their PE imports don't
        // describe what the installer will run.
        let detected = pickedURL.pathExtension.lowercased() == "exe"
            ? RuntimeDetector.detect(at: pickedURL)
            : []
        if !detected.isEmpty {
            provisioningMessage = nil
            let installed = await presentRuntimesSheet(
                exeName: pickedURL.lastPathComponent, detected: detected, bottle: bottle
            )
            provisioningMessage = "Running \(installed.isEmpty ? "installer" : "installer (runtimes ready)")..."
        } else {
            provisioningMessage = "Running installer..."
        }
        // runInstaller uses direct `wine <path>` invocation (not `start /unix`)
        // so it returns as soon as the installer's own .exe exits, NOT when
        // wineserver releases (Bug #94). But a *portable* GUI app (e.g. putty.exe)
        // run this way never exits on its own, which would trap us on "Running
        // installer…" forever. So wait for the installer to exit OR for the user
        // to tap "Finish Setup" OR a long backstop — whichever first. On an early
        // finish we leave the process running (it's the user's app) and fall
        // through to finalize + adopt it.
        var installerError: Error?
        let installerRun = Task<Error?, Never> {
            do {
                try await Wine.runInstaller(at: pickedURL, bottle: bottle)
                return nil
            } catch {
                return error
            }
        }
        let installerExited = await waitForInstallerOrFinish(installerRun)
        if installerExited {
            installerError = await installerRun.value
            if let installerError { print("Failed to run installer: \(installerError)") }
        }
        bottle.finalizeAppIdentity()

        if let installerError {
            CrosswireTelemetry.capture(installerError, context: "install.runInstaller")
            provisioningMessage = nil
            showInstallAlert(
                title: "Installer could not start",
                body: "\(installerError.localizedDescription)\n\n"
                    + "The bottle was created but the installer never ran. "
                    + "See the latest log at ~/Library/Logs/app.Crosswire.Crosswire/."
            )
            return
        }

        // If the install scan found nothing AND the picked file was a
        // portable .exe (no .msi, no .bat), treat the .exe itself as the
        // app — copy it into the bottle so Crosswire's program scan picks
        // it up and the Run button works. Without this, self-contained
        // tools like the SWG Legends launcher (10MB Java launcher with
        // bundled JRE) trigger a "no apps detected" warning even though
        // the .exe IS the app the user wanted to run.
        if bottle.userVisiblePrograms.isEmpty,
           pickedURL.pathExtension.lowercased() == "exe",
           await adoptPortableExe(pickedURL, into: bottle) {
            provisioningMessage = nil
            return
        }

        // After a regular installer run, scan the detected programs for
        // self-contained Java launchers (e.g. JavaFX game launchers that
        // ship their own JRE next to the .exe). For each match with no
        // existing per-program plist, seed one with _JAVA_OPTIONS so the
        // first launch doesn't sliver-render under Prism d3d. Runs
        // before any auto-launch attempt. Orthogonal to RuntimeDetector,
        // which only sees Win32 PE imports.
        for program in bottle.userVisiblePrograms {
            await JavaAppDetector.applyDefaultsIfNeeded(forExeAt: program.url, in: bottle)
        }

        // Clean up anything the installer may have already spawned (notably
        // the "Run <app> after install" Finish-step launcher in Inno Setup
        // and friends). That launcher started BEFORE the auto-features
        // above were applied, so its JVM read empty env vars and the
        // dwrite override wasn't yet in user.reg — net result is a sliver-
        // render or post-Login crash on what looks to the user like the
        // first run of their freshly-installed app. Killing the bottle's
        // wineserver takes the half-configured launcher down so the auto-
        // launch below starts cleanly with all auto-features applied. Waiting
        // for teardown (vs the old fire-and-forget kill + 2s sleep) is what
        // stops the relaunch racing a half-dead wineserver — the cause of the
        // post-install "blank launcher window". The wait is BOUNDED: a stuck or
        // zombie wine client can make `wineserver -w` block forever, and an
        // unbounded wait here would freeze the install flow with no escape, so
        // we cap it and proceed (the relaunch starts a fresh wineserver anyway).
        await killBottleBounded(bottle)

        provisioningMessage = nil

        if bottle.userVisiblePrograms.isEmpty {
            showInstallAlert(
                title: "Installer finished but no apps were detected",
                body: "The installer ran, but Crosswire could not find anything to launch. "
                    + "Check the latest run log for details: ~/Library/Logs/app.Crosswire.Crosswire/. "
                    + "You can delete the app from its settings panel and try again."
            )
            return
        }

        // Auto-launch the freshly-installed app. The installer's wizard
        // promised "Run <app> after install" — we just killed THAT launcher
        // because it started before our auto-features applied. Auto-launch
        // here gives the user what they expected (their app opens), now with
        // the plist's _JAVA_OPTIONS + dwrite=builtin in effect from first
        // paint. The killBottleAndWait above already blocked until the old
        // wineserver exited, so this relaunch comes up against a clean prefix
        // (no sleep-race).
        runPrimary(for: bottle)
    }
    // swiftlint:enable function_body_length

    /// Apply a matching recipe's DLL overrides + winetricks prerequisites to a
    /// fresh bottle (reusing the existing runners), before the user's installer
    /// runs. No-op when no recipe matches the picked installer.
    @MainActor
    private func applyRecipeIfMatched(_ pickedURL: URL, into bottle: Bottle) async {
        guard let recipe = RecipeMatcher.match(installerURL: pickedURL) else { return }
        provisioningMessage = "Applying \(recipe.name) setup…"
        for (dll, value) in recipe.dllOverrides {
            try? await Wine.setDllOverrideIfAbsent(dll, value: value, bottle: bottle)
        }
        if !recipe.prerequisites.isEmpty {
            _ = await Winetricks.runVerbs(recipe.prerequisites, bottle: bottle)
        }
    }

    /// Present the runtimes-detected sheet and suspend until the user
    /// makes a decision. Returns the verbs that were actually installed
    /// (empty when the user skipped).
    @MainActor
    func presentRuntimesSheet(
        exeName: String, detected: [DetectedRuntime], bottle: Bottle
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            runtimesPrompt = RuntimesPrompt(
                exeName: exeName,
                detected: detected,
                bottle: bottle,
                continuation: continuation
            )
        }
    }

    /// Copy a portable .exe the user picked into the bottle's
    /// `Program Files (x86)/<stem>/` so subsequent program scans and the
    /// Run button can find it. Sets primaryProgramURL + userVisible to
    /// the in-bottle path. Returns true on success.
    private func adoptPortableExe(_ source: URL, into bottle: Bottle) async -> Bool {
        let stem = source.deletingPathExtension().lastPathComponent
        let targetDir = bottle.url
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: stem)
        let targetURL = targetDir.appending(path: source.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) {
                try FileManager.default.copyItem(at: source, to: targetURL)
            }
        } catch {
            print("Failed to adopt portable exe \(source.lastPathComponent): \(error)")
            return false
        }
        bottle.updateInstalledPrograms()
        bottle.settings.primaryProgramURL = targetURL
        bottle.settings.userVisibleProgramURLs = [targetURL]

        // Check the SOURCE dir tree for a bundled JRE — that's where the
        // lib/jre layout lives; we only copy the .exe into the bottle,
        // not the surrounding tree. The plist is written for the
        // in-bottle target path (same basename as source, so the helper
        // keys it correctly off lastPathComponent).
        await JavaAppDetector.applyDefaultsIfNeeded(forExeAt: source, in: bottle)
        return true
    }

    private func showInstallAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    func waitForBottle(url: URL) async -> Bottle? {
        // createNewBottle spawns an inner Task; poll the published list until
        // the bottle flips out of inFlight. ~30s ceiling.
        for _ in 0..<300 {
            if let bottle = bottleVM.bottles.first(where: { $0.url == url }), !bottle.inFlight {
                return bottle
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return bottleVM.bottles.first(where: { $0.url == url })
    }

    func runPrimary(for bottle: Bottle) {
        guard bottle.isAvailable else { return }
        bottle.updateInstalledPrograms()
        guard !bottle.programs.isEmpty else { return }
        if let program = primaryProgram(for: bottle) {
            run(program: program, bottle: bottle)
        } else {
            // No detection has run and no primary is set; open the entry's
            // detail view so the user can pick a primary launcher explicitly
            // (the picker lives under Advanced).
            withAnimation(CrosswireTheme.Motion.navigation) {
                route = .entryDetail(bottle.id)
            }
        }
    }

    /// The program a Launch should run: an explicit primary if set and still
    /// present, else the first user-visible program, else the sole installed
    /// program. `nil` means we can't pick one unambiguously (caller routes to
    /// the detail view so the user chooses). Assumes `programs` is already
    /// populated and non-empty.
    func primaryProgram(for bottle: Bottle) -> Program? {
        let programs = bottle.programs
        if let primaryURL = bottle.settings.primaryProgramURL,
           let primary = programs.first(where: { $0.url == primaryURL }) {
            return primary
        }
        if let firstVisible = bottle.userVisiblePrograms.first {
            return firstVisible
        }
        return programs.count == 1 ? programs.first : nil
    }

    /// Launch the primary program with full-lifetime output capture (direct
    /// `wine` invocation, not detached). Used to reproduce crashes: the app
    /// runs as a foreground child and its complete stdout/stderr stream to the
    /// per-run log; on exit we reveal that log plus any JVM crash dump the run
    /// produced. See `Wine.runProgram(captureDiagnostics:)`.
    @MainActor
    func runWithDiagnostics(for bottle: Bottle) {
        guard bottle.isAvailable else { return }
        bottle.updateInstalledPrograms()
        guard !bottle.programs.isEmpty, let program = primaryProgram(for: bottle) else {
            withAnimation(CrosswireTheme.Motion.navigation) { route = .entryDetail(bottle.id) }
            return
        }
        bottle.settings.lastLaunched = Date()
        let startedAt = Date()
        let exeName = program.url.lastPathComponent
        Task(priority: .userInitiated) {
            let report = try? await Wine.runProgram(
                at: program.url, bottle: bottle, captureDiagnostics: true
            )
            // The foreground wine returns early if the app re-execs a detached
            // child (e.g. a JVM launcher forking `javaw`). Wait until the
            // launched exe is gone from the process list before collecting
            // artifacts, so a crash that happens minutes after the foreground
            // process exited still gets caught (its hs_err lands on disk).
            await Self.waitForExit(ofExe: exeName)
            await MainActor.run {
                presentDiagnostics(report: report, bottle: bottle, since: startedAt)
            }
        }
    }

    /// Poll until no process mentions `exeName` in its argv, capped so a
    /// long-running app can't hang the diagnostics flow forever. A short
    /// initial delay lets a detached child appear before the first check.
    private static func waitForExit(ofExe exeName: String) async {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let deadline = Date().addingTimeInterval(10 * 60)
        while Date() < deadline {
            if !Wine.isProcessRunning(matching: exeName) { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    /// After a diagnostics launch exits, surface what was captured: the run log
    /// and any `hs_err_pid*.log` (JVM crash dump) written during the run.
    @MainActor
    private func presentDiagnostics(report: ProgramRunReport?, bottle: Bottle, since: Date) {
        let crashDump = recentCrashDump(in: bottle, since: since)
        let alert = NSAlert()
        alert.messageText = "Diagnostics captured"
        // Lead with whether a crash dump was found — that's the real evidence.
        // The run report's exit code reflects only the foreground process,
        // which is unreliable for apps that re-exec a detached child, so it's
        // not surfaced here.
        var info: String
        if crashDump != nil {
            info = "\(bottle.displayName) wrote a crash dump during this run — "
                + "that's the most useful evidence for a Report."
        } else {
            info = "\(bottle.displayName) exited without writing a crash dump."
        }
        if report?.logFileURL != nil {
            info += "\nThe run log captured the launch environment and any "
                + "early output."
        }
        alert.informativeText = info
        if report?.logFileURL != nil {
            alert.addButton(withTitle: "Reveal Log")
        }
        if crashDump != nil {
            alert.addButton(withTitle: "Reveal Crash Dump")
        }
        alert.addButton(withTitle: "Close")

        let response = alert.runModal()
        var revealed: [URL] = []
        var buttonIndex = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if let log = report?.logFileURL {
            if response.rawValue == buttonIndex { revealed = [log] }
            buttonIndex += 1
        }
        if let dump = crashDump, response.rawValue == buttonIndex {
            revealed = [dump]
        }
        if !revealed.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(revealed)
        }
    }

    /// Find an `hs_err_pid*.log` under the bottle's `drive_c` modified after
    /// `since` — the JVM's own crash dump, which is the real evidence for
    /// JavaFX/JVM crashes like #84/#93.
    private func recentCrashDump(in bottle: Bottle, since: Date) -> URL? {
        let driveC = bottle.url.appending(path: "drive_c")
        guard let enumerator = FileManager.default.enumerator(
            at: driveC,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            guard name.hasPrefix("hs_err_pid"), name.hasSuffix(".log") else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified >= since { return url }
        }
        return nil
    }

    func run(program: Program, bottle: Bottle) {
        bottle.settings.lastLaunched = Date()
        // Single-instance: unless this bottle opts into multiple instances, a
        // Launch on an app that's already running focuses the existing window
        // instead of spawning a duplicate. We only suppress the spawn when we
        // find a live, focusable window — otherwise we fall through and launch,
        // so the guard can never get stuck blocking legitimate launches.
        if !bottle.settings.allowMultipleInstances {
            let liveApps = Wine.runningProcessIDs(for: bottle)
                .compactMap { NSRunningApplication(processIdentifier: $0) }
                .filter { !$0.isTerminated }
            if let existing = liveApps.first(where: { $0.activationPolicy == .regular }) {
                existing.activate(options: [.activateAllWindows])
                return
            }
        }
        Task(priority: .userInitiated) {
            do {
                try await Wine.runProgram(at: program.url, bottle: bottle)
            } catch {
                print("Failed to run program: \(error)")
            }
        }
    }
}
