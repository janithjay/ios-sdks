// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The browser, operating system and device model a User-Agent names, and whether it came from a
/// native app rather than a browser. A part the string doesn't reveal is nil.
public struct UserAgentDescription: Equatable {
    public var browser: String?
    public var os: String?
    public var device: String?
    public var isApp: Bool

    public init(browser: String? = nil, os: String? = nil, device: String? = nil, isApp: Bool = false) {
        self.browser = browser
        self.os = os
        self.device = device
        self.isApp = isApp
    }
}

// The User-Agent the mobile SDKs send: `ThunderID-Android/1.4.0 (Android 14; Google Pixel 8)`, or the
// iOS equivalent. The Flutter SDK bridges to those, so its requests carry the same header. The
// first word of the comment is the operating system, the part after `;` the device.
private let nativeSDKPattern = #"\bThunderID-(?:Android|iOS)/\S*\s*\((\w+)[^;)]*(?:;\s*([^)]+))?\)"#

// Checked in order, matching the JavaScript SDK's describeUserAgent: several browsers also carry the
// tokens of the ones they derive from, so Edge, Opera and Samsung Internet come before Chrome, and
// Chrome before Safari.
private let browserPatterns: [(String, String)] = [
    (#"\bEdg(?:e|A|iOS)?/"#, "Edge"),
    (#"\b(?:OPR|Opera)/"#, "Opera"),
    (#"\bSamsungBrowser/"#, "Samsung Internet"),
    (#"\b(?:Firefox|FxiOS)/"#, "Firefox"),
    (#"\b(?:Chrome|CriOS)/"#, "Chrome"),
    (#"\bVersion/[\d.]+.*\bSafari/"#, "Safari")
]

private let osPatterns: [(String, String)] = [
    (#"\bWindows\b"#, "Windows"),
    (#"\b(?:iPhone|iPad|iPod)\b"#, "iOS"),
    (#"\bAndroid\b"#, "Android"),
    (#"\bCrOS\b"#, "ChromeOS"),
    (#"\bMac OS X\b|\bMacintosh\b"#, "macOS"),
    (#"\bLinux\b"#, "Linux")
]

/// Reads the browser and operating system from a User-Agent, or the device from a mobile SDK's, for
/// showing a session as, for example, "Chrome on macOS". It recognizes the common browsers only, and
/// is for display, never for decisions.
public func describeUserAgent(_ userAgent: String?) -> UserAgentDescription {
    guard let userAgent, !userAgent.isEmpty else { return UserAgentDescription() }
    let range = NSRange(userAgent.startIndex..., in: userAgent)
    if let expression = try? NSRegularExpression(pattern: nativeSDKPattern),
       let match = expression.firstMatch(in: userAgent, range: range) {
        let group = { (index: Int) -> String? in
            guard let groupRange = Range(match.range(at: index), in: userAgent) else { return nil }
            let value = userAgent[groupRange].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return UserAgentDescription(os: group(1), device: group(2), isApp: true)
    }
    let firstMatch = { (patterns: [(String, String)]) -> String? in
        patterns.first { pattern, _ in userAgent.range(of: pattern, options: .regularExpression) != nil }?.1
    }
    return UserAgentDescription(browser: firstMatch(browserPatterns), os: firstMatch(osPatterns))
}

/// Sessions that share an operating system, listed together.
public struct SessionGroup: Identifiable {
    public let os: String?
    public let sessions: [SSOSession]
    public var id: String { os ?? "" }
    public var hasCurrent: Bool { sessions.contains { $0.isCurrent } }
}

/// Groups sessions by the operating system their User-Agent names. The group holding the current
/// session comes first; the rest keep the server's order, most recently active first.
func groupSessionsByOS(_ sessions: [SSOSession]) -> [SessionGroup] {
    var order: [String?] = []
    var grouped: [String?: [SSOSession]] = [:]
    for session in sessions {
        let os = describeUserAgent(session.userAgent).os
        if grouped[os] == nil { order.append(os) }
        grouped[os, default: []].append(session)
    }
    let groups = order.map { SessionGroup(os: $0, sessions: grouped[$0] ?? []) }
    return groups.filter(\.hasCurrent) + groups.filter { !$0.hasCurrent }
}

extension ThunderIDI18n {
    /// Resolves an active-sessions key and substitutes `{name}` placeholders in one call.
    func sessions(_ key: String, _ values: [String: String] = [:]) -> String {
        values.reduce(resolve("activeSessions.\(key)")) { text, pair in
            text.replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
        }
    }
}

// The server lists participants first joined first, so the first started the session.
private func startingAppName(_ session: SSOSession) -> String? { session.participants.first?.appName }

/// "Chrome on macOS", a native app's device ("iPhone 7"), or the part that is known, or "Unknown device".
func deviceLabel(_ session: SSOSession, i18n: ThunderIDI18n) -> String {
    let description = describeUserAgent(session.userAgent)
    // A native app's session is named by its device alone; its applications are listed separately.
    if let device = description.device { return device }
    let client = description.browser ?? startingAppName(session)
    let place = description.os
    if let client, let place {
        return i18n.sessions("device", ["client": client, "place": place])
    }
    return client ?? place ?? i18n.sessions("unknownDevice")
}

/// A session row's title: the browser, a native app's device, or the application that started it.
func clientLabel(_ session: SSOSession, i18n: ThunderIDI18n) -> String {
    let description = describeUserAgent(session.userAgent)
    return description.browser ?? description.device ?? startingAppName(session) ?? i18n.sessions("unknownDevice")
}

/// The address the session was last seen from, falling back to the one it was created from.
func sessionIp(_ session: SSOSession) -> String? { session.lastActiveIp ?? session.creationIp }

/// Formats a server timestamp as a medium date and short time, or returns it unchanged when it
/// can't be read.
func formatSessionTime(_ value: String, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = parser.date(from: value)
    if date == nil {
        parser.formatOptions = [.withInternetDateTime]
        date = parser.date(from: value)
    }
    guard let date else { return value }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

/// Whether a revoke failed only because the session is already gone, revoked elsewhere or expired.
func isAlreadyRevoked(_ error: Error) -> Bool { (error as? ThunderIDError)?.code == .notFound }

/// State container passed to the ``BaseActiveSessions`` builder.
@MainActor
public final class ActiveSessionsState: ObservableObject {
    @Published public fileprivate(set) var sessions: [SSOSession] = []
    @Published public fileprivate(set) var totalCount: Int = 0
    @Published public fileprivate(set) var isLoading: Bool = false
    @Published public fileprivate(set) var error: String?
    @Published public fileprivate(set) var revokingSessionId: String?
    @Published public fileprivate(set) var revokingOthers: Bool = false

    fileprivate var onRefresh: () -> Void = {}
    fileprivate var onRevoke: (String) -> Void = { _ in }
    fileprivate var onRevokeOthers: () -> Void = {}

    public var groups: [SessionGroup] { groupSessionsByOS(sessions) }

    /// Sessions other than the current one, counted across every page, not just the loaded one.
    public var otherCount: Int { max(totalCount - sessions.filter(\.isCurrent).count, 0) }

    public func refresh() { onRefresh() }

    public func revoke(_ sessionId: String) { onRevoke(sessionId) }

    public func revokeOthers() { onRevokeOthers() }
}

/// Headless active-sessions list. Loads the signed-in user's live SSO sessions from
/// `GET /sessions/me`, revokes one or every other session, and hands its ``ActiveSessionsState``
/// to a caller-supplied builder, mirroring the ``BaseUserProfile`` split.
///
/// Only the first page is loaded, `limit` sessions at most (the server's page size by default);
/// sessions beyond it can still be revoked with ``ActiveSessionsState/revokeOthers()``.
public struct BaseActiveSessions<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    private let limit: Int?
    private let onRevoked: (() -> Void)?
    private let onError: (() -> Void)?
    private let content: (ActiveSessionsState) -> Content

    @StateObject private var state = ActiveSessionsState()

    public init(
        limit: Int? = nil,
        onRevoked: (() -> Void)? = nil,
        onError: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (ActiveSessionsState) -> Content
    ) {
        self.limit = limit
        self.onRevoked = onRevoked
        self.onError = onError
        self.content = content
    }

    public var body: some View {
        content(state)
            .task(id: limit) {
                state.onRefresh = { Task { await load() } }
                state.onRevoke = revoke
                state.onRevokeOthers = revokeOthers
                await load()
            }
    }

    private func load() async {
        state.isLoading = true
        defer { state.isLoading = false }
        do {
            let page = try await thunderState.client.getUserSessions(limit: limit)
            state.sessions = page.sessions
            state.totalCount = page.totalResults
            state.error = nil
        } catch {
            state.error = thunderState.i18n.sessions("error.load")
            onError?()
        }
    }

    private func runRevoke(_ call: () async throws -> Void) async {
        state.error = nil
        do {
            try await call()
            await load()
            onRevoked?()
        } catch {
            if isAlreadyRevoked(error) {
                await load()
            } else {
                state.error = thunderState.i18n.sessions("error.revoke")
                onError?()
            }
        }
    }

    private func revoke(_ sessionId: String) {
        guard state.revokingSessionId == nil, !state.revokingOthers else { return }
        state.revokingSessionId = sessionId
        Task {
            defer { state.revokingSessionId = nil }
            await runRevoke { try await thunderState.client.revokeUserSession(sessionId: sessionId) }
        }
    }

    private func revokeOthers() {
        guard state.revokingSessionId == nil, !state.revokingOthers else { return }
        state.revokingOthers = true
        Task {
            defer { state.revokingOthers = false }
            await runRevoke { try await thunderState.client.revokeUserSessions(exceptCurrent: true) }
        }
    }
}

/// Styled default active-sessions list. Renders a Manage sessions row with the session count that
/// pushes a page listing every session, grouped by operating system. A session pushes a detail page,
/// where it can be signed out after a confirmation.
///
/// The pages are pushed like a Settings screen, so place this inside a `NavigationStack` (or
/// `NavigationView`); outside one, the row can't open.
///
/// The current session has no Revoke action, since ending it would also end the session the
/// app is using. Use the regular sign-out for that.
///
/// `title` overrides the "Active sessions" heading; pass an empty string to omit it.
public struct ActiveSessions: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    public let limit: Int?
    public let title: String?
    public let onRevoked: (() -> Void)?

    public init(limit: Int? = nil, title: String? = nil, onRevoked: (() -> Void)? = nil) {
        self.limit = limit
        self.title = title
        self.onRevoked = onRevoked
    }

    public var body: some View {
        BaseActiveSessions(limit: limit, onRevoked: onRevoked) { state in
            ActiveSessionsSummary(state: state, i18n: i18n, title: title ?? i18n.sessions("section"))
        }
    }
}

private struct ActiveSessionsSummary: View {
    @ObservedObject var state: ActiveSessionsState
    let i18n: ThunderIDI18n
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundColor(colorScheme.sessionsTextSecondary)
                    .padding(.leading, 16)
            }
            if state.isLoading && state.sessions.isEmpty {
                Text(i18n.sessions("loading"))
                    .font(.system(size: 15))
                    .foregroundColor(colorScheme.sessionsTextSecondary)
                    .padding(.leading, 16)
            } else if state.sessions.isEmpty {
                Text(state.error ?? i18n.sessions("empty"))
                    .font(.system(size: 15))
                    .foregroundColor(state.error == nil ? colorScheme.sessionsTextSecondary : colorScheme.sessionsError)
                    .padding(.leading, 16)
            } else {
                manageRow
                Text(i18n.sessions("footnote"))
                    .font(.system(size: 13))
                    .foregroundColor(colorScheme.sessionsTextSecondary)
                    .padding(.horizontal, 16)
                if let error = state.error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(colorScheme.sessionsError)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private var manageRow: some View {
        NavigationLink {
            SessionListPage(state: state, i18n: i18n)
        } label: {
            HStack(spacing: 6) {
                Text(i18n.sessions("manage"))
                    .font(.system(size: 16))
                    .foregroundColor(colorScheme.sessionsText)
                Spacer()
                Text(String(state.totalCount))
                    .font(.system(size: 16))
                    .foregroundColor(colorScheme.sessionsTextSecondary)
                chevron
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(colorScheme.sessionsCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("thunderid-action-manageSessions")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(colorScheme.sessionsChevron)
    }
}

/// Color tokens for `ActiveSessions`, matching the light/dark palette `UserProfile` and
/// `ChangeCredential` use. Kept local to this file, following this SDK's per-component convention.
private extension ColorScheme {
    var sessionsCard: Color { self == .dark ? Color(hex: "111c2e") : Color(hex: "ffffff") }
    var sessionsText: Color { self == .dark ? Color(hex: "E0EAFF") : Color(hex: "05213F") }
    var sessionsError: Color { Color(hex: "d95757") }

    var sessionsTextSecondary: Color {
        self == .dark ? Color(hex: "E0EAFF").opacity(0.48) : Color(hex: "5A7085")
    }

    var sessionsChevron: Color {
        self == .dark ? Color(hex: "E0EAFF").opacity(0.3) : Color(hex: "5A7085").opacity(0.55)
    }
}

private extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}
