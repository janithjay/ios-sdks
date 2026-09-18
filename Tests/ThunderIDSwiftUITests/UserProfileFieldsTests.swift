// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

final class UserProfileFieldsTests: XCTestCase {
    // MARK: - buildProfileFields

    func testBuildProfileFieldsFiltersCredentialAttributes() {
        let schema: [String: AttributeSchema] = [
            "password": AttributeSchema(credential: true, type: "STRING"),
            "email": AttributeSchema(credential: false, type: "STRING")
        ]
        let profile = ThunderID.UserProfile(id: "u1", attributes: ["email": AnyCodable("a@b.com")])
        let fields = buildProfileFields(schema: schema, profile: profile)
        XCTAssertEqual(fields.map(\.name), ["email"])
    }

    func testBuildProfileFieldsMarksReadonlyFromSchemaFlag() {
        let schema: [String: AttributeSchema] = ["email": AttributeSchema(readOnly: true, type: "STRING")]
        let profile = ThunderID.UserProfile(id: "u1", attributes: [:])
        let fields = buildProfileFields(schema: schema, profile: profile)
        XCTAssertEqual(fields.first?.isReadonly, true)
    }

    func testBuildProfileFieldsMarksReadonlyFromMutability() {
        let schema: [String: AttributeSchema] = ["email": AttributeSchema(mutability: "READ_ONLY", type: "STRING")]
        let profile = ThunderID.UserProfile(id: "u1", attributes: [:])
        let fields = buildProfileFields(schema: schema, profile: profile)
        XCTAssertEqual(fields.first?.isReadonly, true)
    }

    func testBuildProfileFieldsMarksReadonlyFromFixedList() {
        let schema: [String: AttributeSchema] = ["username": AttributeSchema(type: "STRING")]
        let profile = ThunderID.UserProfile(id: "u1", attributes: [:])
        let fields = buildProfileFields(schema: schema, profile: profile)
        XCTAssertEqual(fields.first?.isReadonly, true)
    }

    func testBuildProfileFieldsLeavesOrdinaryAttributesEditable() {
        let schema: [String: AttributeSchema] = ["nickname": AttributeSchema(type: "STRING")]
        let profile = ThunderID.UserProfile(id: "u1", attributes: [:])
        let fields = buildProfileFields(schema: schema, profile: profile)
        XCTAssertEqual(fields.first?.isReadonly, false)
    }

    // MARK: - formatClaim

    func testFormatClaimReturnsNilForEmptyString() {
        XCTAssertNil(formatClaim(""))
    }

    func testFormatClaimReturnsStringAsIs() {
        XCTAssertEqual(formatClaim("Alice"), "Alice")
    }

    func testFormatClaimFormatsBooleanAsYesNo() {
        XCTAssertEqual(formatClaim(true), "Yes")
        XCTAssertEqual(formatClaim(false), "No")
    }

    func testFormatClaimFormatsNumbers() {
        XCTAssertEqual(formatClaim(42), "42")
    }

    func testFormatClaimJoinsAList() {
        let list = [AnyCodable("a"), AnyCodable("b")]
        XCTAssertEqual(formatClaim(list), "a, b")
    }

    func testFormatClaimDropsNestedMap() {
        let nested = ["level": AnyCodable("AAL1")]
        XCTAssertNil(formatClaim(nested))
    }

    // MARK: - claimLabel

    func testClaimLabelHumanizesSnakeCase() {
        XCTAssertEqual(claimLabel("given_name"), "Given Name")
    }

    func testClaimLabelHumanizesCamelCase() {
        XCTAssertEqual(claimLabel("givenName"), "Given Name")
    }

    // MARK: - claimsDisplayName

    func testClaimsDisplayNameReturnsGuestForNilUser() {
        XCTAssertEqual(claimsDisplayName(nil), "Guest")
    }

    func testClaimsDisplayNamePrefersGivenAndFamilyName() {
        let user = User(claims: ["given_name": AnyCodable("Ada"), "family_name": AnyCodable("Lovelace")])
        XCTAssertEqual(claimsDisplayName(user), "Ada Lovelace")
    }

    func testClaimsDisplayNameFallsBackToUsername() {
        let user = User(claims: ["username": AnyCodable("ada")])
        XCTAssertEqual(claimsDisplayName(user), "ada")
    }

    func testClaimsDisplayNameFallsBackToGuestWhenNothingAvailable() {
        let user = User(claims: ["sub": AnyCodable("abc")])
        XCTAssertEqual(claimsDisplayName(user), "Guest")
    }

    // MARK: - buildProfileFieldsFromClaims

    func testBuildProfileFieldsFromClaimsDropsReservedClaims() {
        let user = User(claims: ["sub": AnyCodable("abc"), "given_name": AnyCodable("Ada")])
        let fields = buildProfileFieldsFromClaims(user)
        XCTAssertEqual(fields.map(\.name), ["given_name"])
        XCTAssertTrue(fields.allSatisfy(\.isReadonly))
    }

    func testBuildProfileFieldsFromClaimsDropsNestedObjectClaims() {
        let user = User(claims: [
            "given_name": AnyCodable("Ada"),
            "assurance": AnyCodable(["level": AnyCodable("AAL1")])
        ])
        let fields = buildProfileFieldsFromClaims(user)
        XCTAssertEqual(fields.map(\.name), ["given_name"])
    }

    // MARK: - validateField

    func testValidateFieldRejectsBlankRequiredValue() {
        let schema = AttributeSchema(required: true)
        XCTAssertEqual(validateField(schema, "  "), "userProfile.validation.required")
    }

    func testValidateFieldAcceptsNonBlankRequiredValue() {
        let schema = AttributeSchema(required: true)
        XCTAssertNil(validateField(schema, "value"))
    }

    func testValidateFieldRejectsValueNotMatchingRegex() {
        let schema = AttributeSchema(regex: "^[0-9]+$")
        XCTAssertEqual(validateField(schema, "abc"), "userProfile.validation.pattern")
    }

    func testValidateFieldAcceptsValueMatchingRegex() {
        let schema = AttributeSchema(regex: "^[0-9]+$")
        XCTAssertNil(validateField(schema, "123"))
    }

    func testValidateFieldIgnoresInvalidRegexPattern() {
        let schema = AttributeSchema(regex: "([")
        XCTAssertNil(validateField(schema, "anything"))
    }

    // MARK: - mapAttribute / computeDisplayName

    func testMapAttributeUsesDefaultMappingFallbackOrder() {
        let profile = ThunderID.UserProfile(id: "u1", attributes: ["given_name": AnyCodable("Ada")])
        XCTAssertEqual(mapAttribute("firstName", [:], profile), "Ada")
    }

    func testMapAttributeUsesCustomMappingOverDefault() {
        let profile = ThunderID.UserProfile(id: "u1", attributes: ["nick": AnyCodable("Ace")])
        XCTAssertEqual(mapAttribute("firstName", ["firstName": ["nick"]], profile), "Ace")
    }

    func testMapAttributeFallsBackToDirectAttributeWhenNoMappingExists() {
        let profile = ThunderID.UserProfile(id: "u1", attributes: ["department": AnyCodable("Eng")])
        XCTAssertEqual(mapAttribute("department", [:], profile), "Eng")
    }

    func testComputeDisplayNameCombinesFirstAndLastName() {
        let profile = ThunderID.UserProfile(
            id: "u1",
            attributes: ["given_name": AnyCodable("Ada"), "family_name": AnyCodable("Lovelace")]
        )
        XCTAssertEqual(computeDisplayName([:], profile), "Ada Lovelace")
    }

    func testComputeDisplayNameFallsBackToId() {
        let profile = ThunderID.UserProfile(id: "u1", attributes: [:])
        XCTAssertEqual(computeDisplayName([:], profile), "u1")
    }

    // MARK: - stringifyFieldValue

    func testStringifyFieldValueHandlesNil() {
        XCTAssertEqual(stringifyFieldValue(nil), "")
    }

    func testStringifyFieldValueJoinsList() {
        XCTAssertEqual(stringifyFieldValue([AnyCodable("a"), AnyCodable("b")]), "a, b")
    }

    func testStringifyFieldValueBlanksOutComplexMap() {
        XCTAssertEqual(stringifyFieldValue(["k": AnyCodable("v")]), "")
    }

    func testStringifyFieldValueConvertsScalar() {
        XCTAssertEqual(stringifyFieldValue("hello"), "hello")
    }

    // MARK: - buildUpdatePayload / deepMergeAttributes

    func testBuildUpdatePayloadBuildsNestedDotPath() {
        let payload = buildUpdatePayload("name.givenName", "Ada", false)
        let name = payload["name"] as? [String: Any]
        XCTAssertEqual(name?["givenName"] as? String, "Ada")
    }

    func testBuildUpdatePayloadSplitsMultiValuedField() {
        let payload = buildUpdatePayload("tags", "a, b, c", true)
        XCTAssertEqual(payload["tags"] as? [String], ["a", "b", "c"])
    }

    func testDeepMergeAttributesMergesNestedDictionariesRecursively() {
        let base: [String: Any] = ["name": ["givenName": "Ada", "familyName": "Lovelace"]]
        let overrides: [String: Any] = ["name": ["givenName": "Grace"]]
        let merged = deepMergeAttributes(base, overrides)
        let name = merged["name"] as? [String: Any]
        XCTAssertEqual(name?["givenName"] as? String, "Grace")
        XCTAssertEqual(name?["familyName"] as? String, "Lovelace")
    }

    func testDeepMergeAttributesOverwritesScalarValues() {
        let base: [String: Any] = ["email": "old@example.com"]
        let overrides: [String: Any] = ["email": "new@example.com"]
        let merged = deepMergeAttributes(base, overrides)
        XCTAssertEqual(merged["email"] as? String, "new@example.com")
    }

    // MARK: - isPictureField

    func testIsPictureFieldMatchesEverySharedPictureClaimCandidateCaseInsensitively() {
        for candidate in pictureClaimKeys {
            XCTAssertTrue(isPictureField(candidate), "expected '\(candidate)' to match")
            XCTAssertTrue(isPictureField(candidate.uppercased()), "expected '\(candidate.uppercased())' to match")
        }
    }

    func testIsPictureFieldDoesNotMatchAnUnrelatedAttributeName() {
        XCTAssertFalse(isPictureField("firstName"))
        XCTAssertFalse(isPictureField("email"))
    }
}
