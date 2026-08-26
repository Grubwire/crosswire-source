//
//  RuntimeDetectorTests.swift
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

/// Locks the curated import→verb mapping in `RuntimeDetector.detect(from:)`.
/// The mapping is what decides which runtimes a freshly-installed app is offered
/// before first launch; a careless edit to the rules would silently change the
/// install experience for every app. These tests exercise the pure seam
/// (`detect(from:)`) with DLL-name sets, so they need no PE fixture. Names are
/// lowercased, matching what `PEFile.importedDLLs` produces.
final class RuntimeDetectorTests: XCTestCase {

    private func verbs(_ imports: Set<String>) -> [String] {
        RuntimeDetector.detect(from: imports).map(\.verb)
    }

    // MARK: - Visual C++ redistributables

    func testVCRuntime140MapsToVcrun2019() {
        XCTAssertEqual(verbs(["vcruntime140.dll"]), ["vcrun2019"])
        XCTAssertEqual(verbs(["msvcp140.dll"]), ["vcrun2019"])
        XCTAssertEqual(verbs(["concrt140.dll"]), ["vcrun2019"])
    }

    func testOlderMSVCRuntimesMapToTheirVerbs() {
        XCTAssertEqual(verbs(["msvcr120.dll"]), ["vcrun2013"])
        XCTAssertEqual(verbs(["msvcr110.dll"]), ["vcrun2012"])
        XCTAssertEqual(verbs(["msvcr100.dll"]), ["vcrun2010"])
        XCTAssertEqual(verbs(["msvcr90.dll"]), ["vcrun2008"])
        XCTAssertEqual(verbs(["msvcr80.dll"]), ["vcrun2005"])
    }

    // MARK: - .NET

    func testDotNetLoaderMapsToDotnet48() {
        XCTAssertEqual(verbs(["mscoree.dll"]), ["dotnet48"])
        XCTAssertEqual(verbs(["mscorlib.dll"]), ["dotnet48"])
    }

    // MARK: - DirectX

    func testD3DX9PrefixMatchesAnyVersion() {
        XCTAssertEqual(verbs(["d3dx9_43.dll"]), ["d3dx9"])
        XCTAssertEqual(verbs(["d3dx9_30.dll"]), ["d3dx9"])
    }

    func testD3DCompilerExactMatch() {
        XCTAssertEqual(verbs(["d3dcompiler_47.dll"]), ["d3dcompiler_47"])
        // A different compiler version is not the redistributable we ship a verb for.
        XCTAssertEqual(verbs(["d3dcompiler_43.dll"]), [])
    }

    func testXactAndPhysxPrefixes() {
        XCTAssertEqual(verbs(["xactengine3_7.dll"]), ["xact"])
        XCTAssertEqual(verbs(["x3daudio1_7.dll"]), ["xact"])
        XCTAssertEqual(verbs(["physx_cooking.dll"]), ["physx"])
    }

    // MARK: - Dedup, ordering, triggering DLLs

    func testDuplicateVerbDeduplicatedWithSortedTriggers() {
        // Two d3dx9_* imports must collapse to a single d3dx9 offer, listing
        // both DLLs (sorted) as the trigger.
        let detected = RuntimeDetector.detect(from: ["d3dx9_43.dll", "d3dx9_30.dll"])
        XCTAssertEqual(detected.map(\.verb), ["d3dx9"])
        XCTAssertEqual(detected.first?.triggeringDLLs, ["d3dx9_30.dll", "d3dx9_43.dll"])
    }

    func testMultipleRuntimesPreserveRuleOrder() {
        // Rules walk in catalogue order; a modern game launcher importing both
        // VC++ and D3DX9 should surface vcrun2019 before d3dx9.
        XCTAssertEqual(
            verbs(["d3dx9_43.dll", "vcruntime140.dll"]),
            ["vcrun2019", "d3dx9"]
        )
    }

    // MARK: - Conservative guarantee (no over-detection)

    func testEmptyImportsDetectNothing() {
        XCTAssertEqual(verbs([]), [])
    }

    func testPlainWin32ImportsDetectNothing() {
        // Wine ships builtins for these; offering verbs for them would be the
        // over-detection the detector is explicitly designed to avoid.
        XCTAssertEqual(verbs(["kernel32.dll", "user32.dll", "ntdll.dll", "gdi32.dll", "msvcrt.dll"]), [])
    }
}
