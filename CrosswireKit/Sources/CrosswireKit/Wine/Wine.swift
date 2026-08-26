//
//  Wine.swift
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
import os.log

// swiftlint:disable file_length

@MainActor
// swiftlint:disable:next type_body_length
public class Wine {
    /// URL to the installed `DXVK` folder. Lives inside the engine tree so DXVK
    /// ships, versions, signs, and installs atomically with the engine archive
    /// (engine-bundle.yml drops d9vk into `engine/DXVK/{x64,x32}`); previously a
    /// sibling of Engine/ under Libraries/, which the engine archive never wrote.
    ///
    /// Computed, not a cached `static let`: CrosswireEngine.engineFolder can now
    /// change during a single run (a fresh Stage-2 install starts on the bundled
    /// engine, then an in-session update installs a newer one to Application
    /// Support). A cached constant would keep pointing at the stale path until
    /// the app restarts, safe under Stage 1 where the underlying path never
    /// changed during a run, not safe now.
    private nonisolated static var dxvkFolder: URL {
        CrosswireEngine.engineFolder.appending(path: "DXVK")
    }
    /// Path to the Crosswire64 wrapper (thin shell over wine64; all app code uses this, never wine64 directly)
    public nonisolated static var wineBinary: URL {
        CrosswireEngine.binFolder.appending(path: "Crosswire64")
    }
    /// Path to the Crosswireserver wrapper (thin shell over wineserver)
    private nonisolated static var wineserverBinary: URL {
        CrosswireEngine.binFolder.appending(path: "Crosswireserver")
    }

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL, directory: URL? = nil,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = directory ?? executableURL.deletingLastPathComponent()
        process.environment = environment
        process.qualityOfService = .userInitiated

        return try process.runStream(
            name: name ?? args.joined(separator: " "), fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    private static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineBinary,
            fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    private static func runWineserverProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineserverBinary,
            fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    public static func runWineProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineProcess(
            name: name, args: args,
            environment: constructWineEnvironment(for: bottle, environment: environment),
            fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    public static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineserverProcess(
            name: name, args: args,
            environment: constructWineServerEnvironment(for: bottle, environment: environment),
            fileHandle: fileHandle
        )
    }

    /// Execute a `wine start {url}` command returning the output result.
    /// Per-program plist (Program Settings/<exe>.plist) env / locale / args are auto-merged.
    /// Caller-supplied `environment` keys and non-empty `args` override the plist.
    ///
    /// Returns a `ProgramRunReport` describing the exit. Also posts
    /// `.crosswireProgramDidExit` on `NotificationCenter.default` so the
    /// app's `FailureWatcher` can surface a dialog on abnormal exits.
    ///
    /// `captureDiagnostics` controls the launch mode:
    /// - `false` (default): `wine start /unix <path>` — detached. The app is
    ///   reparented to wineserver, so it survives Crosswire quitting, but the
    ///   foreground `start` process exits within seconds and the per-run log
    ///   stops capturing there. The report's `exitCode` is `start`'s, not the
    ///   app's.
    /// - `true`: direct `wine <path>` — the foreground wine process *is* the
    ///   app and lives for its whole lifetime, so the per-run log captures the
    ///   app's complete stdout/stderr through to crash/exit and the report's
    ///   `exitCode` is the app's real status (so `FailureWatcher` fires on a
    ///   real crash). Tradeoff: the app is a direct child of Crosswire and
    ///   stops if Crosswire quits — intended for reproducing crashes (#84/#93),
    ///   not normal launches. Mirrors `runInstaller`'s proven direct-invocation
    ///   path (non-blocking pipe drain — no #94 hang).
    @discardableResult
    public static func runProgram(
        at url: URL, args: [String] = [], bottle: Bottle,
        environment: [String: String] = [:], captureDiagnostics: Bool = false
    ) async throws -> ProgramRunReport {
        var finalEnv = environment
        var finalArgs = args
        if let settings = loadProgramSettings(for: url, in: bottle) {
            for (key, value) in settings.environment where finalEnv[key] == nil {
                finalEnv[key] = value
            }
            if settings.locale != .auto, finalEnv["LC_ALL"] == nil {
                finalEnv["LC_ALL"] = settings.locale.rawValue
            }
            if finalArgs.isEmpty, !settings.arguments.isEmpty {
                finalArgs = settings.arguments.split { $0.isWhitespace }.map(String.init)
            }
        }

        if bottle.settings.dxvk {
            try enableDXVK(bottle: bottle)
        }

        let unixPath = url.path(percentEncoded: false)
        let wineArgs = captureDiagnostics
            ? [unixPath] + finalArgs
            : ["start", "/unix", unixPath] + finalArgs

        let startedAt = Date()
        var exitCode: Int32 = 0
        var logURL: URL?
        for await output in try Self.runWineProcess(
            name: url.lastPathComponent,
            args: wineArgs,
            bottle: bottle, environment: finalEnv
        ) {
            switch output {
            case .terminated(let process):
                exitCode = process.terminationStatus
            case .started:
                if logURL == nil { logURL = latestRunLogURL() }
            case .message, .error:
                break
            }
        }

        let report = ProgramRunReport(
            executableURL: url,
            bottleURL: bottle.url,
            bottleDisplayName: bottle.settings.name,
            exitCode: exitCode,
            duration: Date().timeIntervalSince(startedAt),
            logFileURL: logURL ?? latestRunLogURL()
        )
        NotificationCenter.default.post(name: .crosswireProgramDidExit, object: report)
        return report
    }

    /// Run an installer .exe and wait for IT SPECIFICALLY to exit, without
    /// waiting for any background processes it may have launched (e.g. an
    /// Inno Setup wizard's "Run after install" Finish-step launcher).
    ///
    /// Bug #94 was that `runProgram(at:)` uses `wine start /unix <path>`,
    /// which fires the .exe as a detached child of wineserver and then exits
    /// — but only after wineserver decides to release its grip, which it
    /// won't do while any child process (including the installer-spawned
    /// launcher) is still running. That blocks the install flow's await for
    /// minutes-to-forever, blocking finalizeAppIdentity + JavaAppDetector
    /// from running until the user closes the unrelated launcher window.
    ///
    /// This method runs the installer with a direct `wine <path>` invocation
    /// (no `start`). Direct invocation makes the foreground wine process
    /// represent the installer's own process: it lives as long as the .exe
    /// lives, exits when the .exe exits. Grandchildren the installer
    /// `ShellExecute`s do NOT extend this method's await — they keep running
    /// under wineserver but the install flow is free to proceed to its
    /// post-install code.
    ///
    /// Used by the install flow (`ContentView+Install.provisionAndInstall`)
    /// for the installer step only. The user's Run button + ad-hoc launch
    /// paths still use `runProgram(at:)` because they want detached
    /// `start /unix` semantics (the app keeps running after Crosswire's
    /// invocation completes).
    @discardableResult
    public static func runInstaller(
        at url: URL, bottle: Bottle, environment: [String: String] = [:]
    ) async throws -> ProgramRunReport {
        var finalEnv = environment
        if let settings = loadProgramSettings(for: url, in: bottle) {
            for (key, value) in settings.environment where finalEnv[key] == nil {
                finalEnv[key] = value
            }
            if settings.locale != .auto, finalEnv["LC_ALL"] == nil {
                finalEnv["LC_ALL"] = settings.locale.rawValue
            }
        }
        if bottle.settings.dxvk {
            try enableDXVK(bottle: bottle)
        }

        let startedAt = Date()
        var exitCode: Int32 = 0
        var logURL: URL?
        // Direct wine invocation: foreground wine wraps the installer's own
        // process. Exits when the installer exits, independent of any
        // wineserver children the installer may have spawned.
        for await output in try Self.runWineProcess(
            name: url.lastPathComponent,
            args: [url.path(percentEncoded: false)],
            bottle: bottle, environment: finalEnv
        ) {
            switch output {
            case .terminated(let process):
                exitCode = process.terminationStatus
            case .started:
                if logURL == nil { logURL = latestRunLogURL() }
            case .message, .error:
                break
            }
        }

        let report = ProgramRunReport(
            executableURL: url,
            bottleURL: bottle.url,
            bottleDisplayName: bottle.settings.name,
            exitCode: exitCode,
            duration: Date().timeIntervalSince(startedAt),
            logFileURL: logURL ?? latestRunLogURL()
        )
        NotificationCenter.default.post(name: .crosswireProgramDidExit, object: report)
        return report
    }

    /// Best-effort lookup of the run log file `runWineProcess` just opened.
    /// `makeFileHandle()` (in Extensions) writes to
    /// `~/Library/Logs/app.Crosswire.Crosswire/<timestamp>.log`; the most
    /// recent file is overwhelmingly likely to be the one for this run.
    private static func latestRunLogURL() -> URL? {
        let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appending(path: "Logs")
            .appending(path: "app.Crosswire.Crosswire")
        guard let logDir,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: logDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else { return nil }
        return entries
            .filter { $0.pathExtension == "log" }
            .max { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return lhsDate < rhsDate
            }
    }

    /// Load the per-program plist for an exe inside a bottle, if one exists on disk.
    /// Returns nil when the program has no plist (the common case).
    ///
    /// If the full Codable decode fails (e.g. a hand-edited plist has one bad
    /// field like a wrong locale raw value), salvages the rest via a raw
    /// `PropertyListSerialization` read so the user's env vars and arguments
    /// still apply. Silent decode-failure was a real footgun: it caused the
    /// SWG launcher to keep sliver-rendering after a hand-written plist used
    /// `<string>auto</string>` for locale (`.auto` decodes from `""`).
    private static func loadProgramSettings(for url: URL, in bottle: Bottle) -> ProgramSettings? {
        let plistURL = bottle.url
            .appending(path: "Program Settings")
            .appending(path: url.lastPathComponent)
            .appendingPathExtension("plist")
        guard FileManager.default.fileExists(atPath: plistURL.path(percentEncoded: false)) else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: plistURL)
        } catch {
            Logger.wineKit.error("Failed to read per-program settings at \(plistURL.path): \(error)")
            return nil
        }
        if let full = try? PropertyListDecoder().decode(ProgramSettings.self, from: data) {
            return full
        }
        // Full decode failed — try a salvage read so env/args survive a single
        // malformed field. Logged so the failure is still visible.
        Logger.wineKit.error("Full decode failed for \(plistURL.path); attempting env/args salvage")
        return salvageProgramSettings(from: data)
    }

    /// Best-effort recovery of env + args from a per-program plist whose full
    /// decode failed. Reads the plist as a loose dictionary, accepts only the
    /// fields it knows how to coerce safely, and skips anything dubious (like
    /// `locale`, which is the most common cause of full-decode failure).
    private static func salvageProgramSettings(from data: Data) -> ProgramSettings? {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            return nil
        }
        var settings = ProgramSettings()
        if let env = plist["environment"] as? [String: String] {
            settings.environment = env
        }
        if let args = plist["arguments"] as? String {
            settings.arguments = args
        }
        return settings
    }

    public static func generateRunCommand(
        at url: URL, bottle: Bottle, args: String, environment: [String: String]
    ) -> String {
        var wineCmd = "\(wineBinary.esc) start /unix \(url.esc) \(args)"
        let env = constructWineEnvironment(for: bottle, environment: environment)
        for environment in env {
            wineCmd = "\(environment.key)=\"\(environment.value)\" " + wineCmd
        }

        return wineCmd
    }

    public static func generateTerminalEnvironmentCommand(bottle: Bottle) -> String {
        var cmd = """
        export PATH=\"\(CrosswireEngine.binFolder.path):$PATH\"
        export WINE=\"Crosswire64\"
        alias wine=\"Crosswire64\"
        alias winecfg=\"Crosswire64 winecfg\"
        alias msiexec=\"Crosswire64 msiexec\"
        alias regedit=\"Crosswire64 regedit\"
        alias regsvr32=\"Crosswire64 regsvr32\"
        alias wineboot=\"Crosswire64 wineboot\"
        alias wineconsole=\"Crosswire64 wineconsole\"
        alias winedbg=\"Crosswire64 winedbg\"
        alias winefile=\"Crosswire64 winefile\"
        alias winepath=\"Crosswire64 winepath\"
        """

        let env = constructWineEnvironment(for: bottle, environment: constructWineEnvironment(for: bottle))
        for environment in env {
            cmd += "\nexport \(environment.key)=\"\(environment.value)\""
        }

        return cmd
    }

    /// Run a `wineserver` command with the given arguments and return the output result
    private static func runWineserver(_ args: [String], bottle: Bottle) async throws -> String {
        var result: [ProcessOutput] = []

        for await output in try Self.runWineserverProcess(args: args, bottle: bottle, environment: [:]) {
            result.append(output)
        }

        return result.compactMap { output -> String? in
            switch output {
            case .started, .terminated:
                return nil
            case .message(let message), .error(let message):
                return message
            }
        }.joined()
    }

    @discardableResult
    /// Run a `wine` command with the given arguments and return the output result
    public static func runWine(
        _ args: [String], bottle: Bottle?, environment: [String: String] = [:]
    ) async throws -> String {
        var result: [String] = []
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        var environment = environment

        if let bottle = bottle {
            fileHandle.writeInfo(for: bottle)
            environment = constructWineEnvironment(for: bottle, environment: environment)
        }

        for await output in try runWineProcess(args: args, environment: environment, fileHandle: fileHandle) {
            switch output {
            case .started, .terminated:
                break
            case .message(let message), .error(let message):
                result.append(message)
            }
        }

        return result.joined()
    }

    public static func wineVersion() async throws -> String {
        var output = try await runWine(["--version"], bottle: nil)
        output.replace("wine-", with: "")

        // Deal with WineCX version names
        if let index = output.firstIndex(where: { $0.isWhitespace }) {
            return String(output.prefix(upTo: index))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    public static func runBatchFile(url: URL, bottle: Bottle) async throws -> String {
        return try await runWine(["cmd", "/c", url.path(percentEncoded: false)], bottle: bottle)
    }

    public static func killBottle(bottle: Bottle) throws {
        Task(priority: .userInitiated) {
            try await runWineserver(["-k"], bottle: bottle)
        }
    }

    /// Kill the bottle's wineserver and BLOCK until it has fully terminated.
    /// Unlike `killBottle` (fire-and-forget — it returns before the kill has
    /// even started), this awaits teardown via `wineserver -k -w` (kill, then
    /// wait for termination). A caller that relaunches immediately afterward is
    /// then guaranteed a clean prefix rather than racing a half-dead wineserver
    /// (the post-install "blank launcher window" bug).
    ///
    /// - Warning: the wait is UNBOUNDED. `wineserver -w` blocks until every
    ///   client has exited, so a stuck/zombie wine process that survives the
    ///   kill makes this hang forever. Hang-sensitive callers (e.g. an
    ///   interactive flow) must impose their own timeout — see
    ///   `killBottleBounded` in the install flow.
    public static func killBottleAndWait(bottle: Bottle) async throws {
        _ = try await runWineserver(["-k", "-w"], bottle: bottle)
    }

    /// PIDs of processes currently running inside this bottle's prefix.
    ///
    /// Programs are launched with `WINEPREFIX` in their environment, and since
    /// Crosswire owns these processes we can read that environment back via
    /// `ps -E`. Matching `WINEPREFIX=<prefix>` gives a precise per-bottle
    /// liveness signal — `runProgram` itself can't provide one because
    /// `wine start /unix` detaches and returns immediately. Returns an empty
    /// array when nothing is running in the bottle.
    public static func runningProcessIDs(for bottle: Bottle) -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aww", "-E", "-o", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        let needle = "WINEPREFIX=\(bottle.url.path)"
        var pids: [pid_t] = []
        for line in output.split(separator: "\n") where line.contains(needle) {
            let digits = line.drop { $0 == " " }.prefix { $0.isNumber }
            if let pid = pid_t(digits) {
                pids.append(pid)
            }
        }
        return pids
    }

    /// Best-effort: is any process whose command line mentions `needle`
    /// currently running? Matches by argv (visible in `ps`) rather than env —
    /// a re-exec'ing launcher forks a detached child (`ppid=1`) whose env is
    /// hidden from `ps -E`, but whose argv still carries the launched exe name.
    /// The diagnostics flow uses this to wait out such a child before
    /// collecting crash artifacts. Argv basename collisions across bottles can
    /// extend the wait but never break it (single-instance does proper
    /// per-bottle disambiguation separately).
    public static func isProcessRunning(matching needle: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aww", "-o", "command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").contains(needle)
    }

    /// Set AeDebug.Auto = 0 in both the 64-bit and 32-bit (Wow6432Node)
    /// registry views. Stops Wine from spawning `winedbg --auto` on every
    /// in-process crash. Critical for JVM-based apps under Wine — the HotSpot
    /// JIT routinely triggers safepoint crashes that recover internally
    /// (especially with `-Xint`), but each one was leaving a stuck winedbg
    /// process behind. After a few hours of accumulation those debuggers can
    /// bring the host Mac to its knees (saw 965 stuck procs + load avg 75
    /// from one launcher session).
    public static func disableCrashDebugger(bottle: Bottle) async throws {
        let regContent = """
        REGEDIT4

        [HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\AeDebug]
        "Auto"="0"

        [HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Microsoft\\Windows NT\\CurrentVersion\\AeDebug]
        "Auto"="0"

        """
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "crosswire-disable-aedebug-\(UUID().uuidString).reg")
        try regContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try await runWine(["regedit", "/S", tempURL.path(percentEncoded: false)], bottle: bottle)
    }

    /// Directory for the dedup script and its state file. Deliberately
    /// `~/Library/Caches/<bundleID>`, NOT `CrosswireEngine.applicationFolder`
    /// (`~/Library/Application Support/...`): confirmed empirically that
    /// Wine's `Browsers` registry value cannot contain a space -- it is
    /// parsed as a delimited list of candidate commands, not one quoted
    /// path, so "Application Support" silently breaks the whole override
    /// (winebrowser falls through to "could not find a suitable app to
    /// open" with no error surfaced anywhere). This path has no spaces.
    private nonisolated static let browserDedupDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appending(path: Bundle.CrosswireBundleIdentifier)
    }()

    /// Shared wrapper script every bottle's `HKCU\Software\Wine\WineBrowser`
    /// `Browsers` value points at (#128). A Windows-side dependency check
    /// that fails and retries can call `ShellExecute` on the same URL every
    /// attempt; Wine's own browser passthrough has no memory of a URL it
    /// already opened, so each retry opened a fresh tab with nothing
    /// capping or deduping them. This script rate-limits repeats of the
    /// same URL to one open per window before handing off to the real
    /// `open`, confirmed empirically (a real winebrowser.exe invocation
    /// against this engine) to be Wine's actual browser-launch mechanism
    /// on macOS, not a Linux-only xdg-open path.
    private nonisolated static var browserDedupScriptURL: URL {
        browserDedupDir.appending(path: "browser-dedup.sh")
    }

    private nonisolated static func browserDedupScript(stateFilePath: String) -> String {
        """
        #!/bin/bash
        # Crosswire: rate-limit repeated browser-open requests forwarded from
        # Wine (winebrowser.exe's ShellExecute passthrough). Without this, a
        # dependency check that retries on failure opens a fresh tab every
        # single attempt instead of failing gracefully once. See #128.
        URL="$1"
        STATE_FILE="\(stateFilePath)"
        WINDOW=30

        NOW=$(date +%s)
        touch "$STATE_FILE"

        LAST=$(grep -F "$URL|" "$STATE_FILE" | tail -1 | cut -d'|' -f2)
        if [ -n "$LAST" ] && [ $((NOW - LAST)) -lt "$WINDOW" ]; then
            exit 0
        fi

        echo "$URL|$NOW" >> "$STATE_FILE"
        # Cap so a long session with many distinct URLs can't grow this file
        # unbounded.
        tail -n 50 "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

        exec open "$URL"

        """
    }

    /// Points this bottle's Wine browser launcher at the shared dedup
    /// script (writing the script itself the first time, idempotently).
    /// Called once per bottle at creation, the same way
    /// `disableCrashDebugger` is.
    public static func configureBrowserDedup(bottle: Bottle) async throws {
        if !FileManager.default.fileExists(atPath: browserDedupScriptURL.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: browserDedupDir, withIntermediateDirectories: true)
            let stateFilePath = browserDedupDir.appending(path: "browser-open-state.txt").path(percentEncoded: false)
            try browserDedupScript(stateFilePath: stateFilePath)
                .write(to: browserDedupScriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: browserDedupScriptURL.path(percentEncoded: false)
            )
        }

        let scriptPath = browserDedupScriptURL.path(percentEncoded: false)
        let regContent = """
        REGEDIT4

        [HKEY_CURRENT_USER\\Software\\Wine\\WineBrowser]
        "Browsers"="\(scriptPath)"

        """
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "crosswire-browser-dedup-\(UUID().uuidString).reg")
        try regContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try await runWine(["regedit", "/S", tempURL.path(percentEncoded: false)], bottle: bottle)
    }

    /// Add a Wine DLL override at
    /// `HKEY_CURRENT_USER\Software\Wine\DllOverrides`. Idempotent: if an
    /// entry for `dll` already exists with any value, leaves it untouched
    /// (respects user customization). Returns true when an override was
    /// actually written.
    ///
    /// The headline use case is `dwrite=builtin` for self-contained
    /// JavaFX launchers — Wine's built-in dwrite avoids the crash path
    /// the bundled MS dwrite hits during the post-Login CSS reapply.
    @discardableResult
    public static func setDllOverrideIfAbsent(
        _ dll: String, value: String, bottle: Bottle
    ) async throws -> Bool {
        let userReg = bottle.url.appending(path: "user.reg")
        if let contents = try? String(contentsOf: userReg, encoding: .utf8),
           contents.contains("\"\(dll)\"=") {
            return false
        }
        let regContent = """
        REGEDIT4

        [HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]
        "\(dll)"="\(value)"

        """
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "crosswire-dll-override-\(UUID().uuidString).reg")
        try regContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try await runWine(["regedit", "/S", tempURL.path(percentEncoded: false)], bottle: bottle)
        return true
    }

    public static func enableDXVK(bottle: Bottle) throws {
        // No-op when the installed engine doesn't ship DXVK (the prod engine
        // currently doesn't — only the beta channel does). Without this guard,
        // a bottle with DXVK on would fail to launch on a non-DXVK engine
        // because the source folders don't exist.
        guard FileManager.default.fileExists(atPath: Wine.dxvkFolder.path(percentEncoded: false)) else {
            return
        }
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x64")
        )
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "syswow64"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x32")
        )
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]
        bottle.settings.environmentVariables(wineEnv: &result)
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineServerEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }
}

enum WineInterfaceError: Error {
    case invalidResponce
}

enum RegistryType: String {
    case binary = "REG_BINARY"
    case dword = "REG_DWORD"
    case qword = "REG_QWORD"
    case string = "REG_SZ"
}

extension Wine {
    public nonisolated static let logsFolder = FileManager.default.urls(
        for: .libraryDirectory, in: .userDomainMask
    )[0].appending(path: "Logs").appending(path: Bundle.CrosswireBundleIdentifier)

    public nonisolated static func makeFileHandle() throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: Self.logsFolder.path) {
            try FileManager.default.createDirectory(at: Self.logsFolder, withIntermediateDirectories: true)
        }

        let dateString = Date.now.ISO8601Format()
        let fileURL = Self.logsFolder.appending(path: dateString).appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileHandle(forWritingTo: fileURL)
    }
}

extension Wine {
    private enum RegistryKey: String {
        case currentVersion = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#
        case macDriver = #"HKCU\Software\Wine\Mac Driver"#
        case desktop = #"HKCU\Control Panel\Desktop"#
    }

    private static func addRegistryKey(
        bottle: Bottle, key: String, name: String, data: String, type: RegistryType
    ) async throws {
        try await runWine(
            ["reg", "add", key, "-v", name, "-t", type.rawValue, "-d", data, "-f"],
            bottle: bottle
        )
    }

    private static func queryRegistryKey(
        bottle: Bottle, key: String, name: String, type: RegistryType
    ) async throws -> String? {
        let output = try await runWine(["reg", "query", key, "-v", name], bottle: bottle)
        let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)

        guard let line = lines.first(where: { $0.contains(type.rawValue) }) else { return nil }
        let array = line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard let value = array.last else { return nil }
        return String(value)
    }

    public static func changeBuildVersion(bottle: Bottle, version: Int) async throws {
        try await addRegistryKey(bottle: bottle, key: RegistryKey.currentVersion.rawValue,
                                name: "CurrentBuild", data: "\(version)", type: .string)
        try await addRegistryKey(bottle: bottle, key: RegistryKey.currentVersion.rawValue,
                                name: "CurrentBuildNumber", data: "\(version)", type: .string)
    }

    public static func winVersion(bottle: Bottle) async throws -> WinVersion {
        let output = try await Wine.runWine(["winecfg", "-v"], bottle: bottle)
        let lines = output.split(whereSeparator: \.isNewline)

        if let lastLine = lines.last {
            let winString = String(lastLine)

            if let version = WinVersion(rawValue: winString) {
                return version
            }
        }

        throw WineInterfaceError.invalidResponce
    }

    public static func buildVersion(bottle: Bottle) async throws -> String? {
        return try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.currentVersion.rawValue,
            name: "CurrentBuild", type: .string
        )
    }

    public static func retinaMode(bottle: Bottle) async throws -> Bool {
        let values: Set<String> = ["y", "n"]
        guard let output = try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", type: .string
        ), values.contains(output) else {
            try await changeRetinaMode(bottle: bottle, retinaMode: false)
            return false
        }
        return output == "y"
    }

    public static func changeRetinaMode(bottle: Bottle, retinaMode: Bool) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", data: retinaMode ? "y" : "n",
            type: .string
        )
    }

    public static func dpiResolution(bottle: Bottle) async throws -> Int? {
        guard let output = try await Wine.queryRegistryKey(bottle: bottle, key: RegistryKey.desktop.rawValue,
                                                     name: "LogPixels", type: .dword
        ) else { return nil }

        let noPrefix = output.replacingOccurrences(of: "0x", with: "")
        let int = Int(noPrefix, radix: 16)
        guard let int = int else { return nil }
        return int
    }

    public static func changeDpiResolution(bottle: Bottle, dpi: Int) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.desktop.rawValue, name: "LogPixels", data: String(dpi),
            type: .dword
        )
    }

    @discardableResult
    public static func control(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["control"], bottle: bottle)
    }

    @discardableResult
    public static func regedit(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["regedit"], bottle: bottle)
    }

    @discardableResult
    public static func cfg(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["winecfg"], bottle: bottle)
    }

    @discardableResult
    public static func changeWinVersion(bottle: Bottle, win: WinVersion) async throws -> String {
        return try await Wine.runWine(["winecfg", "-v", win.rawValue], bottle: bottle)
    }
}
