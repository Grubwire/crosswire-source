//
//  Process+Extensions.swift
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
import os.log

public enum ProcessOutput: Hashable, @unchecked Sendable {
    case started(Process)
    case message(String)
    case error(String)
    case terminated(Process)
}

public extension Process {
    /// Run the process returning a stream output
    func runStream(name: String, fileHandle: FileHandle?) throws -> AsyncStream<ProcessOutput> {
        let stream = makeStream(name: name, fileHandle: fileHandle)
        self.logProcessInfo(name: name)
        fileHandle?.writeInfo(for: self)
        try run()
        return stream
    }

    private func makeStream(name: String, fileHandle: FileHandle?) -> AsyncStream<ProcessOutput> {
        let pipe = Pipe()
        let errorPipe = Pipe()
        standardOutput = pipe
        standardError = errorPipe

        return AsyncStream<ProcessOutput> { continuation in
            continuation.onTermination = { termination in
                if case .cancelled = termination, self.isRunning {
                    self.terminate()
                }
            }

            continuation.yield(.started(self))

            // Per-pipe accumulator. A pipe read can return a partial line, or
            // bytes that end mid-UTF-8-codepoint. Lossy UTF-8 decode never
            // returns nil so we never silently drop content. The carry is the
            // tail after the last newline (or the whole chunk if no newline);
            // it gets prepended to the next read.
            let stdoutCarry = LineBuffer()
            let stderrCarry = LineBuffer()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                stdoutCarry.feed(data) { line in
                    continuation.yield(.message(line))
                    Logger.wineKit.info("\(line, privacy: .public)")
                    fileHandle?.write(line: line + "\n")
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                stderrCarry.feed(data) { line in
                    continuation.yield(.error(line))
                    Logger.wineKit.warning("\(line, privacy: .public)")
                    fileHandle?.write(line: line + "\n")
                }
            }

            terminationHandler = { (process: Process) in
                Self.drainPipesAtTermination(
                    pipe: pipe,
                    errorPipe: errorPipe,
                    stdoutCarry: stdoutCarry,
                    stderrCarry: stderrCarry,
                    fileHandle: fileHandle,
                    continuation: continuation
                )
                process.logTermination(name: name)
                continuation.yield(.terminated(process))
                continuation.finish()
            }
        }
    }

    // Drain anything still in the pipes at termination and route it through
    // the same line splitter.
    //
    // CRITICAL: this MUST NOT block. Bug #94: when an installer ShellExecutes
    // a launcher in its Finish step, the launcher inherits the parent wine
    // process's stdout/stderr file descriptors via wineserver. Even after
    // the foreground wine process exits and terminationHandler fires, the
    // pipes' write end is still held by wineserver+launcher, so they never
    // EOF. A previous implementation called `readToEnd()` here, which
    // blocks indefinitely waiting for EOF, suspended this terminationHandler
    // closure forever, and `continuation.finish()` never ran. Result: the
    // install flow's `for await` loop was stuck even though the foreground
    // wine process had cleanly exited 0 — the auto-features (plist seed,
    // dwrite override, finalizeAppIdentity) never got a chance to run.
    //
    // Fix: use `availableData` (non-blocking) to drain only what's currently
    // buffered in the pipe. We may lose a small tail of output written
    // BETWEEN the last readabilityHandler invocation and this drain, but
    // that's acceptable — readabilityHandler already streamed the bulk to
    // the log in real time.
    // swiftlint:disable function_parameter_count
    private static func drainPipesAtTermination(
        pipe: Pipe,
        errorPipe: Pipe,
        stdoutCarry: LineBuffer,
        stderrCarry: LineBuffer,
        fileHandle: FileHandle?,
        continuation: AsyncStream<ProcessOutput>.Continuation
    ) {
    // swiftlint:enable function_parameter_count
        pipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        let stdoutTail = pipe.fileHandleForReading.availableData
        if !stdoutTail.isEmpty {
            stdoutCarry.feed(stdoutTail) { line in
                continuation.yield(.message(line))
                Logger.wineKit.info("\(line, privacy: .public)")
                fileHandle?.write(line: line + "\n")
            }
        }
        let stderrTail = errorPipe.fileHandleForReading.availableData
        if !stderrTail.isEmpty {
            stderrCarry.feed(stderrTail) { line in
                continuation.yield(.error(line))
                Logger.wineKit.warning("\(line, privacy: .public)")
                fileHandle?.write(line: line + "\n")
            }
        }
        // Flush any final non-newline-terminated content already in the carry
        // buffer from earlier readabilityHandler reads.
        if let last = stdoutCarry.flush() {
            continuation.yield(.message(last))
            fileHandle?.write(line: last + "\n")
        }
        if let last = stderrCarry.flush() {
            continuation.yield(.error(last))
            fileHandle?.write(line: last + "\n")
        }
        do {
            try fileHandle?.close()
        } catch {
            Logger.wineKit.error("Error closing fileHandle at termination: \(error)")
        }
    }

    private func logTermination(name: String) {
        if terminationStatus == 0 {
            Logger.wineKit.info(
                "Terminated \(name) with status code '\(self.terminationStatus, privacy: .public)'"
            )
        } else {
            Logger.wineKit.warning(
                "Terminated \(name) with status code '\(self.terminationStatus, privacy: .public)'"
            )
        }
    }

    private func logProcessInfo(name: String) {
        Logger.wineKit.info("Running process \(name)")

        if let arguments = arguments {
            Logger.wineKit.info("Arguments: `\(arguments.joined(separator: " "))`")
        }
        if let executableURL = executableURL {
            Logger.wineKit.info("Executable: `\(executableURL.path(percentEncoded: false))`")
        }
        if let directory = currentDirectoryURL {
            Logger.wineKit.info("Directory: `\(directory.path(percentEncoded: false))`")
        }
        if let environment = environment {
            Logger.wineKit.info("Environment: \(environment)")
        }
    }
}

extension FileHandle {
    func nextLine() -> String? {
        guard let line = String(data: availableData, encoding: .utf8) else { return nil }
        if !line.isEmpty {
            return line
        } else {
            return nil
        }
    }
}

/// Accumulates bytes across multiple pipe reads, emits one whole line per
/// callback. Holds the carry (bytes after the last newline) for the next
/// feed. Lossy UTF-8 decoding so partial multi-byte sequences never silently
/// drop a whole batch — they become replacement characters at worst, on the
/// boundary, which is acceptable for a debug log.
///
/// `@unchecked Sendable`: pipe `readabilityHandler` and `terminationHandler`
/// are `@Sendable` closures under Swift 6 strict concurrency. Each pipe owns
/// its own LineBuffer and the buffer is only ever touched from that pipe's
/// internal serial dispatch queue (or the termination thread after the
/// readabilityHandler has been cleared). There is no cross-thread access in
/// practice, so the unchecked marker is correct here. Same `@unchecked
/// Sendable` pattern as `ProcessOutput` at the top of this file.
final class LineBuffer: @unchecked Sendable {
    private var carry: Data = Data()

    /// Feed new bytes; the closure is called once per complete (newline-
    /// terminated) line. The newline itself is stripped before emission.
    func feed(_ data: Data, _ emit: (String) -> Void) {
        var combined = carry
        combined.append(data)
        // Walk newline boundaries. We strip trailing \r too so Wine's
        // occasional CRLF doesn't leave \r in the emitted line.
        var start = combined.startIndex
        for index in combined.indices where combined[index] == 0x0A {
            var lineEnd = index
            if lineEnd > start && combined[combined.index(before: lineEnd)] == 0x0D {
                lineEnd = combined.index(before: lineEnd)
            }
            let lineData = combined[start..<lineEnd]
            // swiftlint:disable:next optional_data_string_conversion
            let line = String(decoding: lineData, as: UTF8.self)
            emit(line)
            start = combined.index(after: index)
        }
        carry = (start < combined.endIndex) ? combined.subdata(in: start..<combined.endIndex) : Data()
    }

    /// Returns the trailing content (no newline) and clears the buffer.
    /// Called at termination to flush a final non-newline-terminated line.
    func flush() -> String? {
        guard !carry.isEmpty else { return nil }
        // swiftlint:disable:next optional_data_string_conversion
        let line = String(decoding: carry, as: UTF8.self)
        carry = Data()
        return line.isEmpty ? nil : line
    }
}
