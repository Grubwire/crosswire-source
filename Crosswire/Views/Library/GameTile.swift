//
//  GameTile.swift
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

/// One entry in the library rail: art plate, name, meta line, Launch button.
///
/// Two separate targets on purpose. Launch runs the entry straight away;
/// anywhere else on the tile selects it, which is what fills the detail pane
/// beside the rail with that entry's settings and Advanced section. The hero's
/// larger Play remains the dominant action for whatever is selected, but a
/// per-tile Launch means running something you are not currently looking at
/// costs one click instead of two.
///
/// The context menu is shorter than the old row's seven items. "Show Details"
/// is meaningless when the detail pane is always visible, and dependencies and
/// diagnostics live in that pane, which also means this view presents no sheet
/// of its own — a `.sheet` on a lazily-realised row is a known source of
/// presentation bugs when the row recycles.
struct GameTile: View {
    @ObservedObject var bottle: Bottle
    let isSelected: Bool
    /// Whether the rail itself has keyboard focus. Selection stays visible when
    /// it does not, just quieter — the hero always reflects the selection, so
    /// dropping the highlight entirely would orphan the pane.
    let isListFocused: Bool
    let actions: BoundBottleActions
    /// Set to ask the detail pane to begin an inline rename of this entry.
    let onRequestRename: () -> Void
    let onSelect: () -> Void

    @State private var hovered = false
    @State private var showProgramPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            art
            labels
            launchButton
        }
        .padding(10)
        // No fixed width: the grid cell decides, so every tile in a row is the
        // same size and the row fills the pane evenly rather than leaving a
        // gutter down one side.
        .frame(maxWidth: .infinity)
        .background(background)
        .overlay(border)
        .contentShape(RoundedRectangle(cornerRadius: shapeRadius, style: .continuous))
        .opacity(bottle.isAvailable ? 1 : CrosswireTheme.disabledOpacity)
        .scaleEffect(hovered && !isSelected ? 1.02 : 1)
        .onHover { hovered = $0 }
        .animation(CrosswireTheme.Motion.hover, value: hovered)
        .animation(CrosswireTheme.Motion.hover, value: isSelected)
        // Single click selects. Double click launches. Declared first so it
        // wins the race for a two-tap sequence. The Launch button below is an
        // interactive child and swallows its own clicks, so neither fires when
        // the user is aiming at it.
        .onTapGesture(count: 2) { if bottle.canLaunch { actions.run() } }
        .onTapGesture { onSelect() }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(bottle.displayName)
        .accessibilityValue(bottle.librarySecondaryLine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .onAppear {
            if bottle.isAvailable, bottle.programs.isEmpty {
                bottle.updateInstalledPrograms()
            }
        }
    }

    // MARK: - Pieces

    private var art: some View {
        TileArtView(bottle: bottle)
            .saturation(bottle.isAvailable ? 1 : 0)
            .overlay(alignment: .bottomLeading) {
                if bottle.inFlight {
                    ProgressView()
                        .controlSize(.small)
                        .padding(6)
                }
            }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(bottle.displayName)
                .font(CrosswireLauncherTheme.Typography.tileTitle)
                .foregroundStyle(CrosswireLauncherTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(metaLine)
                .font(CrosswireLauncherTheme.Typography.tileMeta)
                .foregroundStyle(CrosswireLauncherTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(height: CrosswireLauncherTheme.Layout.sidebarTileLabelHeight,
               alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaLine: String {
        bottle.isAvailable ? bottle.librarySecondaryLine : "Unavailable"
    }

    /// Runs the entry directly. With several launchers it opens the picker
    /// instead of guessing, matching what the old row did.
    @ViewBuilder
    private var launchButton: some View {
        let multiple = bottle.userVisiblePrograms.count > 1
        Button {
            if multiple {
                showProgramPicker = true
            } else {
                actions.run()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Launch")
                    .font(CrosswireLauncherTheme.Typography.tileTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryCTAButtonStyle(size: .compact, fillWidth: true))
        .disabled(!bottle.canLaunch)
        .frame(height: CrosswireLauncherTheme.Layout.sidebarTileButtonHeight)
        // Stops the tile's select/double-click gestures from firing underneath
        // a deliberate press on the button.
        .onTapGesture {}
        .popover(isPresented: $showProgramPicker, arrowEdge: .trailing) {
            ProgramPickerList(programs: bottle.userVisiblePrograms) { program in
                showProgramPicker = false
                actions.runProgram(program)
            }
        }
        .help("Launch \(bottle.displayName)")
        .accessibilityLabel("Launch \(bottle.displayName)")
    }

    // MARK: - Selection styling

    private var shapeRadius: CGFloat {
        CrosswireLauncherTheme.Layout.tileCornerRadius + 4
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: shapeRadius, style: .continuous)
            .fill(fill)
    }

    private var fill: Color {
        if isSelected { return CrosswireLauncherTheme.surfaceSelected }
        return hovered ? CrosswireLauncherTheme.surfaceHover : CrosswireLauncherTheme.surface
    }

    /// Selected-and-focused gets the full accent edge; selected-but-unfocused
    /// keeps the same shape at reduced strength, the standard macOS treatment
    /// for a list that has lost focus without losing its selection.
    private var border: some View {
        RoundedRectangle(cornerRadius: shapeRadius, style: .continuous)
            .strokeBorder(borderColor, lineWidth: isSelected ? (isListFocused ? 2 : 1.5) : 1)
    }

    private var borderColor: Color {
        guard isSelected else { return CrosswireLauncherTheme.stroke }
        return isListFocused
            ? CrosswireLauncherTheme.strokeSelected
            : CrosswireLauncherTheme.strokeSelected.opacity(0.55)
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        Button { actions.run() } label: { Label("Launch", systemImage: "play.fill") }
            .disabled(!bottle.canLaunch)
        Button { onRequestRename() } label: { Label("Rename", systemImage: "pencil") }
        Button { bottle.revealInFinder() } label: { Label("Show in Finder", systemImage: "folder") }
        Divider()
        Button(role: .destructive) {
            actions.uninstall()
        } label: {
            Label("Uninstall…", systemImage: "trash")
        }
    }
}
