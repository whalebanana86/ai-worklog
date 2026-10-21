import XCTest
@testable import WorkLogCore

final class AppReleaseTests: XCTestCase {
    func testComparesVersionsNumerically() throws {
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("1.10.0")), try XCTUnwrap(AppVersion("1.9.9")))
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("2.0.0")), try XCTUnwrap(AppVersion("1.99.99")))
        XCTAssertEqual(AppVersion("v1.3.0"), AppVersion("1.3.0"))
        for text in ["", "1.0", "1.3.0-beta", "1..0", "-1.2.3", "1.2.3.4", "1.2.3+dev"] {
            XCTAssertNil(AppVersion(text), text)
        }
    }

    func release(tag: String = "v1.3.0", url: String? = nil, draft: Bool = false, prerelease: Bool = false) throws -> AppRelease {
        let data = try JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "html_url": url ?? "https://github.com/whalebanana86/ai-worklog/releases/tag/\(tag)",
            "draft": draft, "prerelease": prerelease
        ])
        return try JSONDecoder().decode(AppRelease.self, from: data)
    }

    func testOffersOnlyNewerStableReleaseFromOurRepository() throws {
        let latest = try release()
        XCTAssertTrue(latest.isNewer(than: "1.1.1"))
        XCTAssertFalse(latest.isNewer(than: "1.3.0"))
        XCTAssertFalse(latest.isNewer(than: "1.4.0"))
        XCTAssertFalse(latest.isNewer(than: "unknown"))
        XCTAssertFalse(try release(draft: true).isStable)
        XCTAssertFalse(try release(prerelease: true).isStable)
        XCTAssertFalse(try release(tag: "v1.4.0-beta").isStable)
        for url in ["https://example.com/update", "http://github.com/whalebanana86/ai-worklog/releases/tag/v1.3.0",
                    "https://github.com/another/repository/releases/tag/v1.3.0"] {
            XCTAssertFalse(try release(url: url).isStable)
        }
    }
}
