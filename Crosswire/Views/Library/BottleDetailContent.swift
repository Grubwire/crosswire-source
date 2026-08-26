//
//  BottleDetailContent.swift
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

/// The bottle detail content shared by Sidebar's permanent pane
/// (`LibraryDetailPane`) and Grid's slide-over (`EntryDetailView`): name row,
/// Play button, secondary actions, and the Advanced disclosure. Both call
/// sites render `HeroArtView(bottle:)` themselves immediately before this
/// view, at their own appropriate width — see the width note in
/// `EntryDetailView.swift`.
///
/// `@ObservedObject`, not `let` — without it, `updateInstalledPrograms()`
/// completing asynchronously (the scan that makes `canLaunch` true for a
/// bottle nothing has scanned yet) never triggers a re-render, and Play
/// stays visibly disabled even after the scan succeeds. This is the same
/// mistake `GameTile` and `LibraryRow` avoid by declaring `bottle` as
/// `@ObservedObject` themselves.
struct BottleDetailContent: View {
    @ObservedObject var bottle: Bottle
    let actions: BoundBottleActions
    /// Sidebar-only: an external trigger (context menu on a different row)
    /// that should open this content already in rename mode. Grid has no
    /// such trigger and omits this parameter.
    var renameRequestID: Binding<Bottle.ID?>?

    @State private var isRenaming = false
    @State private var showProgramPicker = false
    @State private var showRuntimesSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            nameRow
            playRow
            secondaryActions
            EntryDetailAdvancedSection(bottle: bottle,
                                       onRunProgram: actions.runProgram,
                                       onLaunchDiagnostics: actions.launchDiagnostics)
        }
        .id(bottle.id)
        .onAppear {
            if bottle.isAvailable, bottle.programs.isEmpty {
                bottle.updateInstalledPrograms()
            }
        }
        .onChange(of: renameRequestID?.wrappedValue) { _, id in
            guard let renameRequestID, id == bottle.id else { return }
            isRenaming = true
            renameRequestID.wrappedValue = nil
        }
    }

    // MARK: - Name

    @ViewBuilder
    private var nameRow: some View {
        if isRenaming {
            HStack(spacing: 8) {
                BottleRenameField(bottle: bottle,
                                  isEditing: $isRenaming,
                                  font: .system(size: 18, weight: .semibold),
                                  maxWidth: 320)
            }
        }
    }

    // MARK: - Play

    private var playRow: some View {
        HStack(spacing: 12) {
            playButton
            Text(bottle.librarySecondaryLine)
                .font(CrosswireLauncherTheme.Typography.tileMeta)
                .foregroundStyle(CrosswireLauncherTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var playButton: some View {
        let multiple = bottle.userVisiblePrograms.count > 1
        Button {
            if multiple {
                showProgramPicker = true
            } else {
                actions.run()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("Play")
                    .font(CrosswireLauncherTheme.Typography.playLabel)
            }
            .frame(minWidth: CrosswireLauncherTheme.Layout.playButtonMinWidth)
        }
        .buttonStyle(LauncherPlayButtonStyle())
        .disabled(!bottle.canLaunch)
        .popover(isPresented: $showProgramPicker, arrowEdge: .bottom) {
            ProgramPickerList(programs: bottle.userVisiblePrograms) { program in
                showProgramPicker = false
                actions.runProgram(program)
            }
        }
        .accessibilityLabel("Launch \(bottle.displayName)")
    }

    // MARK: - Secondary actions

    private var secondaryActions: some View {
        HStack(spacing: 10) {
            secondaryButton("Rename", systemImage: "pencil") { isRenaming = true }
            secondaryButton("Check Dependencies", systemImage: "shippingbox") {
                showRuntimesSheet = true
            }
            secondaryButton("Show in Finder", systemImage: "folder") { bottle.revealInFinder() }
            secondaryButton("Uninstall", systemImage: "trash", destructive: true) {
                actions.uninstall()
            }
        }
        .sheet(isPresented: $showRuntimesSheet) {
            CommonRuntimesView(bottle: bottle)
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
            .font(.system(size: 12))
        }
        .buttonStyle(LauncherSecondaryButtonStyle(destructive: destructive))
        .accessibilityLabel(title)
    }
}

/// The dominant Play control's fill/press/glow. Kept here, not private — this
/// is the one place the launcher's "everything else recedes" accent
/// treatment applies, and `PrimaryCTAButtonStyle` is tuned for
/// `CrosswireTheme`, not the dark launcher tokens (white text is right in
/// both, but the glow is new here).
struct LauncherPlayButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: CrosswireLauncherTheme.Layout.playButtonCornerRadius,
                                     style: .continuous)
        configuration.label
            .foregroundStyle(CrosswireLauncherTheme.textOnAccent)
            .padding(.horizontal, 22)
            .frame(height: CrosswireLauncherTheme.Layout.playButtonHeight)
            .background(shape.fill(isEnabled ? CrosswireLauncherTheme.accent
                                             : CrosswireLauncherTheme.accent.opacity(0.3)))
            .shadow(color: isEnabled ? CrosswireLauncherTheme.accentGlow : .clear, radius: 14, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(CrosswireTheme.Motion.press, value: configuration.isPressed)
    }
}

struct LauncherSecondaryButtonStyle: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        configuration.label
            .foregroundStyle(destructive ? CrosswireTheme.danger : CrosswireLauncherTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(shape.fill(CrosswireLauncherTheme.surface))
            .overlay(shape.strokeBorder(CrosswireLauncherTheme.stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(CrosswireTheme.Motion.press, value: configuration.isPressed)
    }
}
