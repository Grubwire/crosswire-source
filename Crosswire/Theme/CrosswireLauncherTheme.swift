//
//  CrosswireLauncherTheme.swift
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

/// Tokens for the Battle.net/Riot-style launcher surfaces, per
/// `docs/specs/visual-design-direction.md`.
///
/// Separate from `CrosswireTheme` because the launcher is its own design
/// language: a deeper, cooler, higher-contrast surface scale than the settings
/// chrome, with hero art and cover tiles to sit on it. `CrosswireTheme` keeps
/// serving Settings, About and the setup flow.
///
/// Both files are appearance-adaptive through `Color(light:dark:)`, which
/// resolves against the SwiftUI environment. `AppearancePreference` drives that
/// environment via a single `.preferredColorScheme(_:)` at the window root, so
/// the user's Dark / Light / System choice reaches every token here without any
/// view needing to consult it.
///
/// Rules of engagement (in addition to the four in `CrosswireTheme`):
/// 5. The background scale steps in deliberate increments — each level is a
///    perceptible lift on the one below, not a 1% nudge. Stay on the scale.
///    Elevation moves *toward* the page's extreme: lighter in Light, lighter in
///    Dark. Hover is the exception and moves against it, so a hovered card
///    reads as pressed-into rather than floating.
/// 6. The hero scrims and `textOnArt` are deliberately NOT adaptive. They sit on
///    rendered banner art, and `BannerImagePipeline` bakes a dark treatment into
///    every image it produces (42% ambient darkening plus a bottom scrim fading
///    to 78% black). Art is therefore dark in both appearances, so anything
///    layered on it stays calibrated for dark. Flipping these with the
///    appearance would put dark text on dark art.
public enum CrosswireLauncherTheme {

    // MARK: - Background scale (page → most elevated)

    /// The page itself. Cool-shifted rather than neutral grey — this is what
    /// makes the whole surface read cool instead of muddy once art sits on it.
    public static let backgroundBase = Color(light: 0xE7EBF1, dark: 0x0A0D13)

    /// A raised region on the page — the sidebar column, a shelf container.
    /// One step above `backgroundBase`.
    public static let backgroundRaised = Color(light: 0xEFF2F7, dark: 0x11151E)

    /// A card / tile at rest. Two steps above base.
    public static let surface = Color(light: 0xF8FAFC, dark: 0x181D28)

    /// A card / tile elevated by context (an open panel, a foreground sheet).
    public static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x212836)

    /// A tile / row under cursor hover. A full perceptible step from `surface`,
    /// matching the ramp spacing rather than a faint tint. Moves against the
    /// elevation direction (see rule 5).
    public static let surfaceHover = Color(light: 0xE9EDF4, dark: 0x2A3242)

    /// Selected tile fill. Accent-tinted so selection reads as part of the
    /// accent system, at low enough opacity to sit under cover art. The tint is
    /// the same blue in both appearances; only what it composites over changes.
    public static let surfaceSelected = Color(hex: 0x418DF7).opacity(0.16)

    /// Hairline stroke between surfaces. Low contrast — an edge, not a line.
    public static let stroke = Color(light: 0xD3DAE4, dark: 0x333C4D)

    /// Stroke on a selected tile. Full accent, thin.
    public static let strokeSelected = Color(hex: 0x418DF7)

    // MARK: - Accent

    /// The brand blue, unchanged from `CrosswireTheme.accent` — the launcher
    /// does not get its own brand color, only its own surfaces.
    public static let accent = Color(hex: 0x418DF7)

    /// The accent pushed for contrast against the current page: darker in
    /// Light, brighter in Dark. Use where plain `accent` loses legibility at
    /// small sizes, not as a second brand color.
    public static let accentBright = Color(light: 0x2C74DB, dark: 0x5FA8FF)

    /// Pressed state on accent fills.
    public static let accentPressed = Color(light: 0x2560BE, dark: 0x2E78E0)

    /// Halo behind the dominant Play control. Used as a shadow / glow color,
    /// never as a fill. Reads strongly on dark and softly on light, which is
    /// the correct behavior for a glow.
    public static let accentGlow = Color(hex: 0x418DF7).opacity(0.45)

    // MARK: - Text

    /// Primary text on launcher surfaces. Cool-shifted at both ends so it does
    /// not read warm against the cool background scale.
    public static let textPrimary = Color(light: 0x14181F, dark: 0xF2F5FA)

    /// Metadata, secondary lines, captions.
    public static let textSecondary = Color(light: 0x5A6472, dark: 0xA3AEC2)

    /// Hints, disabled labels, footnotes.
    public static let textTertiary = Color(light: 0x8A94A3, dark: 0x6B7688)

    /// Text sitting directly on the accent fill. White in both appearances —
    /// the fill it sits on does not change.
    public static let textOnAccent = Color.white

    /// Text sitting directly on rendered banner art. Fixed light: art is dark
    /// in both appearances (see rule 6).
    public static let textOnArt = Color(hex: 0xF2F5FA)

    // MARK: - Hero scrims (fixed dark — see rule 6)

    /// Bottom-up scrim laid over hero banner art so title text stays legible
    /// regardless of what the art underneath looks like. Clear at the top,
    /// near-opaque at the bottom edge.
    public static let heroScrim = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x0A0D13, opacity: 0.00), location: 0.00),
            .init(color: Color(hex: 0x0A0D13, opacity: 0.55), location: 0.55),
            .init(color: Color(hex: 0x0A0D13, opacity: 0.95), location: 1.00)
        ],
        startPoint: .top, endPoint: .bottom
    )

    /// Left-to-right scrim for heroes that place text on the leading edge with
    /// art bleeding off the trailing edge.
    ///
    /// KNOWN WEAK: at the 0.50 stop this is only 40% opaque, and during the
    /// Phase 0 review busy art read through the title letterforms. Steepen the
    /// falloff or move the text further into the dark before Phase 2 relies on
    /// it. Tracked as a follow-up.
    public static let heroScrimLeading = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x0A0D13, opacity: 0.92), location: 0.00),
            .init(color: Color(hex: 0x0A0D13, opacity: 0.40), location: 0.50),
            .init(color: Color(hex: 0x0A0D13, opacity: 0.00), location: 1.00)
        ],
        startPoint: .leading, endPoint: .trailing
    )

    /// Fill shown in a tile or hero while art is still resolving, and behind
    /// art with transparency.
    public static let artPlaceholder = Color(light: 0xDDE3EC, dark: 0x141A24)

    // MARK: - Typography

    /// Bold condensed display type for titles and headers, per the direction
    /// doc. `.width(.condensed)` is macOS 13+; the app floor is 14.0, so this
    /// resolves to real condensed metrics rather than a transform of the
    /// default width.
    public enum Typography {
        /// The hero title — the selected game's name over its banner.
        public static let heroTitle: Font = .system(size: 40, weight: .bold).width(.condensed)

        /// A shelf / sidebar section header ("LIBRARY", "RECENTLY PLAYED").
        /// Pair with `.textCase(.uppercase)` + `.tracking(1.2)`.
        public static let shelfHeader: Font = .system(size: 12, weight: .semibold).width(.condensed)

        /// A game name on a shelf tile.
        public static let tileTitle: Font = .system(size: 15, weight: .semibold).width(.condensed)

        /// A tile's secondary line ("Last played 2h ago").
        public static let tileMeta: Font = .system(size: 11, weight: .regular)

        /// The dominant Play control's label. Oversized per the direction's
        /// "one dominant Play action" rule.
        public static let playLabel: Font = .system(size: 17, weight: .bold).width(.condensed)
    }

    // MARK: - Layout

    public enum Layout {
        /// Shelf tile footprint. 3:4 portrait, the cover-art proportion
        /// Battle.net and Riot use for library tiles.
        ///
        /// UNUSED as of Phase 1: the sidebar uses square art (see
        /// `sidebarTileArtSide`) because the art source is a square extracted
        /// icon, which leaves ~25% of a 3:4 frame empty. Kept for a future grid
        /// view built on real cover art.
        public static let tileWidth: CGFloat = 168
        public static let tileHeight: CGFloat = 224

        /// Gap between tiles in a shelf, both axes.
        public static let tileSpacing: CGFloat = 16

        // MARK: Sidebar

        /// Width of the library rail. With the fixed 1080pt window this leaves
        /// 840pt for the hero pane.
        ///
        /// 220 originally, widened to 240 once real app names showed up —
        /// "SWG Legends Launcher" was truncating to "SWG Legends Laun…" in
        /// `LibraryRow`'s compact layout. `LibraryRow` sizes its own art and
        /// padding directly rather than through the tokens below (those were
        /// sized for a large-tile rail that got replaced by compact rows; see
        /// `sidebarTileArtSide`'s note).
        public static let sidebarWidth: CGFloat = 240

        /// Side of a tile's square art plate. Square because the art source is
        /// an extracted icon, which is square — a 3:4 frame would be a quarter
        /// empty.
        ///
        /// UNUSED as of the compact-row rail (`LibraryRow`) — this sized a
        /// large-tile rail design that got replaced mid-session once real app
        /// names made the density problem obvious. Kept for a possible future
        /// large-tile mode; `GameTile` (Grid mode) uses its own sizing too.
        public static let sidebarTileArtSide: CGFloat = 140

        /// Height reserved beneath the art for the name and meta lines.
        public static let sidebarTileLabelHeight: CGFloat = 36

        /// The per-tile Launch control. Compact next to the hero's dominant
        /// Play, which stays the primary action for the selected entry.
        public static let sidebarTileButtonHeight: CGFloat = 26

        /// Gap between tiles in the rail.
        public static let sidebarTileSpacing: CGFloat = 12

        /// Padding around the tile column inside the rail.
        public static let sidebarPadding: CGFloat = 24

        /// Tile corner radius. Tighter than `CrosswireTheme.Layout.cornerRadius`
        /// — cover art wants a crisper edge than a settings card does.
        public static let tileCornerRadius: CGFloat = 8

        /// Padding inside the shelf container, around the tile field.
        public static let shelfPadding: CGFloat = 24

        /// Hero banner aspect ratio (width / height).
        ///
        /// This is the hero's own layout choice, NOT a constraint imposed by
        /// `BannerRenderer` — that takes an arbitrary `CGSize` and composes
        /// proportionally to whatever it is handed.
        public static let heroAspectRatio: CGFloat = 16.0 / 9.0

        /// Minimum hero height, so the hero stays substantial in a narrow
        /// window instead of collapsing to a strip.
        public static let heroMinHeight: CGFloat = 260

        /// The dominant Play control. Oversized on purpose — this is the
        /// "everything else recedes" rule expressed as a number.
        public static let playButtonHeight: CGFloat = 48
        public static let playButtonMinWidth: CGFloat = 180
        public static let playButtonCornerRadius: CGFloat = 6
    }
}
