// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

final class ActiveSessionsTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private let baseUrl = "https://localhost:8090"

    private func makeClient() async throws -> ThunderIDClient {
        let storage = InMemoryStorageAdapter()
        // Mirrors TokenStore's private storage key; seeding it directly skips a real sign-in.
        storage.store(key: "thunder.access_token", value: "test-access-token")
        let client = ThunderIDClient()
        let config = ThunderIDConfig(baseUrl: baseUrl, clientId: "test-client")
        _ = try await client.initialize(config: config, storage: storage, session: MockURLProtocol.makeSession())
        return client
    }

    private func respond(status: Int = 200, body: String = "") {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    private func session(_ id: String, userAgent: String? = nil, isCurrent: Bool = false, app: String? = nil) -> SSOSession {
        SSOSession(
            id: id,
            userId: "user-1",
            authenticatedAt: "2026-10-21T09:00:00Z",
            createdAt: "2026-10-21T09:00:00Z",
            lastActiveAt: "2026-10-21T09:05:00Z",
            userAgent: userAgent,
            isCurrent: isCurrent,
            participants: app.map { [SSOSessionParticipant(appId: "app-1", appName: $0, firstJoinedAt: "", lastActiveAt: "")] } ?? []
        )
    }

    // MARK: - Client

    func testListsSessionsWithPagingAndTheSDKUserAgent() async throws {
        var seen: URLRequest?
        MockURLProtocol.handler = { request in
            seen = request
            let body = #"{"totalResults":1,"startIndex":0,"count":1,"sessions":[{"id":"s1","userId":"u1","#
                + #""authenticatedAt":"a","createdAt":"c","lastActiveAt":"l","isCurrent":true,"#
                + #""participants":[{"appId":"app-1","appName":"Quickstart","firstJoinedAt":"f","lastActiveAt":"l"}]}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        let client = try await makeClient()

        let page = try await client.getUserSessions(limit: 5, offset: 10)

        XCTAssertEqual(page.totalResults, 1)
        XCTAssertEqual(page.sessions.first?.isCurrent, true)
        XCTAssertEqual(page.sessions.first?.participants.first?.appName, "Quickstart")
        XCTAssertEqual(seen?.httpMethod, "GET")
        XCTAssertEqual(seen?.url?.absoluteString, "\(baseUrl)/sessions/me?limit=5&offset=10")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertTrue(seen?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("ThunderID-iOS/") == true)
    }

    func testRevokesOneSessionByEncodedIdentifier() async throws {
        var seen: URLRequest?
        MockURLProtocol.handler = { request in
            seen = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = try await makeClient()

        try await client.revokeUserSession(sessionId: "a/b c")

        XCTAssertEqual(seen?.httpMethod, "DELETE")
        XCTAssertEqual(seen?.url?.absoluteString, "\(baseUrl)/sessions/me/a%2Fb%20c")
    }

    func testRejectsABlankSessionIdentifierBeforeSending() async throws {
        respond(status: 204)
        let client = try await makeClient()

        do {
            try await client.revokeUserSession(sessionId: " ")
            XCTFail("Expected a blank identifier to fail")
        } catch {
            XCTAssertEqual((error as? ThunderIDError)?.code, .invalidInput)
        }
        XCTAssertEqual(MockURLProtocol.requestCount, 0)
    }

    func testReportsASessionThatIsAlreadyGone() async throws {
        respond(status: 404)
        let client = try await makeClient()

        do {
            try await client.revokeUserSession(sessionId: "gone")
            XCTFail("Expected not found")
        } catch {
            XCTAssertEqual((error as? ThunderIDError)?.code, .notFound)
            XCTAssertTrue(isAlreadyRevoked(error))
        }
    }

    func testRevokesEveryOtherSession() async throws {
        var seen: URLRequest?
        MockURLProtocol.handler = { request in
            seen = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = try await makeClient()

        try await client.revokeUserSessions(exceptCurrent: true)

        XCTAssertEqual(seen?.url?.absoluteString, "\(baseUrl)/sessions/me?exceptCurrent=true")
    }

    func testSessionCallsRequireInitialization() async {
        do {
            _ = try await ThunderIDClient().getUserSessions()
            XCTFail("Expected an uninitialized client to fail")
        } catch {
            XCTAssertEqual((error as? ThunderIDError)?.code, .sdkNotInitialized)
        }
    }

    // MARK: - Display

    func testDescribesBrowsersAndMobileSDKs() {
        XCTAssertEqual(
            describeUserAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/129.0 Safari/537.36"),
            UserAgentDescription(browser: "Chrome", os: "macOS")
        )
        XCTAssertEqual(
            describeUserAgent("ThunderID-iOS/1.4.0 (iOS 15.8; iPhone 7)"),
            UserAgentDescription(os: "iOS", device: "iPhone 7", isApp: true)
        )
        XCTAssertEqual(
            describeUserAgent("ThunderID-Android/1.4.0 (Android 11; Redmi Note 8 Pro)"),
            UserAgentDescription(os: "Android", device: "Redmi Note 8 Pro", isApp: true)
        )
        XCTAssertEqual(describeUserAgent(nil), UserAgentDescription())
    }

    func testLabelsADeviceByTheClientAndThePlace() {
        let i18n = ThunderIDI18n()
        XCTAssertEqual(
            deviceLabel(session("s1", userAgent: "ThunderID-iOS/1.4.0 (iOS 15.8; iPhone 7)", app: "Quickstart"), i18n: i18n),
            "iPhone 7"
        )
        XCTAssertEqual(
            deviceLabel(session("s1", userAgent: "ThunderID-iOS/1.4.0 (iOS 15.8)", app: "Quickstart"), i18n: i18n),
            "Quickstart on iOS"
        )
        XCTAssertEqual(
            deviceLabel(session("s2", userAgent: "Mozilla/5.0 (Windows NT 10.0) Firefox/131.0"), i18n: i18n),
            "Firefox on Windows"
        )
        XCTAssertEqual(deviceLabel(session("s3"), i18n: i18n), "Unknown device")
    }

    func testTitlesARowByTheBrowserTheDeviceOrTheApplication() {
        let i18n = ThunderIDI18n()
        XCTAssertEqual(
            clientLabel(session("s1", userAgent: "Mozilla/5.0 (Windows NT 10.0) Firefox/131.0", app: "Console"), i18n: i18n),
            "Firefox"
        )
        XCTAssertEqual(
            clientLabel(session("s2", userAgent: "ThunderID-iOS/1.4.0 (iOS 18.0; iPhone 16)", app: "Quickstart"), i18n: i18n),
            "iPhone 16"
        )
        XCTAssertEqual(clientLabel(session("s3", userAgent: "ThunderID-iOS/1.4.0 (iOS 18.0)", app: "Quickstart"), i18n: i18n), "Quickstart")
        XCTAssertEqual(clientLabel(session("s4"), i18n: i18n), "Unknown device")
    }

    func testParsesSVGPathDataIncludingArcsAndCompactNumbers() {
        // Lucide's circle: two relative and absolute arcs that should trace the full 20 point circle.
        let circle = parseSVGPath("M22 12A10 10 0 1 1 2 12a10 10 0 0 1 20 0z").boundingRect
        XCTAssertEqual(circle.minX, 2, accuracy: 0.01)
        XCTAssertEqual(circle.minY, 2, accuracy: 0.01)
        XCTAssertEqual(circle.width, 20, accuracy: 0.01)
        XCTAssertEqual(circle.height, 20, accuracy: 0.01)

        // `h-.5.5` style runs: numbers that start with a sign or a second decimal point.
        let square = parseSVGPath("M1 1h2v2h-2z").boundingRect
        XCTAssertEqual(square, CGRect(x: 1, y: 1, width: 2, height: 2))
        XCTAssertEqual(parseSVGPath("M.5.5l1-.5").boundingRect, CGRect(x: 0.5, y: 0, width: 1, height: 0.5))
    }

    func testFindsLogosForTheBrowsersAndSystemsItNames() {
        XCTAssertNotNil(browserLogo("Chrome"))
        XCTAssertTrue(browserLogo("Safari")?.outlined == true)
        XCTAssertNil(browserLogo("Edge"))
        XCTAssertNil(browserLogo(nil))
        for os in ["iOS", "macOS", "Android", "Windows", "Linux", "ChromeOS"] {
            XCTAssertNotNil(osLogo(os), os)
        }
    }

    func testGroupsByOperatingSystemWithTheCurrentGroupFirst() {
        let groups = groupSessionsByOS([
            session("s1", userAgent: "Mozilla/5.0 (Windows NT 10.0) Firefox/131.0"),
            session("s2", userAgent: "ThunderID-iOS/1.4.0 (iOS 15.8; iPhone 7)", isCurrent: true),
            session("s3", userAgent: "Mozilla/5.0 (Windows NT 10.0) Chrome/129.0")
        ])

        XCTAssertEqual(groups.map(\.os), ["iOS", "Windows"])
        XCTAssertEqual(groups.last?.sessions.map(\.id), ["s1", "s3"])
    }

    func testFormatsATimestampOrLeavesItUnchanged() {
        let utc = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        XCTAssertTrue(formatSessionTime("2026-10-21T09:05:00Z", locale: locale, timeZone: utc).contains("2026"))
        XCTAssertTrue(formatSessionTime("2026-10-21T09:05:00.123Z", locale: locale, timeZone: utc).contains("2026"))
        XCTAssertEqual(formatSessionTime("not a date"), "not a date")
    }
}
