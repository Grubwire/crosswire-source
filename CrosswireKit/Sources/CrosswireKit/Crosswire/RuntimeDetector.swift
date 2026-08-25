//
//  RuntimeDetector.swift
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

/// A runtime an exe needs that Crosswire can install via winetricks before
/// the first launch. Returned by `RuntimeDetector.detect(...)`.
public struct DetectedRuntime: Identifiable, Hashable, Sendable {
    /// Winetricks verb (e.g. `vcrun2019`, `dotnet48`).
    public let verb: String
    /// Human-readable label for the install sheet.
    public let title: String
    /// Lowercased DLL names that triggered detection (for the "more details"
    /// disclosure in the UI).
    public let triggeringDLLs: [String]
    public var id: String { verb }
}

/// Static analyzer that maps an .exe's PE imports to the winetricks verbs
/// the user needs to install before launching it. Conservative on purpose —
/// over-detection produces a worse first-run experience (long install for
/// runtimes you don't actually need) than under-detection.
///
/// The mapping is intentionally hardcoded, not data-driven. Wine ships
/// builtins for almost every Windows API a normal exe uses; we only want
/// to flag the runtimes the user genuinely has to download because they're
/// redistributable and Microsoft/Adobe/etc. distributes them separately
/// from Windows itself.
public enum RuntimeDetector {

    /// Inspect a PE file's import table and return the runtimes Crosswire
    /// should offer to install. Returns an empty array for exes that need
    /// nothing (Notepad++, most portable apps, self-contained Java
    /// launchers).
    public static func detect(at url: URL) -> [DetectedRuntime] {
        guard let peFile = try? PEFile(url: url) else { return [] }
        let imports = Set(peFile.importedDLLs)
        return detect(from: imports)
    }

    /// Pure-function variant for unit tests / probing.
    public static func detect(from imports: Set<String>) -> [DetectedRuntime] {
        // Walk the rules in order so a fixed UI ordering falls out for free.
        var detected: [DetectedRuntime] = []
        for rule in rules {
            let matches = imports.filter { rule.dllPredicate($0) }
            guard !matches.isEmpty else { continue }
            detected.append(DetectedRuntime(
                verb: rule.verb,
                title: rule.title,
                triggeringDLLs: matches.sorted()
            ))
        }
        // Deduplicate verbs (multiple rules can map to the same verb, e.g.
        // d3dx9_30 + d3dx9_43 both want d3dx9). Keep first occurrence.
        var seen = Set<String>()
        return detected.filter { seen.insert($0.verb).inserted }
    }

    // MARK: - Rules

    private struct Rule: Sendable {
        let verb: String
        let title: String
        let dllPredicate: @Sendable (String) -> Bool
    }

    /// Curated catalogue. Each rule maps a DLL pattern to a winetricks verb.
    /// Order matters — earlier matches win when multiple rules would fire
    /// for the same exe (after dedup).
    private static let rules: [Rule] = [
        // --- Visual C++ Redistributables ---
        // The newest VC++ runtime covers 2015..2022. We pick the most recent
        // verb when any of vcruntime140 / msvcp140 / ucrtbase shows up,
        // which is what nearly all modern apps want.
        Rule(verb: "vcrun2019", title: "Microsoft Visual C++ 2015–2022",
             dllPredicate: { name in
                 name == "vcruntime140.dll" || name == "vcruntime140_1.dll"
                 || name == "msvcp140.dll" || name == "msvcp140_1.dll"
                 || name == "msvcp140_2.dll" || name == "concrt140.dll"
             }),
        Rule(verb: "vcrun2013", title: "Microsoft Visual C++ 2013",
             dllPredicate: { name in
                 name == "msvcr120.dll" || name == "msvcp120.dll"
             }),
        Rule(verb: "vcrun2012", title: "Microsoft Visual C++ 2012",
             dllPredicate: { name in
                 name == "msvcr110.dll" || name == "msvcp110.dll"
             }),
        Rule(verb: "vcrun2010", title: "Microsoft Visual C++ 2010",
             dllPredicate: { name in
                 name == "msvcr100.dll" || name == "msvcp100.dll"
             }),
        Rule(verb: "vcrun2008", title: "Microsoft Visual C++ 2008",
             dllPredicate: { name in
                 name == "msvcr90.dll" || name == "msvcp90.dll"
             }),
        Rule(verb: "vcrun2005", title: "Microsoft Visual C++ 2005",
             dllPredicate: { name in
                 name == "msvcr80.dll" || name == "msvcp80.dll"
             }),

        // --- .NET Framework ---
        // mscoree.dll is the .NET runtime loader. mscorlib is the BCL.
        // We pick .NET 4.8 as a safe-default modern version. Apps that
        // truly need .NET 2.0/3.5 (rare in 2026) will fail loudly and the
        // user can pick that explicitly via the manual sheet.
        Rule(verb: "dotnet48", title: ".NET Framework 4.8",
             dllPredicate: { name in
                 name == "mscoree.dll" || name == "mscorlib.dll"
                 || name == "mscoreei.dll" || name == "system.dll"
             }),

        // --- DirectX runtime DLLs that need redistribution ---
        // d3dx9_*.dll is the legacy D3DX9 redistributable. Wine ships its
        // own d3d11/d3d12/d3d9 implementations, so those don't need verbs.
        Rule(verb: "d3dx9", title: "DirectX 9 (D3DX9)",
             dllPredicate: { $0.hasPrefix("d3dx9_") && $0.hasSuffix(".dll") }),
        Rule(verb: "d3dx10", title: "DirectX 10 (D3DX10)",
             dllPredicate: { $0.hasPrefix("d3dx10_") && $0.hasSuffix(".dll") }),
        Rule(verb: "d3dx11_43", title: "DirectX 11 (D3DX11 43)",
             dllPredicate: { $0 == "d3dx11_43.dll" }),
        // D3DCompiler is a separate redist that some game launchers explicitly
        // import even when DXVK provides d3d11 itself.
        Rule(verb: "d3dcompiler_47", title: "D3D Compiler 47",
             dllPredicate: { $0 == "d3dcompiler_47.dll" }),
        // XACT audio runtime — used by older XNA games and some launchers.
        Rule(verb: "xact", title: "XACT (DirectX Audio)",
             dllPredicate: { name in
                 name.hasPrefix("xactengine") && name.hasSuffix(".dll")
                 || name == "x3daudio1_7.dll"
             }),

        // --- PhysX ---
        Rule(verb: "physx", title: "NVIDIA PhysX Runtime",
             dllPredicate: { name in
                 name.hasPrefix("physx") && name.hasSuffix(".dll")
                 || name.hasPrefix("nvpmapi") && name.hasSuffix(".dll")
             })
    ]
}
