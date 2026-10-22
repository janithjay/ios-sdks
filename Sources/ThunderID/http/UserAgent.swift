// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The User-Agent the SDK sends on every request, so the server can show a session as the device
/// that holds it: `ThunderID-iOS/1.4.0 (iOS 15.8; iPhone 7)`. It is for display only; the client
/// sets it, so nothing may rely on it for a decision.
enum UserAgent {
    /// Kept in step with `s.version` in `ThunderID.podspec`.
    static let sdkVersion = "1.4.0"

    static let value: String = build(
        sdkVersion: sdkVersion,
        osName: osName,
        osVersion: osVersion(ProcessInfo.processInfo.operatingSystemVersion),
        device: deviceName(machine: machineIdentifier())
    )

    static func build(sdkVersion: String, osName: String, osVersion: String?, device: String?) -> String {
        let os = [osName, clean(osVersion)].compactMap { $0 }.joined(separator: " ")
        let comment = [os, clean(device)].compactMap { $0 }.joined(separator: "; ")
        return "ThunderID-iOS/\(sdkVersion) (\(comment))"
    }

    /// `15.8`, or `15.8.3` when the patch version is set.
    static func osVersion(_ version: OperatingSystemVersion) -> String {
        var parts = [version.majorVersion, version.minorVersion]
        if version.patchVersion > 0 { parts.append(version.patchVersion) }
        return parts.map(String.init).joined(separator: ".")
    }

    /// The name a person recognizes their device by, "iPhone 7" rather than the hardware identifier
    /// `iPhone9,3`. An identifier missing from the table is shown as it is.
    static func deviceName(machine: String?) -> String? {
        guard let machine = clean(machine) else { return nil }
        if machine == "x86_64" || machine == "arm64" || machine == "i386" { return "iOS Simulator" }
        return marketingNames[machine] ?? machine
    }

    private static var osName: String {
        #if os(iOS)
        "iOS"
        #else
        "macOS"
        #endif
    }

    private static func machineIdentifier() -> String? {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
        }
    }

    // A comment's delimiters, or a control character, would break the header's structure.
    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let delimiters = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "();"))
        let kept = value.unicodeScalars.filter { !delimiters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static let marketingNames: [String: String] = [
        "iPhone9,1": "iPhone 7", "iPhone9,3": "iPhone 7",
        "iPhone9,2": "iPhone 7 Plus", "iPhone9,4": "iPhone 7 Plus",
        "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8",
        "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
        "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max"
    ]
}
