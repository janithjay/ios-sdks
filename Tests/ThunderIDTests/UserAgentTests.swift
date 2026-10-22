// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class UserAgentTests: XCTestCase {
    func testBuildsTheMobileSDKFormat() {
        XCTAssertEqual(
            UserAgent.build(sdkVersion: "1.4.0", osName: "iOS", osVersion: "15.8", device: "iPhone 7"),
            "ThunderID-iOS/1.4.0 (iOS 15.8; iPhone 7)"
        )
    }

    func testLeavesOutAnUnknownDevice() {
        XCTAssertEqual(
            UserAgent.build(sdkVersion: "1.4.0", osName: "iOS", osVersion: "15.8", device: nil),
            "ThunderID-iOS/1.4.0 (iOS 15.8)"
        )
    }

    func testRemovesDelimitersFromEachPart() {
        XCTAssertEqual(
            UserAgent.build(sdkVersion: "1.4.0", osName: "iOS", osVersion: "15.8", device: "Bad (Name); x"),
            "ThunderID-iOS/1.4.0 (iOS 15.8; Bad Name x)"
        )
    }

    func testFormatsTheOSVersion() {
        XCTAssertEqual(UserAgent.osVersion(OperatingSystemVersion(majorVersion: 15, minorVersion: 8, patchVersion: 0)), "15.8")
        XCTAssertEqual(UserAgent.osVersion(OperatingSystemVersion(majorVersion: 15, minorVersion: 8, patchVersion: 3)), "15.8.3")
    }

    func testNamesTheDevice() {
        XCTAssertEqual(UserAgent.deviceName(machine: "iPhone9,3"), "iPhone 7")
        XCTAssertEqual(UserAgent.deviceName(machine: "arm64"), "iOS Simulator")
        XCTAssertEqual(UserAgent.deviceName(machine: "iPhone99,9"), "iPhone99,9")
        XCTAssertNil(UserAgent.deviceName(machine: nil))
    }
}
