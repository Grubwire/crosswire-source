//
//  FileOpenView.swift
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
import CrosswireKit
import os.log

struct FileOpenView: View {
    var fileURL: URL
    var currentBottle: URL?
    var bottles: [Bottle]

    /// Sentinel selection meaning "provision a fresh, dedicated bottle for this
    /// exe" — the isolation-by-default choice (one bottle per app, #107). An
    /// externally-opened exe must never be routed into an unrelated app's
    /// bottle without an explicit user choice.
    private static let newBottleSentinel = URL(filePath: "crosswire-new-dedicated-bottle")

    @State private var selection: URL = FileOpenView.newBottleSentinel
    @State private var isProvisioning = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("run.bottle", selection: $selection) {
                    // Default: isolate this exe in its own bottle.
                    Text(String(format: String(localized: "run.newBottle"),
                                fileURL.deletingPathExtension().lastPathComponent))
                        .tag(FileOpenView.newBottleSentinel)
                    ForEach(bottles, id: \.self) {
                        Text($0.settings.name)
                            .tag($0.url)
                    }
                }
                .disabled(isProvisioning)
                if isProvisioning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("run.provisioning")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .formStyle(.grouped)
            .navigationTitle(String(format: String(localized: "run.title"), fileURL.lastPathComponent))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("button.run") {
                        run()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isProvisioning)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.small)
        // No onAppear default-to-existing-bottle and no single-bottle auto-run:
        // both routed external exes into an arbitrary existing bottle (#107).
        // The default is a fresh dedicated bottle; reusing an existing bottle
        // stays available as an explicit pick.
    }

    func run() {
        // One-bottle-per-app: the default selection provisions a fresh,
        // dedicated bottle for this exe (#107).
        if selection == FileOpenView.newBottleSentinel {
            provisionAndRun()
            return
        }
        if let bottle = bottles.first(where: { $0.url == selection }) {
            Task(priority: .userInitiated) {
                do {
                    if fileURL.pathExtension == "bat" {
                        try await Wine.runBatchFile(url: fileURL,
                                                    bottle: bottle)
                    } else {
                        try await Wine.runProgram(at: fileURL, bottle: bottle)
                    }
                } catch {
                    print(error)
                }
            }
            dismiss()
        }
    }

    /// Create a dedicated bottle named after the exe, wait for the wineprefix
    /// to finish initializing, then run the exe inside it.
    private func provisionAndRun() {
        isProvisioning = true
        // #120: log the exact fileURL Finder handed to Crosswire, before any
        // naming logic runs, so a future wrong-name repro shows whether it
        // was already wrong at this entry point.
        Logger.wineKit.error(
            "[install-entry] Open With picked: \(fileURL.path(percentEncoded: false), privacy: .public)"
        )
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let existingNames = Set(bottles.map { $0.settings.name })
        var name = stem
        var suffix = 2
        while existingNames.contains(name) {
            name = "\(stem) \(suffix)"
            suffix += 1
        }
        let defaultLocation = UserDefaults.standard.url(forKey: "defaultBottleLocation")
            ?? BottleData.defaultBottleDir
        let newBottleURL = BottleVM.shared.createNewBottle(
            bottleName: name,
            winVersion: .win10,
            bottleURL: defaultLocation
        )

        Task(priority: .userInitiated) {
            guard let bottle = await Self.pollForProvisionedBottle(newBottleURL: newBottleURL) else {
                isProvisioning = false
                showProvisionFailureAlert(bottleName: name)
                return
            }
            do {
                if fileURL.pathExtension == "bat" {
                    try await Wine.runBatchFile(url: fileURL, bottle: bottle)
                } else {
                    try await Wine.runProgram(at: fileURL, bottle: bottle)
                }
            } catch {
                print(error)
            }
            bottle.updateInstalledPrograms()
            dismiss()
        }
    }

    /// Poll `BottleVM.shared.bottles` until the freshly-created bottle at
    /// `newBottleURL` flips out of `inFlight`, or the ceiling below is hit.
    /// createNewBottle returns while the prefix is still initializing;
    /// running against an in-flight prefix fails silently. The ceiling
    /// catches a genuine hang instead of leaving the sheet spinning forever.
    ///
    /// Ceiling was 15s and was too tight: a real, successful provisioning
    /// run captured via the diagnostic logging below timed `changeWinVersion`
    /// (winecfg) alone at 17.7s, before the regedit step even started. That
    /// run had no competing load (no build, no backup, no heavy Spotlight
    /// indexing running) and winecfg on its own fanned out to over twenty
    /// short-lived wine child processes, each paying real macOS XPC/startup
    /// overhead (cfprefsd, distributed_notifications, fonts,
    /// launchservicesd). That looks like typical cost on this machine, not a
    /// resource-contention spike, so 15s was never a realistic ceiling.
    /// A timeout that fires too early is worse than one that waits a few
    /// extra seconds for a real success: it produces a spurious failure
    /// alert while the Task keeps running in the background, which is what
    /// drove the retry storms (vcredist_x64, vcredist_x64 2, vcredist_x64 3)
    /// this ceiling was found from. 45s gives roughly double the full
    /// observed successful chain (winecfg + wineVersion + regedit, ~22.3s)
    /// and well over double the slowest single step observed (17.7s),
    /// without letting a truly stuck bottle sit silent for a full minute.
    ///
    /// Diagnostic logging (tag correlates with BottleVM.createNewBottle's own
    /// logging) for the provisioning-stall investigation: shows exactly how
    /// far the poll got, and whether the bottle was still inFlight or missing
    /// entirely at timeout. Keep this in place until the new ceiling has been
    /// confirmed across a few real sessions, not just the one that found it,
    /// then downgrade or remove it so it does not linger as permanent noise.
    @MainActor
    private static func pollForProvisionedBottle(newBottleURL: URL) async -> Bottle? {
        let tag = newBottleURL.lastPathComponent
        let ceilingAttempts = 450 // 45s at the 100ms poll interval below
        // .error, not .info: Info-level entries are not reliably retained by
        // the unified logging system for a post-hoc `log show`. Remove once
        // root-caused.
        Logger.wineKit.error("[provision \(tag, privacy: .public)] poll: start (45s ceiling)")

        for attempt in 0..<ceilingAttempts {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == newBottleURL }),
               !bottle.inFlight {
                let elapsedMs = attempt * 100
                Logger.wineKit.error(
                    "[provision \(tag, privacy: .public)] poll: ready at attempt \(attempt) (~\(elapsedMs)ms)"
                )
                return bottle
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        let stillTracked = BottleVM.shared.bottles.first(where: { $0.url == newBottleURL })
        Logger.wineKit.error(
            """
            [provision \(tag, privacy: .public)] poll: TIMED OUT after 45s. \
            bottle in BottleVM.bottles=\(stillTracked != nil) \
            inFlight=\(stillTracked?.inFlight ?? true)
            """
        )
        return nil
    }

    private func showProvisionFailureAlert(bottleName: String) {
        let alert = NSAlert()
        alert.messageText = "Could not set up \(bottleName)"
        alert.informativeText = "Crosswire was unable to prepare a new environment for this app "
            + "in time. See the latest run log for details: ~/Library/Logs/app.Crosswire.Crosswire/."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
