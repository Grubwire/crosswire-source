//
//  LibraryRow.swift
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

/// One entry in the Sidebar mode rail: small art, name, meta. No Launch
/// button — Mail/Outlook-style, where a row's job is to fill the pane beside
/// it, and the pane's dominant Play is where launching actually happens.
/// Double-click still launches directly, the same shortcut `GameTile` offers.
struct LibraryRow: View {
    @ObservedObject var bottle: Bottle
    let isSelected: Bool
    let isListFocused: Bool
    let actions: BoundBottleActions
    let onSelect: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            TileArtView(bottle: bottle)
                .frame(width: 34, height: 34)
                .saturation(bottle.isAvailable ? 1 : 0)
            VStack(alignment: .leading, spacing: 1) {
                // Plain .regular system font. Confirmed against the real
                // window, not a screenshot: both .semibold and .medium read
                // as too heavy here, white text on this dark a background
                // amplifies weight (light-on-dark optical bloom) well past
                // what the same weight looks like on a light background.
                // Condensed is also wrong at this size regardless of weight —
                // that display type is tuned for large headers, not a 34pt
                // dense row.
                Text(bottle.displayName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(CrosswireLauncherTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(metaLine)
                    .font(CrosswireLauncherTheme.Typography.tileMeta)
                    .foregroundStyle(CrosswireLauncherTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if bottle.inFlight {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? (isListFocused ? 1.5 : 1) : 0)
        )
        .contentShape(Rectangle())
        .opacity(bottle.isAvailable ? 1 : CrosswireTheme.disabledOpacity)
        .onHover { hovered = $0 }
        .animation(CrosswireTheme.Motion.hover, value: hovered)
        .animation(CrosswireTheme.Motion.hover, value: isSelected)
        .onTapGesture(count: 2) { if bottle.canLaunch { actions.run() } }
        .onTapGesture { onSelect() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(bottle.displayName)
        .accessibilityValue(bottle.librarySecondaryLine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var metaLine: String {
        bottle.isAvailable ? bottle.librarySecondaryLine : "Unavailable"
    }

    private var fill: Color {
        if isSelected { return CrosswireLauncherTheme.surfaceSelected }
        return hovered ? CrosswireLauncherTheme.surfaceHover : Color.clear
    }

    private var borderColor: Color {
        isListFocused
            ? CrosswireLauncherTheme.strokeSelected
            : CrosswireLauncherTheme.strokeSelected.opacity(0.55)
    }
}
