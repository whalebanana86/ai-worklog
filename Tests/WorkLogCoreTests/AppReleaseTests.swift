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
    func testInstallerAssetIsPinnedToReleaseAndRequiresDigest() throws {
        func asset(_ url: String, _ digest: String?) throws -> AppRelease {
            var item: [String: Any] = ["name": "Igeolnaega-1.6.0-macOS.zip", "size": 123, "browser_download_url": url]
            if let digest { item["digest"] = digest }
            let data = try JSONSerialization.data(withJSONObject: [
                "tag_name": "v1.6.0", "html_url": "https://github.com/whalebanana86/ai-worklog/releases/tag/v1.6.0",
                "draft": false, "prerelease": false, "assets": [item]
            ])
            return try JSONDecoder().decode(AppRelease.self, from: data)
        }
        let url = "https://github.com/whalebanana86/ai-worklog/releases/download/v1.6.0/Igeolnaega-1.6.0-macOS.zip"
        let digest = "sha256:" + String(repeating: "a", count: 64)
        XCTAssertNotNil(try asset(url, digest).updateAsset)
        XCTAssertNil(try asset(url, nil).updateAsset)
        XCTAssertNil(try asset(url.replacingOccurrences(of: "download/v1.6.0", with: "download/v1.5.0"), digest).updateAsset)
        XCTAssertNil(try asset(url.replacingOccurrences(of: "github.com", with: "example.com"), digest).updateAsset)
    }

    func testSignatureIsPinnedNextToTheZip() throws {
        func release(_ files: [(name: String, size: Int, tag: String)]) throws -> AppRelease {
            let assets = files.map { file -> [String: Any] in
                ["name": file.name, "size": file.size,
                 "browser_download_url": "https://github.com/whalebanana86/ai-worklog/releases/download/\(file.tag)/\(file.name)"]
            }
            let data = try JSONSerialization.data(withJSONObject: [
                "tag_name": "v1.8.0", "html_url": "https://github.com/whalebanana86/ai-worklog/releases/tag/v1.8.0",
                "draft": false, "prerelease": false, "assets": assets
            ])
            return try JSONDecoder().decode(AppRelease.self, from: data)
        }
        let name = "Igeolnaega-1.8.0-macOS.zip.sig"
        XCTAssertEqual(try release([(name, 89, "v1.8.0")]).signatureAsset?.name, name)
        XCTAssertNil(try release([(name, 89, "v1.7.1")]).signatureAsset)
        XCTAssertNil(try release([(name, 4096, "v1.8.0")]).signatureAsset)
        XCTAssertNil(try release([("Igeolnaega-1.7.1-macOS.zip.sig", 89, "v1.8.0")]).signatureAsset)
        XCTAssertNil(try release([]).signatureAsset)
    }

}
