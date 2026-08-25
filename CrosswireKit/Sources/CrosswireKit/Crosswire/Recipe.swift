//
//  Recipe.swift
//  CrosswireKit
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

import Foundation
import CryptoKit

/// A per-app "recipe" — the known-good prerequisites + overrides for a specific
/// Windows title, applied automatically before its installer runs. Recipes are
/// DATA (like Lutris/Bottles), not code: this v1 ships an embedded catalog +
/// matcher; a future version can load JSON from the bundle or `download.grubwire.io`
/// (the type is `Codable` so that's a drop-in). Application reuses the existing
/// winetricks runner + `Wine.setDllOverrideIfAbsent`; see the install flow.
public struct Recipe: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// Winetricks verbs to install, in order (e.g. `vcrun2019`, `dotnet48`,
    /// `corefonts`; winetricks setting-verbs like `win10` are allowed too).
    public let prerequisites: [String]
    /// Wine DLL overrides to set (e.g. `["dwrite": "builtin"]`).
    public let dllOverrides: [String: String]
    /// Whether this title benefits from DXVK (D3D11+ games). Forward-looking
    /// hint — only takes effect once DXVK is bundled in the engine; the apply
    /// path does NOT flip the bottle's DXVK flag yet (no DLLs to use).
    public let useDXVK: Bool
    /// A user-facing heads-up surfaced for this title (e.g. launcher quirks like
    /// "first launch installs the Akamai downloader — let it finish").
    public let note: String?
    /// Whether this recipe has been confirmed end-to-end on a real install in
    /// Crosswire. ONLY validated recipes are eligible to match + apply
    /// (`RecipeMatcher` skips the rest). Inferred-from-Lutris recipes ship
    /// `false` — present as documented data, but inert until someone proves them.
    public let validated: Bool
    /// How to recognize this title's installer.
    public let signatures: [Signature]

    public struct Signature: Codable, Sendable {
        /// Exact SHA-256 (hex) of the installer, if known. Most precise.
        public let sha256: String?
        /// Case-insensitive filename glob (`*` = any run), e.g. `SWGLegendsSetup*.exe`.
        public let filenamePattern: String?

        public init(sha256: String? = nil, filenamePattern: String? = nil) {
            self.sha256 = sha256
            self.filenamePattern = filenamePattern
        }
    }

    public init(id: String, name: String, prerequisites: [String] = [],
                dllOverrides: [String: String] = [:], useDXVK: Bool = false,
                note: String? = nil, validated: Bool = false, signatures: [Signature]) {
        self.id = id
        self.name = name
        self.prerequisites = prerequisites
        self.dllOverrides = dllOverrides
        self.useDXVK = useDXVK
        self.note = note
        self.validated = validated
        self.signatures = signatures
    }
}

/// The embedded recipe catalog (v1). Recipes are pure DATA, so adding a verified
/// title is a list entry, not an engine change. Verb lists below are sourced
/// from Lutris install scripts (the authoritative per-game lists) except DDO,
/// which is inferred from LOTRO (same Standing Stone engine) — see
/// docs/specs/game-recipes-research.md for sources + confidence + the broader
/// findings (anti-cheat blockers, store-launcher games that this picked-installer
/// matching can't catch, and why DXVK hints don't apply until DXVK is bundled).
///
/// ⚠️ ONLY `swgLegends` is `validated`. The other five (LOTRO, DDO, SWTOR, City of
/// Heroes, Dragon Age: Origins) are UNVALIDATED — sourced from Lutris but never run
/// once in Crosswire. They ship `validated: false`, so `RecipeMatcher` will NOT
/// match or apply them (inert documented data). Do not promote one to `validated`
/// until it's confirmed end-to-end on a real install here.
public enum RecipeCatalog {
    /// Every catalog entry, validated or not (the full documented set).
    public static let all: [Recipe] = [swgLegends, lotro, ddo, swtor, cityOfHeroes, dragonAgeOrigins]
    /// Recipes eligible to match + apply — validated only. `RecipeMatcher` uses this.
    public static var active: [Recipe] { all.filter(\.validated) }

    /// SWG Legends: self-contained JavaFX launcher. Known-good override is
    /// `dwrite=builtin` (bundled MS dwrite crashes on the post-login CSS reapply;
    /// `JavaAppDetector` also applies it — setting it here up front is harmless).
    /// VALIDATED: the only proven-playable title; its matcher + override mechanism
    /// are covered by `RecipeMatcherTests`. (A full live install-flow run remains a
    /// manual user check — automation can't drive the installer wizard.)
    static let swgLegends = Recipe(
        id: "swg-legends",
        name: "Star Wars Galaxies Legends",
        dllOverrides: ["dwrite": "builtin"],
        validated: true,
        signatures: [
            .init(filenamePattern: "SWGLegends*Setup*.exe"),
            .init(filenamePattern: "SwgClientSetup*.exe"),
            .init(filenamePattern: "SWGLegendsSetup*.exe")
        ]
    )

    /// UNVALIDATED (validated: false → inert). LOTRO (Lutris script 10679). DX9/DX11.
    static let lotro = Recipe(
        id: "lotro",
        name: "Lord of the Rings Online",
        prerequisites: ["corefonts", "vcrun2017", "d3dcompiler_42", "d3dcompiler_43",
                        "d3dx11_42", "d3dx11_43", "winhttp", "win10"],
        useDXVK: true,
        note: "First launch installs the Akamai download manager — let it finish; "
            + "don’t auto-launch the game from the installer.",
        signatures: [.init(filenamePattern: "*lotro*.exe"),
                     .init(filenamePattern: "LotroLauncher*.exe")]
    )

    /// UNVALIDATED (validated: false → inert). DDO — inferred from LOTRO (same
    /// Standing Stone engine; its own Lutris script lists no verbs).
    static let ddo = Recipe(
        id: "ddo",
        name: "Dungeons & Dragons Online",
        prerequisites: ["corefonts", "vcrun2017", "d3dcompiler_42", "d3dcompiler_43",
                        "d3dx11_42", "d3dx11_43", "winhttp", "win10"],
        useDXVK: true,
        note: "First launch installs the Akamai download manager — let it finish.",
        signatures: [.init(filenamePattern: "*ddo*.exe"),
                     .init(filenamePattern: "DNDLauncher*.exe")]
    )

    /// UNVALIDATED (validated: false → inert). SWTOR (Lutris script 3262). DX9.
    static let swtor = Recipe(
        id: "swtor",
        name: "Star Wars: The Old Republic",
        prerequisites: ["d3dcompiler_47", "d3dx9_41"],
        note: "If the launcher hangs, disable BitRaider (set patch mode to SSN in "
            + "launcher.settings).",
        signatures: [.init(filenamePattern: "*swtor*.exe"),
                     .init(filenamePattern: "*setup*swtor*.exe")]
    )

    /// UNVALIDATED (validated: false → inert). City of Heroes: Homecoming (Lutris 24202). DX9.
    static let cityOfHeroes = Recipe(
        id: "city-of-heroes-homecoming",
        name: "City of Heroes: Homecoming",
        prerequisites: ["dotnet35", "corefonts", "dinput8", "tahoma"],
        note: "Press Alt+Enter if it starts full-screen.",
        signatures: [.init(filenamePattern: "*homecoming*.exe"),
                     .init(filenamePattern: "*cityofheroes*.exe")]
    )

    /// UNVALIDATED (validated: false → inert). Dragon Age: Origins (Lutris 22639).
    /// DX9; PhysX required; nvapi disabled to avoid the NVIDIA hack path.
    static let dragonAgeOrigins = Recipe(
        id: "dragon-age-origins",
        name: "Dragon Age: Origins",
        prerequisites: ["arial", "d3dcompiler_43", "d3dcompiler_47", "d3dx9", "physx"],
        dllOverrides: ["nvapi": "disabled", "nvapi64": "disabled"],
        note: "PhysX is required; performance depends on the Wine version.",
        signatures: [.init(filenamePattern: "*dragonage*origins*.exe"),
                     .init(filenamePattern: "DAOrigins*.exe")]
    )
}

/// Matches a picked installer to a recipe — exact SHA-256 wins, else a
/// case-insensitive filename glob. `nil` means no recipe (use the generic
/// PE-import runtime detection + defaults). Only `validated` recipes are
/// considered (`RecipeCatalog.active`); UNVALIDATED catalog entries never match.
public enum RecipeMatcher {
    public static func match(installerURL: URL) -> Recipe? {
        let name = installerURL.lastPathComponent

        // Filename globs first (cheap, no I/O).
        for recipe in RecipeCatalog.active {
            for signature in recipe.signatures {
                if let pattern = signature.filenamePattern, matches(name, glob: pattern) {
                    return recipe
                }
            }
        }

        // SHA-256 only if some recipe declares one (avoids hashing a multi-GB
        // installer when no recipe needs it).
        let needsHash = RecipeCatalog.active.contains { recipe in
            recipe.signatures.contains { $0.sha256 != nil }
        }
        guard needsHash, let hash = sha256Hex(of: installerURL) else { return nil }
        for recipe in RecipeCatalog.active {
            for signature in recipe.signatures where signature.sha256?.lowercased() == hash {
                return recipe
            }
        }
        return nil
    }

    private static func matches(_ name: String, glob: String) -> Bool {
        let pattern = "^" + NSRegularExpression.escapedPattern(for: glob)
            .replacingOccurrences(of: "\\*", with: ".*") + "$"
        return name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func sha256Hex(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
