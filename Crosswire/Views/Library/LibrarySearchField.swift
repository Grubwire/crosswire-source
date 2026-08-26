//
//  LibrarySearchField.swift
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

/// The library search field, styled with the dark launcher tokens. One
/// definition shared by Grid mode's header and Sidebar mode's rail so the
/// control looks identical in both rather than drifting into two lookalikes.
struct LibrarySearchField: View {
    @Binding var text: String
    var placeholder: String = "Search your library…"

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(CrosswireLauncherTheme.textTertiary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(CrosswireLauncherTheme.textPrimary)
                .focused($focused)
                .accessibilityLabel("Search your library")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CrosswireLauncherTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(focused ? CrosswireLauncherTheme.accent.opacity(0.55)
                                      : CrosswireLauncherTheme.stroke, lineWidth: 1)
        )
        .animation(CrosswireTheme.Motion.hover, value: focused)
    }
}
