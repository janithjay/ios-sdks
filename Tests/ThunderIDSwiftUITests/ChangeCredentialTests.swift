// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

final class ChangeCredentialTests: XCTestCase {
    // MARK: - evaluateCredentialForm

    func testInvalidWhenNewValueEmpty() {
        let result = evaluateCredentialForm(current: "old", new: "", confirm: "", regex: nil)
        XCTAssertFalse(result.isValid)
    }

    func testInvalidWhenConfirmMismatch() {
        let result = evaluateCredentialForm(current: "old", new: "n3wValue!", confirm: "typo", regex: nil)
        XCTAssertFalse(result.confirmMatches)
        XCTAssertFalse(result.isValid)
    }

    func testInvalidWhenReusingCurrentValue() {
        let result = evaluateCredentialForm(current: "same", new: "same", confirm: "same", regex: nil)
        XCTAssertTrue(result.reusesCurrent)
        XCTAssertFalse(result.isValid)
    }

    func testValidWithNoPolicy() {
        let result = evaluateCredentialForm(current: "old", new: "n3wValue!", confirm: "n3wValue!", regex: nil)
        XCTAssertFalse(result.patternChecked)
        XCTAssertTrue(result.isValid)
    }

    func testAppliesRegexPolicy() {
        let regex = "^.{8,}$"
        let short = evaluateCredentialForm(current: "old", new: "short", confirm: "short", regex: regex)
        XCTAssertTrue(short.patternChecked)
        XCTAssertFalse(short.patternPassed)
        XCTAssertFalse(short.isValid)

        let long = evaluateCredentialForm(current: "old", new: "longEnough1", confirm: "longEnough1", regex: regex)
        XCTAssertTrue(long.patternPassed)
        XCTAssertTrue(long.isValid)
    }

    func testTreatsUncompilableRegexAsPassing() {
        let result = evaluateCredentialForm(current: "old", new: "anything", confirm: "anything", regex: "([)")
        XCTAssertTrue(result.patternPassed)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - mapCredentialError

    func testMapsRejectedCurrentValueToCurrentField() {
        let error = ThunderIDError(code: .invalidCredential, message: "The current value is incorrect")
        XCTAssertEqual(mapCredentialError(error), .current)
    }

    func testMapsBadRequestToNewField() {
        let error = ThunderIDError(code: .invalidInput, message: "Bad request")
        XCTAssertEqual(mapCredentialError(error), .new)
    }

    func testMapsOtherFailuresToFormLevel() {
        XCTAssertEqual(mapCredentialError(ThunderIDError(code: .serverError, message: "boom")), .form)
        XCTAssertEqual(mapCredentialError(NSError(domain: "x", code: 1)), .form)
    }

    // MARK: - helpers

    func testSubstituteCredentialReplacesPlaceholders() {
        let resolved = substituteCredential("Change {credential} ({credentialLower})", "PIN")
        XCTAssertEqual(resolved, "Change PIN (pin)")
    }

    func testTitleCasedCredential() {
        XCTAssertEqual(titleCasedCredential("pin"), "Pin")
        XCTAssertEqual(titleCasedCredential("password"), "Password")
    }
}
