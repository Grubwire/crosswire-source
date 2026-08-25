//
//  RosettaView.swift
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

struct RosettaView: View {
    @State var installing: Bool = true
    @State var successful: Bool = true
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    var body: some View {
        VStack(spacing: 0) {
            heading
                .padding(.top, 8)
            Spacer(minLength: 12)
            content
            Spacer(minLength: 12)
            buttonRow
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .frame(width: 420, height: 320)
        .onAppear {
            Task.detached {
                await checkOrInstall()
            }
        }
    }

    @ViewBuilder
    private var heading: some View {
        VStack(spacing: 6) {
            Text("setup.rosetta")
                .font(CrosswireTheme.Typography.title)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Text("setup.rosetta.subtitle")
                .font(CrosswireTheme.Typography.entryMeta)
                .foregroundStyle(CrosswireTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if installing {
            ProgressView()
                .controlSize(.large)
                .frame(width: 96, height: 96)
        } else if successful {
            ZStack {
                Circle()
                    .fill(CrosswireTheme.success.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(CrosswireTheme.success)
            }
            .transition(.scale.combined(with: .opacity))
        } else {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(CrosswireTheme.danger.opacity(0.10))
                        .frame(width: 72, height: 72)
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(CrosswireTheme.danger)
                }
                Text("setup.rosetta.fail")
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var buttonRow: some View {
        HStack {
            if !successful {
                Button("setup.quit") {
                    exit(0)
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("setup.retry") {
                    installing = true
                    successful = true
                    Task.detached { await checkOrInstall() }
                }
                .buttonStyle(.borderedProminent)
                .tint(CrosswireTheme.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            } else {
                Spacer()
            }
        }
        .frame(height: 32)
    }

    func checkOrInstall() async {
        do {
            try await RosettaCheck.ensureInstalled()
            await MainActor.run {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    installing = false
                }
            }
            try await Task.sleep(for: .seconds(2))
            await proceed()
        } catch {
            await MainActor.run {
                successful = false
                installing = false
            }
        }
    }

    @MainActor
    func proceed() {
        if !CrosswireEngine.isEnginePresent() {
            path.append(.engineSetup)
            return
        }
        SetupFlow.finish(path: $path, showSetup: $showSetup)
    }
}

#Preview {
    RosettaView(path: .constant([]), showSetup: .constant(true))
}
