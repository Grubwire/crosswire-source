//
//  LibraryViewMode.swift
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

/// The two ways to browse the library.
///
/// A third "List" mode was drawn and dropped: once Sidebar used compact rows
/// instead of large tiles, it did everything List would have, at higher
/// density, with a permanent detail pane List didn't have. Two real choices
/// beat three where one is redundant.
enum LibraryViewMode: String, CaseIterable {
    /// Full-width tiles, large art. Selecting one slides `EntryDetailView` in
    /// over the grid — the same overlay mechanism the app has always used.
    case grid
    /// Compact rows in a rail, `LibraryDetailPane` permanently visible beside
    /// them. The direction doc's "hero always visible" model.
    case sidebar

    static let defaultsKey = "libraryViewMode"

    /// Sidebar by default: the hero and the dominant Play stay on screen,
    /// which is the closest match to the confirmed Battle.net direction.
    static let fallback: LibraryViewMode = .sidebar

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .sidebar: return "sidebar.left"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .grid: return "Grid view"
        case .sidebar: return "Sidebar view"
        }
    }
}

/// Toolbar segmented control for `LibraryViewMode`. Its own view rather than
/// an inline `Picker` so the icon-only segmented look and the persisted
/// binding live in one place.
struct LibraryViewModeSwitcher: View {
    @AppStorage(LibraryViewMode.defaultsKey) private var raw = LibraryViewMode.fallback.rawValue

    private var mode: LibraryViewMode {
        LibraryViewMode(rawValue: raw) ?? .fallback
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LibraryViewMode.allCases, id: \.self) { option in
                segment(for: option)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(CrosswireTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(CrosswireTheme.surfaceStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func segment(for option: LibraryViewMode) -> some View {
        let isSelected = mode == option
        let fill: Color = isSelected ? CrosswireTheme.accent : Color.clear
        let foreground: Color = isSelected ? CrosswireTheme.textOnAccent : CrosswireTheme.textSecondary
        Button {
            raw = option.rawValue
        } label: {
            Image(systemName: option.icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 20)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill))
        .foregroundStyle(foreground)
        .help(option.accessibilityLabel)
        .accessibilityLabel(option.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
