//
//  EntryDetailView.swift
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

/// Full-bleed inline per-entry detail shown when `AppRoute == .entryDetail`.
/// Slides in over the library (same pattern as inline Settings); the back
/// chevron returns. Replaces the old detached per-app settings sheet.
///
/// This is a transient overlay, so it sits on a `.regularMaterial` blur over
/// the library shell (materials-vs-hex rule). Launch + run-specific routes go
/// back out through ContentView's run helpers so single-instance handling
/// (Commit 6) applies uniformly.
struct EntryDetailView: View {
    @ObservedObject var bottle: Bottle
    var onBack: () -> Void
    var onRun: () -> Void
    var onRunProgram: (Program) -> Void
    var onUninstall: () -> Void
    /// Launch with full-lifetime diagnostics capture (Advanced › Maintenance).
    var onLaunchDiagnostics: () -> Void

    @State private var showRuntimesSheet: Bool = false
    @State private var isRenaming: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            InlinePanelBackBar(action: onBack)
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    launchButton
                    secondaryActions
                    EntryDetailAdvancedSection(bottle: bottle,
                                               onRunProgram: onRunProgram,
                                               onLaunchDiagnostics: onLaunchDiagnostics)
                }
                .padding(28)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(.regularMaterial)
        .sheet(isPresented: $showRuntimesSheet) {
            CommonRuntimesView(bottle: bottle)
        }
        .onAppear {
            if bottle.programs.isEmpty {
                bottle.updateInstalledPrograms()
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(spacing: 18) {
            AppIcon(bottle: bottle, side: 84)
            VStack(alignment: .leading, spacing: 5) {
                nameField
                Text(categoryLine)
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                Text(lastPlayedLine)
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textTertiary)
            }
            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CrosswireTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CrosswireTheme.surfaceStroke, lineWidth: 1)
        )
    }

    /// "Last played 2 hours ago" / "Never launched", for the hero subtitle.
    /// Unlike the library line this never shows "Setting up…" — the detail view
    /// has the provisioning state covered elsewhere.
    private var lastPlayedLine: String {
        guard let relative = bottle.lastPlayedDescription else { return "Never launched" }
        return "Last played \(relative)"
    }

    /// The name, plus a pencil that starts an inline rename. The pencil is
    /// hidden while editing so it does not sit beside its own text field.
    private var nameField: some View {
        HStack(spacing: 8) {
            BottleRenameField(bottle: bottle,
                              isEditing: $isRenaming,
                              font: .system(size: 22, weight: .semibold),
                              maxWidth: isRenaming ? 360 : nil)
            if !isRenaming {
                Button { isRenaming = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(CrosswireButtonStyle(kind: .plain, tint: CrosswireTheme.textSecondary))
                .help("Rename")
                .accessibilityLabel("Rename")
            }
        }
    }

    private var categoryLine: String {
        let count = bottle.userVisiblePrograms.count
        if count > 1 { return "Windows app · \(count) launchers" }
        return "Windows app"
    }

    // MARK: - Launch

    private var canLaunch: Bool { bottle.canLaunch }

    private var launchButton: some View {
        Button(action: onRun) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Launch")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .buttonStyle(PrimaryCTAButtonStyle(size: .prominent, fillWidth: true))
        .disabled(!canLaunch)
        .accessibilityLabel("Launch \(bottle.displayName)")
    }

    // MARK: - Secondary actions

    private var secondaryActions: some View {
        HStack(spacing: 10) {
            secondaryButton("Check Dependencies", systemImage: "shippingbox") {
                showRuntimesSheet = true
            }
            secondaryButton("Show in Finder", systemImage: "folder") {
                bottle.revealInFinder()
            }
            secondaryButton("Uninstall", systemImage: "trash", destructive: true) {
                onUninstall()
            }
        }
    }

    @ViewBuilder
    private func secondaryButton(
        _ title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
        }
        .buttonStyle(CrosswireButtonStyle(kind: destructive ? .destructive : .secondary, fillWidth: true))
        .accessibilityLabel(title)
    }

}
