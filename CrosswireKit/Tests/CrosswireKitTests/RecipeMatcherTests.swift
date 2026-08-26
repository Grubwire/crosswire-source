//
//  RecipeMatcherTests.swift
//  CrosswireKitTests
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

import XCTest
@testable import CrosswireKit

/// Validates the recipe apply-path mechanism on the one proven-playable title
/// (SWG Legends), and proves the UNVALIDATED recipes are inert. This is the
/// non-GUI half of "validate the recipe system end-to-end on SWG": the matcher +
/// the override it carries. A full live install-flow run is a manual user check.
final class RecipeMatcherTests: XCTestCase {

    /// File-glob matching uses only `lastPathComponent`, so a non-existent path
    /// is fine (the SHA-256 branch is skipped — no validated recipe declares a hash).
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    // MARK: SWG (validated) — the matcher must find it and carry the known-good override.

    func testSWGInstallerNamesMatchSWGRecipe() {
        for name in ["SWGLegendsSetup.exe", "SWGLegendsSetup_4.4.exe",
                     "SwgClientSetup.exe", "SWGLegends-Setup-2.0.exe"] {
            let recipe = RecipeMatcher.match(installerURL: url(name))
            XCTAssertEqual(recipe?.id, "swg-legends", "expected SWG recipe for \(name)")
        }
    }

    func testSWGRecipeCarriesDwriteBuiltinOverride() {
        let recipe = RecipeMatcher.match(installerURL: url("SWGLegendsSetup.exe"))
        XCTAssertEqual(recipe?.dllOverrides["dwrite"], "builtin")
        XCTAssertEqual(recipe?.validated, true)
    }

    // MARK: UNVALIDATED recipes must NOT match (inert until proven).

    func testUnvalidatedRecipeNamesDoNotMatch() {
        // These globs exist in the catalog but on `validated: false` recipes,
        // so the matcher (which consults `active` only) must return nil.
        for name in ["LotroLauncher.exe", "DNDLauncher.exe", "swtor_setup.exe",
                     "homecoming.exe", "DAOrigins.exe"] {
            XCTAssertNil(RecipeMatcher.match(installerURL: url(name)),
                         "\(name) is an UNVALIDATED recipe — must not match")
        }
    }

    func testUnrelatedInstallerDoesNotMatch() {
        XCTAssertNil(RecipeMatcher.match(installerURL: url("SomeRandomApp.exe")))
    }

    // MARK: Catalog invariants.

    func testOnlySWGIsActive() {
        XCTAssertEqual(RecipeCatalog.active.map(\.id), ["swg-legends"])
        XCTAssertEqual(RecipeCatalog.all.count, 6)
        XCTAssertTrue(RecipeCatalog.all.filter { !$0.validated }.count == 5)
    }

    /// Recipes are Codable (forward path: load from JSON/R2). Round-trip must
    /// preserve `validated` so an externally-loaded recipe can't silently arrive "valid".
    func testRecipeCodableRoundTripPreservesValidated() throws {
        let data = try JSONEncoder().encode(RecipeCatalog.swgLegends)
        let decoded = try JSONDecoder().decode(Recipe.self, from: data)
        XCTAssertEqual(decoded.id, "swg-legends")
        XCTAssertTrue(decoded.validated)
        XCTAssertEqual(decoded.dllOverrides["dwrite"], "builtin")
    }
}
