//
//  RuntimePresets.swift
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

import Foundation

/// A single runtime/dependency the user can opt into. `verb` is the
/// winetricks verb name; `title` and `subtitle` are user-facing.
struct RuntimePreset: Identifiable, Hashable {
    let verb: String
    let title: String
    let subtitle: String
    var id: String { verb }
}

/// Curated catalogue of runtimes Windows apps commonly require. Ordered so
/// the default-selected essentials come first; the rest sit below for
/// users to pick from when an installer explicitly asks for something
/// niche.
enum RuntimeCatalogue {
    /// Default-checked when the user opens the install sheet.
    static let essentials: [RuntimePreset] = [
        RuntimePreset(
            verb: "corefonts",
            title: "Microsoft Core Fonts",
            subtitle: "Times New Roman, Arial, Verdana — many UI installers expect these."
        ),
        RuntimePreset(
            verb: "vcrun2019",
            title: "Visual C++ 2015–2022 Runtime",
            subtitle: "The most common dependency for modern Windows apps."
        ),
        RuntimePreset(
            verb: "vcrun2013",
            title: "Visual C++ 2013 Runtime",
            subtitle: "Required by many older apps and game launchers."
        ),
        RuntimePreset(
            verb: "dotnet48",
            title: ".NET Framework 4.8",
            subtitle: "Required by most managed desktop apps and installers."
        ),
        RuntimePreset(
            verb: "d3dx9",
            title: "DirectX 9 (D3DX9)",
            subtitle: "Used by classic games and many older 3D installers."
        )
    ]

    /// Additional opt-in items the user can layer on.
    static let optional: [RuntimePreset] = [
        RuntimePreset(
            verb: "vcrun2010",
            title: "Visual C++ 2010 Runtime",
            subtitle: "Legacy apps still ship against this."
        ),
        RuntimePreset(
            verb: "vcrun2008",
            title: "Visual C++ 2008 Runtime",
            subtitle: "Very old installers may still need it."
        ),
        RuntimePreset(
            verb: "dotnet472",
            title: ".NET Framework 4.7.2",
            subtitle: "A few apps explicitly target this older release."
        ),
        RuntimePreset(
            verb: "d3dcompiler_47",
            title: "D3D Compiler 47",
            subtitle: "Some launchers/UIs need this even when DXVK is on."
        ),
        RuntimePreset(
            verb: "xact",
            title: "XACT (DirectX Audio)",
            subtitle: "Audio runtime for many older games."
        ),
        RuntimePreset(
            verb: "physx",
            title: "NVIDIA PhysX Runtime",
            subtitle: "Physics middleware used by various games."
        )
    ]

    /// Full ordered list (essentials first, then optional extras).
    static var all: [RuntimePreset] { essentials + optional }
}
