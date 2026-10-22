// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// An application that has used an ``SSOSession``.
public struct SSOSessionParticipant: Codable, Equatable {
    public let appId: String
    /// The application's name. Left out when the application can't be found.
    public let appName: String?
    public let firstJoinedAt: String
    public let lastActiveAt: String

    public init(appId: String, appName: String? = nil, firstJoinedAt: String, lastActiveAt: String) {
        self.appId = appId
        self.appName = appName
        self.firstJoinedAt = firstJoinedAt
        self.lastActiveAt = lastActiveAt
    }
}

/// A live SSO session of the signed-in user, as recorded by the ThunderID server.
///
/// This is a server record, distinct from the tokens the SDK stores for the signed-in user.
public struct SSOSession: Codable, Equatable, Identifiable {
    public let id: String
    public let userId: String
    public let authenticatedAt: String
    public let createdAt: String
    public let lastActiveAt: String
    public let absoluteExpiresAt: String?
    public let idleExpiresAt: String?
    public let creationIp: String?
    public let lastActiveIp: String?
    public let userAgent: String?
    /// Whether this session issued the access token the request was made with. Every session can be
    /// false, for example when the token came from an earlier grant of the same application.
    public let isCurrent: Bool
    /// The applications that have used the session, first joined first.
    public let participants: [SSOSessionParticipant]

    public init(
        id: String,
        userId: String,
        authenticatedAt: String,
        createdAt: String,
        lastActiveAt: String,
        absoluteExpiresAt: String? = nil,
        idleExpiresAt: String? = nil,
        creationIp: String? = nil,
        lastActiveIp: String? = nil,
        userAgent: String? = nil,
        isCurrent: Bool = false,
        participants: [SSOSessionParticipant] = []
    ) {
        self.id = id
        self.userId = userId
        self.authenticatedAt = authenticatedAt
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.absoluteExpiresAt = absoluteExpiresAt
        self.idleExpiresAt = idleExpiresAt
        self.creationIp = creationIp
        self.lastActiveIp = lastActiveIp
        self.userAgent = userAgent
        self.isCurrent = isCurrent
        self.participants = participants
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        authenticatedAt = try container.decode(String.self, forKey: .authenticatedAt)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        lastActiveAt = try container.decode(String.self, forKey: .lastActiveAt)
        absoluteExpiresAt = try container.decodeIfPresent(String.self, forKey: .absoluteExpiresAt)
        idleExpiresAt = try container.decodeIfPresent(String.self, forKey: .idleExpiresAt)
        creationIp = try container.decodeIfPresent(String.self, forKey: .creationIp)
        lastActiveIp = try container.decodeIfPresent(String.self, forKey: .lastActiveIp)
        userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent)
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        participants = try container.decodeIfPresent([SSOSessionParticipant].self, forKey: .participants) ?? []
    }
}

/// A page of SSO sessions returned by `GET /sessions/me`.
public struct SSOSessionListResponse: Codable, Equatable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let sessions: [SSOSession]

    public init(totalResults: Int = 0, startIndex: Int = 0, count: Int = 0, sessions: [SSOSession] = []) {
        self.totalResults = totalResults
        self.startIndex = startIndex
        self.count = count
        self.sessions = sessions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalResults = try container.decodeIfPresent(Int.self, forKey: .totalResults) ?? 0
        startIndex = try container.decodeIfPresent(Int.self, forKey: .startIndex) ?? 0
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        sessions = try container.decodeIfPresent([SSOSession].self, forKey: .sessions) ?? []
    }
}
