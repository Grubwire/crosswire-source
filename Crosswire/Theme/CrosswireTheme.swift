//
//  CrosswireTheme.swift
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

/// Single source of truth for every color, gradient, surface, accent, and
/// typography token used in Crosswire's UI. Every hex value here was either
/// sampled directly from `AppIcon.icon/Assets/crosswire_512_2x_1024px__layered.png`
/// or chosen to complement those samples per the Brief 2 spec.
///
/// Rules of engagement:
/// 1. NEVER hardcode a hex value in a view. Reference these tokens.
/// 2. Surface tones step UP from the background gradient in deliberate
///    increments (8% / 12% / blue-tint 10%). Stay on the scale.
/// 3. The four tile colors (blue/green/yellow/red) come from the icon's
///    four-tile motif. Use them ONLY for monogram fallback tiles and the
///    occasional categorical accent — they're loud; don't paint with them.
/// 4. Accent (the icon's signature blue tile color) is the ONE interactive
///    color: primary buttons, focus rings, selected state. Resist diluting.
public enum CrosswireTheme {

    // MARK: - Backgrounds

    /// Vertical gradient for the app's main background. Slightly warmer at
    /// the top, deeper at the bottom — adds depth without lifting the
    /// overall tone. Sampled to complement the icon's deep-blue motif
    /// without competing with it (a blue background would clash with the
    /// blue tiles).
    public static let backgroundGradient = LinearGradient(
        colors: [Color(light: 0xEAEDF1, dark: 0x1A1D24),
                 Color(light: 0xE2E6EB, dark: 0x13161C)],
        startPoint: .top, endPoint: .bottom
    )

    /// Solid fallback when a gradient isn't appropriate (e.g. sheet headers
    /// where SwiftUI's material layering wants a single color).
    public static let backgroundSolid = Color(light: 0xE7EBEF, dark: 0x161A21)

    // MARK: - Surfaces (elevated layers on the background)

    /// The library region container — the contained surface the rows sit
    /// inside. One step above the background gradient. Branded hex (not a
    /// material): the persistent library shell stays opaque, not blurred.
    public static let surface = Color(light: 0xFAFBFD, dark: 0x1F232B)

    /// A library row at rest — its own surface, one step above the region
    /// container (`surface`).
    public static let rowSurface = Color(light: 0xFFFFFF, dark: 0x262B34)

    /// A library row / secondary button under cursor hover. A full step above
    /// `rowSurface` (matching the background→surface→rowSurface ramp), so the
    /// lift is perceptible on the dark surface rather than a near-invisible
    /// ~1.5% nudge. Preserves rowSurface's channel spacing — same tone, brighter.
    public static let rowSurfaceHover = Color(light: 0xEDF0F5, dark: 0x323740)

    /// The 1px hairline around the library region container. Same tone as a
    /// row at rest, used as a quiet edge against the page gradient.
    public static let regionBorder = Color(light: 0xD2D7DF, dark: 0x262B34)

    /// A row / card in selected / active state. Blue-tinted at 10% opacity
    /// so the row clearly belongs to the accent system but doesn't shout.
    public static let surfaceSelected = Color(hex: 0x418DF7).opacity(0.10)

    /// The thin stroke around a card / row, especially under hover and
    /// selection. Lower contrast than the surface tones; just a hint of
    /// edge to separate from background gradient.
    public static let surfaceStroke = Color.primary.opacity(0.08)

    /// The one disabled-state opacity for secondary controls and unavailable
    /// rows — dims the whole control. (The primary CTA is the exception: it
    /// dims its fill, not its label, so the white text stays legible.)
    public static let disabledOpacity: Double = 0.4

    // MARK: - Accent (THE Crosswire blue)

    /// The icon's signature tile-blue. Primary interactive color. Used for
    /// CTAs, focus rings, the selected-state tint, hover glints on Run
    /// buttons. Avoid using it as a fill on large areas — it loses its
    /// punch and starts to feel like brand-color spam.
    public static let accent = Color(hex: 0x418DF7)

    /// Slightly darker variant for pressed state on accent surfaces.
    public static let accentPressed = Color(hex: 0x2E78E0)

    /// Subtle hover tint for accent buttons (the +6% lift).
    public static let accentHover = Color(hex: 0x5A9DF8)

    // MARK: - Tile palette (for monogram fallbacks)

    /// The four icon-derived tile colors, cycled deterministically per entry
    /// in `colorForLibraryEntry(name:)`. Same entry always gets the same
    /// color. Don't reorder this array without checking all existing entry
    /// monograms — order is the deterministic input.
    public static let tilePalette: [Color] = [
        Color(hex: 0x418DF7),  // icon BLUE (top-left in the icon)
        Color(hex: 0x10BF86),  // icon GREEN (top-right)
        Color(hex: 0xEFA405),  // icon YELLOW (bottom-left)
        Color(hex: 0xF04E51)   // icon RED (bottom-right)
    ]

    /// Deterministic color for a library entry's monogram tile. Same input
    /// name always yields the same color across runs. Uses a tiny djb2-style
    /// hash so collisions are evenly distributed across the four-color
    /// palette without clustering.
    public static func colorForLibraryEntry(name: String) -> Color {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return tilePalette[0] }
        var hash: UInt32 = 5381
        for scalar in trimmed.unicodeScalars {
            hash = hash &* 33 &+ scalar.value
        }
        return tilePalette[Int(hash % UInt32(tilePalette.count))]
    }

    // MARK: - Text

    /// Primary text — entry names, headlines, body content. Native adaptive
    /// label color (near-black in light, near-white in dark).
    public static let textPrimary = Color(nsColor: .labelColor)

    /// Secondary text — metadata, "Last played" lines, captions. Adapts per
    /// appearance (macOS secondary label).
    public static let textSecondary = Color(nsColor: .secondaryLabelColor)

    /// Tertiary text — disabled, hints, footnotes. Adapts per appearance.
    public static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    /// On-accent text — sits on top of the accent blue, so it stays white in
    /// BOTH appearances (white reads fine against #418DF7; tested WCAG AA 16pt).
    public static let textOnAccent = Color.white

    // MARK: - Status semantics (separate from the tile palette)

    public static let success = Color(hex: 0x10BF86)
    public static let warning = Color(hex: 0xEFA405)
    public static let danger  = Color(hex: 0xF04E51)

    // MARK: - Typography

    public enum Typography {
        /// Window-title scale. The "Crosswire" wordmark in the header.
        public static let display: Font = .system(size: 30, weight: .bold, design: .default)

        /// Page / sheet titles ("About", per-app sheet titles).
        public static let title: Font = .system(size: 20, weight: .semibold, design: .default)

        /// Small-caps region label inside a contained surface ("LIBRARY").
        /// Pair with `.textCase(.uppercase)` + `.tracking(0.6)` + 60% opacity.
        public static let sectionHeader: Font = .system(size: 11, weight: .semibold, design: .default)

        /// Library entry name.
        public static let entryName: Font = .system(size: 16, weight: .semibold, design: .default)

        /// Library entry secondary line ("Last played 2h ago" / "Never launched").
        public static let entryMeta: Font = .system(size: 12, weight: .regular, design: .default)

        /// Body text in settings, sheets, alerts.
        public static let body: Font = .system(size: 14, weight: .regular, design: .default)

        /// Buttons (small / inline).
        public static let buttonLabel: Font = .system(size: 13, weight: .medium, design: .default)

        /// Primary CTA ("Install a Game or App").
        public static let buttonPrimary: Font = .system(size: 14, weight: .semibold, design: .default)
    }

    // MARK: - Motion

    public enum Motion {
        /// Hover transitions on rows + buttons. 150ms ease per the brief.
        public static let hover: Animation = .easeInOut(duration: 0.15)

        /// Press feedback on buttons. Snappier than hover.
        public static let press: Animation = .easeOut(duration: 0.10)

        /// Inline route transitions — the Settings + per-app detail panels
        /// sliding in over the library. One token so every route change uses
        /// the same curve instead of scattered `.easeInOut(duration: 0.2)`.
        public static let navigation: Animation = .easeInOut(duration: 0.2)
    }

    // MARK: - Layout

    public enum Layout {
        /// Library row height. 64pt per the brief.
        public static let libraryRowHeight: CGFloat = 64

        /// Monogram / icon tile side length inside a row. Slightly smaller
        /// than the row height so the row has breathing room.
        public static let libraryRowIconSide: CGFloat = 44

        /// Corner radius for tiles, cards, surfaces. Matches the icon's
        /// rounded-square language. Use ratio of side*0.22 for actual tiles
        /// (visually matches macOS icon corner-radius convention).
        public static let cornerRadius: CGFloat = 10

        /// Group card corner radius (settings sections etc).
        public static let groupCardRadius: CGFloat = 10

        /// Standard internal padding inside group cards and surfaces.
        public static let surfacePadding: CGFloat = 16
    }
}

// MARK: - Color hex initializer

public extension Color {
    /// Construct a `Color` from a packed RGB hex like `0xRRGGBB`. Used by
    /// `CrosswireTheme` so every color literal in this file reads as a hex
    /// rather than three normalized floats — easier to keep in sync with
    /// the icon's actual sampled colors.
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// Appearance-adaptive color: resolves to `light` in Aqua and `dark` in
    /// Dark Aqua. Lets a single token carry both the carefully-sampled dark
    /// surface and its designed light counterpart, so the whole UI follows the
    /// system appearance instead of being dark-only.
    init(light: UInt32, dark: UInt32) {
        let nsColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255.0,
                           green: Double((hex >> 8) & 0xFF) / 255.0,
                           blue: Double(hex & 0xFF) / 255.0,
                           alpha: 1.0)
        }
        self.init(nsColor: nsColor)
    }
}
