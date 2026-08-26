//
//  EngineSetupView.swift
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
import CrosswireKit

struct EngineSetupView: View {
    @State private var phase: Phase = .fetchingManifest
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadStartTime: Date?
    @State private var errorMessage: String?
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    enum Phase: Equatable {
        case fetchingManifest
        case downloading
        case verifying
        case installing
        case done
    }

    var body: some View {
        VStack(spacing: 0) {
            heading
                .padding(.top, 8)
            Spacer(minLength: 12)
            stageContent
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .frame(width: 420, height: 320)
        .onAppear { startSetup() }
    }

    @ViewBuilder
    private var heading: some View {
        VStack(spacing: 6) {
            Text(phase == .downloading ? "setup.engine.download" : "setup.engine.install")
                .font(CrosswireTheme.Typography.title)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Text("setup.engine.install.subtitle")
                .font(CrosswireTheme.Typography.entryMeta)
                .foregroundStyle(CrosswireTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        if let errorMessage {
            errorBlock(errorMessage)
        } else if phase == .done {
            successHalo
        } else if phase == .downloading && totalBytes > 0 {
            downloadProgress
        } else {
            spinnerHalo
        }
    }

    @ViewBuilder
    private var spinnerHalo: some View {
        ProgressView()
            .controlSize(.large)
            .frame(width: 96, height: 96)
    }

    @ViewBuilder
    private var successHalo: some View {
        ZStack {
            Circle()
                .fill(CrosswireTheme.success.opacity(0.12))
                .frame(width: 96, height: 96)
            Image(systemName: "checkmark")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(CrosswireTheme.success)
        }
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder
    private func errorBlock(_ message: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CrosswireTheme.danger.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(CrosswireTheme.danger)
            }
            Text(message)
                .foregroundStyle(CrosswireTheme.textPrimary)
                .font(CrosswireTheme.Typography.entryMeta)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            Button("setup.retry") {
                self.errorMessage = nil
                startSetup()
            }
            .buttonStyle(.borderedProminent)
            .tint(CrosswireTheme.accent)
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    private var downloadProgress: some View {
        VStack(spacing: 10) {
            ProgressView(value: Double(completedBytes), total: Double(totalBytes))
                .progressViewStyle(.linear)
                .tint(CrosswireTheme.accent)
            HStack(spacing: 6) {
                Text(formatBytes(completedBytes))
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Text("/")
                    .foregroundStyle(CrosswireTheme.textTertiary)
                Text(formatBytes(totalBytes))
                    .foregroundStyle(CrosswireTheme.textSecondary)
                if shouldShowETA() {
                    Text("·")
                        .foregroundStyle(CrosswireTheme.textTertiary)
                    Text(formatRemainingTime())
                        .foregroundStyle(CrosswireTheme.textSecondary)
                }
                Spacer()
            }
            .font(.system(size: 11, design: .monospaced))
            .monospacedDigit()
        }
    }

    private func startSetup() {
        phase = .fetchingManifest
        completedBytes = 0
        totalBytes = 0
        downloadSpeed = 0
        downloadStartTime = nil

        Task.detached {
            do {
                let manifest = try await CrosswireEngine.fetchManifest()

                await MainActor.run {
                    phase = .downloading
                    downloadStartTime = Date()
                }

                let archive = try await CrosswireEngine.downloadArchive(manifest: manifest) { written, total in
                    Task { @MainActor in
                        let elapsed = Date().timeIntervalSince(downloadStartTime ?? Date())
                        if written > 0 && elapsed > 0 {
                            downloadSpeed = Double(written) / elapsed
                        }
                        completedBytes = written
                        if total > 0 { totalBytes = total }
                    }
                }

                await MainActor.run { phase = .verifying }
                try await CrosswireEngine.verifyAndInstall(archive: archive, manifest: manifest)
                await MainActor.run {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                        phase = .done
                    }
                }

                try await Task.sleep(for: .seconds(2))
                await MainActor.run { SetupFlow.finish(path: $path, showSetup: $showSetup) }
            } catch {
                CrosswireTelemetry.capture(error, context: "engine.setup")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    private func shouldShowETA() -> Bool {
        let elapsed = Date().timeIntervalSince(downloadStartTime ?? Date())
        return elapsed > 5 && completedBytes > 0 && downloadSpeed > 0
    }

    private func formatRemainingTime() -> String {
        let remaining = Double(totalBytes - completedBytes) / downloadSpeed
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(remaining)) ?? ""
    }
}
