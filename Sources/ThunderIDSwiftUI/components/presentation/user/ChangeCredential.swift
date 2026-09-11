// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The form field a credential-update failure belongs to.
public enum CredentialField: Hashable {
    /// The supplied current value was rejected by the server.
    case current
    /// The new value failed a server-side check.
    case new
    /// The failure has no single field to blame; show it at form level.
    case form
}

/// The derived state a change-credential form needs to render and to gate submission.
///
/// Mirrors the JavaScript SDK's `evaluateChangePasswordForm`: the current value is deliberately
/// left out of `isValid`, since only the server knows whether the account has a value to verify.
public struct CredentialFormEvaluation {
    public let confirmMatches: Bool
    public let meetsPolicy: Bool
    public let reusesCurrent: Bool
    public let isValid: Bool
    /// Whether a regex rule applies, so the requirement checklist can be shown.
    public let patternChecked: Bool
    /// Whether the new value satisfies the regex rule (always `true` when none applies).
    public let patternPassed: Bool
}

/// Evaluates a change-credential form against an optional regex policy.
///
/// An uncompilable pattern is treated as passing, matching the JavaScript SDK: the client stays
/// lenient so a misconfigured schema cannot lock a user out of their own credential change.
public func evaluateCredentialForm(
    current: String,
    new: String,
    confirm: String,
    regex: String?
) -> CredentialFormEvaluation {
    let patternChecked = !(regex ?? "").isEmpty
    var patternPassed = true
    if patternChecked, let regex, let expression = try? NSRegularExpression(pattern: regex) {
        let range = NSRange(new.startIndex..., in: new)
        patternPassed = expression.firstMatch(in: new, range: range) != nil
    }
    let meetsPolicy = !patternChecked || patternPassed
    let confirmMatches = new == confirm
    let reusesCurrent = !new.isEmpty && new == current
    let isValid = !new.isEmpty && !confirm.isEmpty && meetsPolicy && confirmMatches && !reusesCurrent
    return CredentialFormEvaluation(
        confirmMatches: confirmMatches,
        meetsPolicy: meetsPolicy,
        reusesCurrent: reusesCurrent,
        isValid: isValid,
        patternChecked: patternChecked,
        patternPassed: patternPassed
    )
}

/// Maps a failure from the credential write path onto the field that caused it.
///
/// `403` is the server rejecting the supplied current value; `400` is the new value failing a
/// server-side check. Anything else has no single field to blame.
public func mapCredentialError(_ error: Error) -> CredentialField {
    guard let thunderError = error as? ThunderIDError else { return .form }
    switch thunderError.code {
    case .invalidCredential: return .current
    case .invalidInput: return .new
    default: return .form
    }
}

/// Substitutes `{credential}` / `{credentialLower}` into a translation template.
func substituteCredential(_ template: String, _ displayName: String) -> String {
    template
        .replacingOccurrences(of: "{credential}", with: displayName)
        .replacingOccurrences(of: "{credentialLower}", with: displayName.lowercased())
}

/// Title-cases a credential name for use as its default display name, e.g. `pin` -> `Pin`.
func titleCasedCredential(_ name: String) -> String {
    name.isEmpty ? name : name.prefix(1).uppercased() + name.dropFirst()
}

/// State container passed to the ``BaseChangeCredential`` builder.
@MainActor
public final class ChangeCredentialState: ObservableObject {
    @Published public var currentValue: String = ""
    @Published public var newValue: String = ""
    @Published public var confirmValue: String = ""
    @Published public fileprivate(set) var error: String?
    @Published public fileprivate(set) var loading: Bool = false
    @Published public fileprivate(set) var success: Bool = false
    @Published public fileprivate(set) var unavailable: Bool = false
    @Published fileprivate var regex: String?
    @Published fileprivate var fieldErrors: [CredentialField: String] = [:]

    /// The human-readable credential name substituted into every label and message.
    public let credentialDisplayName: String

    fileprivate var onSubmit: () -> Void = {}

    init(credentialDisplayName: String) {
        self.credentialDisplayName = credentialDisplayName
    }

    public var evaluation: CredentialFormEvaluation {
        evaluateCredentialForm(current: currentValue, new: newValue, confirm: confirmValue, regex: regex)
    }

    public func fieldError(_ field: CredentialField) -> String? { fieldErrors[field] }

    public func submit() { onSubmit() }
}

/// Lets the signed-in user set a new value for one of their own credentials.
///
/// Delegates rendering to a caller-supplied builder and keeps the network call, the schema-derived
/// policy, and the error routing here, mirroring the ``BaseUserProfile`` split.
public struct BaseChangeCredential<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    private let credentialName: String
    private let policyRegexOverride: String?
    private let onSuccess: (() -> Void)?
    private let onError: (() -> Void)?
    private let content: (ChangeCredentialState) -> Content

    @StateObject private var state: ChangeCredentialState

    public init(
        credentialName: String = "password",
        credentialDisplayName: String? = nil,
        policyRegex: String? = nil,
        onSuccess: (() -> Void)? = nil,
        onError: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (ChangeCredentialState) -> Content
    ) {
        self.credentialName = credentialName
        self.policyRegexOverride = policyRegex
        self.onSuccess = onSuccess
        self.onError = onError
        self.content = content
        _state = StateObject(wrappedValue: ChangeCredentialState(
            credentialDisplayName: credentialDisplayName ?? titleCasedCredential(credentialName)
        ))
    }

    public var body: some View {
        content(state)
            .task {
                state.onSubmit = submit
                await resolvePolicy()
            }
    }

    private func resolvePolicy() async {
        if let policyRegexOverride {
            state.regex = policyRegexOverride
            return
        }
        guard let schema = try? await thunderState.client.getUserSchema() else { return }
        state.regex = schema[credentialName]?.regex
        state.unavailable = !schema.isEmpty && schema[credentialName] == nil
    }

    private func submit() {
        guard state.evaluation.isValid, !state.loading, !state.unavailable else { return }
        Task { await performSubmit() }
    }

    private func performSubmit() async {
        state.error = nil
        state.fieldErrors = [:]
        state.success = false
        state.loading = true
        defer { state.loading = false }
        do {
            try await thunderState.client.updateUserCredentials(
                credentialName: credentialName,
                currentValue: state.currentValue.isEmpty ? nil : state.currentValue,
                newValue: state.newValue
            )
            state.currentValue = ""
            state.newValue = ""
            state.confirmValue = ""
            state.success = true
            onSuccess?()
        } catch {
            applyError(error)
            onError?()
        }
    }

    private func applyError(_ error: Error) {
        let field = mapCredentialError(error)
        let text = message(for: field)
        switch field {
        case .current, .new: state.fieldErrors[field] = text
        case .form: state.error = text
        }
    }

    private func message(for field: CredentialField) -> String {
        let resolve = { substituteCredential(thunderState.i18n.resolve($0), state.credentialDisplayName) }
        switch field {
        case .current:
            return resolve("changeCredential.current.invalid.error")
        case .new, .form:
            return resolve("changeCredential.generic.error")
        }
    }
}

/// Styled default change-credential form. Defaults to managing the `password` credential; set
/// `credentialName` to manage another one declared on the user type schema (for example `pin`).
public struct ChangeCredential: View {
    private let credentialName: String
    private let credentialDisplayName: String?
    private let onSuccess: (() -> Void)?

    public init(
        credentialName: String = "password",
        credentialDisplayName: String? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        self.credentialName = credentialName
        self.credentialDisplayName = credentialDisplayName
        self.onSuccess = onSuccess
    }

    public var body: some View {
        BaseChangeCredential(
            credentialName: credentialName,
            credentialDisplayName: credentialDisplayName,
            onSuccess: onSuccess
        ) { state in
            ChangeCredentialForm(state: state)
        }
    }
}

private struct ChangeCredentialForm: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @ObservedObject var state: ChangeCredentialState

    private func text(_ key: String) -> String {
        substituteCredential(i18n.resolve(key), state.credentialDisplayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text("changeCredential.heading"))
                .font(.title2)
                .bold()
                .accessibilityAddTraits(.isHeader)

            if state.unavailable {
                Text(text("changeCredential.unavailable"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                formBody
            }
        }
        .padding()
    }

    @ViewBuilder
    private var formBody: some View {
        if let error = state.error {
            Text(error).font(.caption).foregroundColor(.red)
        }
        if state.success {
            Text(text("changeCredential.success")).font(.caption).foregroundColor(.green)
        }

        secureField(text("changeCredential.current.label"),
                    value: $state.currentValue,
                    error: state.fieldError(.current))
        secureField(text("changeCredential.new.label"),
                    value: $state.newValue,
                    error: state.fieldError(.new))

        let evaluation = state.evaluation
        if evaluation.patternChecked {
            HStack(spacing: 6) {
                Image(systemName: evaluation.patternPassed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(evaluation.patternPassed ? .green : .secondary)
                Text(text("changeCredential.requirements.pattern")).font(.caption)
            }
        }

        let mismatch = !state.confirmValue.isEmpty && !evaluation.confirmMatches
        secureField(text("changeCredential.confirm.label"),
                    value: $state.confirmValue,
                    error: mismatch ? text("changeCredential.mismatch.error") : nil)

        Button {
            state.submit()
        } label: {
            Text(text("changeCredential.submit"))
        }
        .disabled(!evaluation.isValid || state.loading)
    }

    private func secureField(_ label: String, value: Binding<String>, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            SecureField(label, text: value)
                .textContentType(.password)
            if let error {
                Text(error).font(.caption2).foregroundColor(.red)
            }
        }
    }
}
