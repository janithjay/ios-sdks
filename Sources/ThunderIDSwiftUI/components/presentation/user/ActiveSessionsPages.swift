// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Every session, grouped by operating system, with Revoke all other sessions at the end.
struct SessionListPage: View {
    @ObservedObject var state: ActiveSessionsState
    let i18n: ThunderIDI18n
    @State private var confirmOthers = false

    var body: some View {
        List {
            ForEach(state.groups) { group in
                Section {
                    ForEach(group.sessions) { session in
                        NavigationLink(destination: SessionDetailView(session: session, state: state, i18n: i18n)) {
                            SessionRow(session: session, i18n: i18n)
                        }
                    }
                } header: {
                    Label { Text(groupTitle(group)) } icon: { OSIcon(os: group.os, size: 13) }
                }
            }
            if state.otherCount > 0 && state.sessions.contains(where: \.isCurrent) {
                Section(footer: Text(i18n.sessions("revokeOthers.note"))) {
                    Button(role: .destructive) { confirmOthers = true } label: {
                        Text(i18n.sessions("revokeOthers")).frame(maxWidth: .infinity)
                    }
                    .disabled(state.revokingOthers || state.revokingSessionId != nil)
                    .accessibilityIdentifier("thunderid-action-revokeOtherSessions")
                    // An alert, as Settings confirms signing out: a dialog opened from a button inside the
                    // list is drawn as a popover with an arrow pointing at it.
                    .alert(i18n.sessions("confirm.others.title"), isPresented: $confirmOthers) {
                        Button(i18n.sessions("cancel"), role: .cancel) {}
                        Button(i18n.sessions("revoke"), role: .destructive) { state.revokeOthers() }
                            .accessibilityIdentifier("thunderid-action-confirmRevoke")
                    } message: {
                        Text(state.otherCount == 1
                            ? i18n.sessions("confirm.others.body.one")
                            : i18n.sessions("confirm.others.body.other", ["count": String(state.otherCount)]))
                    }
                }
            }
            if let error = state.error {
                Text(error).font(.system(size: 13)).foregroundColor(.red)
            }
        }
        .sessionListStyle()
        .navigationTitle(i18n.sessions("title"))
        .refreshable { state.refresh() }
    }

    private func groupTitle(_ group: SessionGroup) -> String {
        let os = group.os ?? i18n.sessions("unknownDevice")
        return group.sessions.count == 1
            ? i18n.sessions("group.one", ["os": os])
            : i18n.sessions("group.other", ["count": String(group.sessions.count), "os": os])
    }
}

private struct SessionRow: View {
    let session: SSOSession
    let i18n: ThunderIDI18n

    var body: some View {
        HStack(spacing: 12) {
            ClientIcon(description: describeUserAgent(session.userAgent))
            VStack(alignment: .leading, spacing: 1) {
                Text(clientLabel(session, i18n: i18n))
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // "This device" for the current session, otherwise when it was last used. The operating system is
    // already in the group's header.
    private var subtitle: String {
        session.isCurrent
            ? i18n.sessions("current")
            : i18n.sessions("lastActive.since", ["date": formatSessionTime(session.lastActiveAt)])
    }
}

/// One session's details. A session other than the current one can be signed out from here; the
/// page closes when it drops out of the reloaded list.
private struct SessionDetailView: View {
    let session: SSOSession
    @ObservedObject var state: ActiveSessionsState
    let i18n: ThunderIDI18n
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false

    var body: some View {
        let description = describeUserAgent(session.userAgent)
        List {
            Section {
                detail(i18n.sessions("ip"), sessionIp(session) ?? i18n.sessions("unknown"))
                detail(i18n.sessions("signedIn"), formatSessionTime(session.authenticatedAt))
                detail(i18n.sessions("lastActive"), formatSessionTime(session.lastActiveAt))
            } header: {
                header(description)
            }
            Section(i18n.sessions("applications")) {
                if session.participants.isEmpty {
                    Text(i18n.sessions("unknown"))
                }
                ForEach(session.participants, id: \.appId) { participant in
                    Text(participant.appName ?? i18n.sessions("unknown"))
                }
            }
            if session.isCurrent {
                Section(footer: Text(i18n.sessions("current.note"))) {}
            } else {
                Section {
                    Button(role: .destructive) { confirm = true } label: {
                        Text(i18n.sessions("revoke")).frame(maxWidth: .infinity)
                    }
                    .disabled(state.revokingSessionId != nil || state.revokingOthers)
                    .accessibilityIdentifier("thunderid-action-revokeSession")
                    .alert(i18n.sessions("confirm.one.title"), isPresented: $confirm) {
                        Button(i18n.sessions("cancel"), role: .cancel) {}
                        Button(i18n.sessions("revoke"), role: .destructive) { state.revoke(session.id) }
                            .accessibilityIdentifier("thunderid-action-confirmRevoke")
                    } message: {
                        Text(i18n.sessions("confirm.one.body", ["device": deviceLabel(session, i18n: i18n)]))
                    }
                }
            }
            if let error = state.error {
                Text(error).font(.system(size: 13)).foregroundColor(.red)
            }
        }
        .sessionListStyle()
        .onChange(of: state.sessions) { sessions in
            if !sessions.contains(where: { $0.id == session.id }) { dismiss() }
        }
    }

    // The operating system in a large circle with the client badged on it, then the session's name.
    private func header(_ description: UserAgentDescription) -> some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                OSIcon(os: description.os, size: 38)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Color.sessionsCard))
                ClientLogo(description: description, size: 18)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white))
                    .overlay(Circle().stroke(Color.sessionsPage, lineWidth: 3))
                    .offset(x: 2, y: 2)
            }
            .padding(.bottom, 12)
            Text(clientLabel(session, i18n: i18n))
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)
            if let line = osLine(description) {
                Text(line)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
        }
        .textCase(nil)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private func osLine(_ description: UserAgentDescription) -> String? {
        let parts = [description.os, session.isCurrent ? i18n.sessions("current") : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func detail(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).monospacedDigit().textSelection(.enabled)
        }
    }
}

/// A browser's logo, or a symbol for a native app or an unrecognized browser, on a white tile sized
/// and rounded like a Settings row icon.
private struct ClientIcon: View {
    let description: UserAgentDescription

    var body: some View {
        ClientLogo(description: description, size: 18)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
            )
    }
}

private struct ClientLogo: View {
    let description: UserAgentDescription
    let size: CGFloat

    var body: some View {
        if let logo = browserLogo(description.browser) {
            PlatformLogoView(logo: logo, size: size)
        } else {
            Image(systemName: clientSymbol(description))
                .font(.system(size: size * 0.85))
                .foregroundColor(.sessionsAccent)
        }
    }
}

private struct OSIcon: View {
    let os: String?
    let size: CGFloat

    var body: some View {
        if let logo = osLogo(os) {
            PlatformLogoView(logo: logo, size: size)
        } else {
            Image(systemName: "questionmark.circle")
                .font(.system(size: size * 0.85))
                .foregroundColor(.secondary)
        }
    }
}

func clientSymbol(_ description: UserAgentDescription) -> String {
    if description.browser == nil && description.isApp { return "iphone" }
    return description.browser == nil ? "desktopcomputer" : "globe"
}

private extension View {
    /// Inset grouped rows under an inline title, the iOS settings look. macOS keeps its defaults.
    @ViewBuilder
    func sessionListStyle() -> some View {
        #if canImport(UIKit)
        listStyle(.insetGrouped).navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

/// The ThunderID accent, and the system grouped-list colors so the detail header blends with the
/// inset grouped list around it.
private extension Color {
    static let sessionsAccent = Color(red: 0x36 / 255, green: 0x88 / 255, blue: 0xFF / 255)

    #if canImport(UIKit)
    static let sessionsPage = Color(uiColor: .systemGroupedBackground)
    static let sessionsCard = Color(uiColor: .secondarySystemGroupedBackground)
    #else
    static let sessionsPage = Color(nsColor: .windowBackgroundColor)
    static let sessionsCard = Color(nsColor: .controlBackgroundColor)
    #endif
}
