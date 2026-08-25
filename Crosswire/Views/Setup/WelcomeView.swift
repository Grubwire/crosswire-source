//
//  WelcomeView.swift
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

struct WelcomeView: View {
    @State var rosettaInstalled: Bool?
    @State var engineInstalled: Bool?
    @State var shouldCheckInstallStatus: Bool = false
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool
    var firstTime: Bool

    var body: some View {
        VStack(spacing: 0) {
            heading
                .padding(.top, 8)
            Spacer(minLength: 16)
            VStack(spacing: 0) {
                InstallStatusView(isInstalled: $rosettaInstalled,
                                  shouldCheckInstallStatus: $shouldCheckInstallStatus,
                                  name: "Rosetta")
                Divider().opacity(0.5)
                InstallStatusView(isInstalled: $engineInstalled,
                                  shouldCheckInstallStatus: $shouldCheckInstallStatus,
                                  showUninstall: true,
                                  name: "Crosswire")
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CrosswireTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(CrosswireTheme.surfaceStroke, lineWidth: 0.5)
            )
            .onAppear {
                checkInstallStatus()
            }
            .onChange(of: shouldCheckInstallStatus) {
                checkInstallStatus()
            }
            Spacer(minLength: 16)
            buttonRow
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .frame(width: 420, height: 320)
    }

    @ViewBuilder
    private var heading: some View {
        VStack(spacing: 6) {
            Text(firstTime ? "setup.welcome" : "setup.title")
                .font(CrosswireTheme.Typography.title)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Text(firstTime ? "setup.welcome.subtitle" : "setup.subtitle")
                .font(CrosswireTheme.Typography.entryMeta)
                .foregroundStyle(CrosswireTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var buttonRow: some View {
        HStack {
            if let rosettaInstalled = rosettaInstalled,
               let engineInstalled = engineInstalled {
                if !rosettaInstalled || !engineInstalled {
                    Button("setup.quit") {
                        exit(0)
                    }
                    .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(rosettaInstalled && engineInstalled ? "setup.done" : "setup.next") {
                    if !rosettaInstalled {
                        path.append(.rosetta)
                        return
                    }
                    if !engineInstalled {
                        path.append(.engineSetup)
                        return
                    }
                    SetupFlow.finish(path: $path, showSetup: $showSetup)
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

    func checkInstallStatus() {
        rosettaInstalled = Rosetta2.isRosettaInstalled
        engineInstalled = CrosswireEngine.isEnginePresent()
    }
}

struct InstallStatusView: View {
    @Binding var isInstalled: Bool?
    @Binding var shouldCheckInstallStatus: Bool
    @State var showUninstall: Bool = false
    @State var name: String
    @State var text: String = String(localized: "setup.install.checking")

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 22, height: 22)
            Text(String.init(format: text, name))
                .font(.system(size: 13))
                .foregroundStyle(CrosswireTheme.textPrimary)
            Spacer()
            if let installed = isInstalled, installed && showUninstall {
                Button("setup.uninstall") {
                    uninstall()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onChange(of: isInstalled) {
            if let installed = isInstalled {
                text = installed
                    ? String(localized: "setup.install.installed")
                    : String(localized: "setup.install.notInstalled")
            } else {
                text = String(localized: "setup.install.checking")
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let installed = isInstalled {
            Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(installed ? CrosswireTheme.success : CrosswireTheme.warning)
                .symbolRenderingMode(.hierarchical)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    func uninstall() {
        if name == "Crosswire" {
            CrosswireEngine.uninstall()
        }
        shouldCheckInstallStatus.toggle()
    }
}
