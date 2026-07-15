//
//  CrosswireControls.swift
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

/// The single hover/press treatment for every custom button in the inline
/// panels (Settings + per-app detail), so the two panels feel like one system.
/// SwiftUI `ButtonStyle` can't hold `@State`, so hover lives in a nested view.
/// All transitions use the theme's 150ms hover / 100ms press easing.
struct CrosswireButtonStyle: ButtonStyle {
    enum Kind {
        /// Filled action chip (Show in Finder, Check Dependencies, Check for
        /// Updates…). Rests on `rowSurface`, lifts to `rowSurfaceHover`.
        case secondary
        /// Destructive action (Uninstall). Rests on `rowSurface`, hovers to a
        /// red tint with red text.
        case destructive
        /// Text/link affordance (back button, About links, maintenance rows).
        /// Transparent at rest, faint fill on hover.
        case plain
    }

    var kind: Kind = .secondary
    /// Expand to fill the available width (e.g. the detail view's equal-width
    /// action row, or full-width maintenance rows).
    var fillWidth: Bool = false
    /// Foreground override (used to tint `.plain` affordances accent-blue).
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        Styled(kind: kind, fillWidth: fillWidth, tint: tint, configuration: configuration)
    }

    private struct Styled: View {
        let kind: Kind
        let fillWidth: Bool
        let tint: Color?
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            let radius: CGFloat = kind == .plain ? 6 : 8
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            configuration.label
                .font(kind == .plain
                      ? CrosswireTheme.Typography.body
                      : CrosswireTheme.Typography.buttonLabel)
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .plain ? 9 : 14)
                .padding(.vertical, kind == .plain ? 5 : 9)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .background(shape.fill(background))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : CrosswireTheme.disabledOpacity)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovered = $0 && isEnabled }
                .animation(CrosswireTheme.Motion.hover, value: hovered)
                .animation(CrosswireTheme.Motion.press, value: configuration.isPressed)
        }

        private var foreground: Color {
            switch kind {
            case .destructive: return CrosswireTheme.danger
            default: return tint ?? CrosswireTheme.textPrimary
            }
        }

        private var background: Color {
            switch kind {
            case .secondary:
                return hovered ? CrosswireTheme.rowSurfaceHover : CrosswireTheme.rowSurface
            case .destructive:
                return hovered ? CrosswireTheme.danger.opacity(0.16) : CrosswireTheme.rowSurface
            case .plain:
                return hovered ? Color.primary.opacity(0.08) : Color.clear
            }
        }
    }
}

/// The one filled-accent call-to-action used across the app — the library
/// row's "Launch" pill, the detail view's prominent Launch button, and the
/// empty-state install button. One style so fill, hover, pressed, and disabled
/// behave identically; `size` only varies padding + corner radius (a compact
/// in-row pill vs. a prominent standalone button). The caller supplies the
/// label (icon + text) at whatever font suits the context.
struct PrimaryCTAButtonStyle: ButtonStyle {
    enum Size { case compact, prominent }
    var size: Size = .compact
    /// Expand to fill the available width (the detail view's full-width Launch).
    var fillWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(size: size, fillWidth: fillWidth, configuration: configuration)
    }

    private struct Styled: View {
        let size: Size
        let fillWidth: Bool
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            let radius: CGFloat = size == .prominent ? 9 : 6
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            configuration.label
                .foregroundStyle(CrosswireTheme.textOnAccent)
                .padding(.horizontal, size == .prominent ? 18 : 14)
                .padding(.vertical, size == .prominent ? 12 : 7)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .background(shape.fill(fill))
                .contentShape(shape)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovered = $0 && isEnabled }
                .animation(CrosswireTheme.Motion.hover, value: hovered)
                .animation(CrosswireTheme.Motion.press, value: configuration.isPressed)
        }

        // Disabled dims the FILL (not the whole control) so the white label
        // stays legible on a faded-blue pill.
        private var fill: Color {
            guard isEnabled else { return CrosswireTheme.accent.opacity(0.30) }
            return hovered ? CrosswireTheme.accentHover : CrosswireTheme.accent
        }
    }
}

/// The small square selection checkbox used by the runtime sheets — accent
/// fill + white check when selected, a quiet outline otherwise. One control so
/// both sheets render an identical, on-brand checkbox.
struct RuntimeCheckbox: View {
    let selected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(selected ? CrosswireTheme.accent : Color.primary.opacity(0.25),
                              lineWidth: 1.25)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selected ? CrosswireTheme.accent : Color.clear)
                )
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CrosswireTheme.textOnAccent)
            }
        }
        .frame(width: 16, height: 16)
    }
}

extension View {
    /// The shared small-caps section-header treatment (LIBRARY / SETTINGS /
    /// RECOMMENDED …): 11pt semibold, uppercased, tracked, secondary tone.
    /// One modifier so every section label matches instead of re-hardcoding
    /// the font + textCase + tracking at each call site.
    func cwSectionHeader() -> some View {
        self
            .font(CrosswireTheme.Typography.sectionHeader)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(CrosswireTheme.textSecondary)
    }
}

/// The shared "‹ Library" back bar at the top-left of every inline panel
/// (Settings + per-app detail). Both panels are slide-in navigation
/// destinations over the library, so they must exit identically.
struct InlinePanelBackBar: View {
    var action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Library")
                }
            }
            .buttonStyle(CrosswireButtonStyle(kind: .plain, tint: CrosswireTheme.accent))
            .keyboardShortcut(.cancelAction)
            .help("Back to Library")
            .accessibilityLabel("Back to Library")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
