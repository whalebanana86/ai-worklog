import Foundation

/// Stable release versions only; prereleases must not be offered as updates.
public struct AppVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct AppRelease: Decodable, Sendable {
    public let tagName: String
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool
    public var assets: [Asset] = []

    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browserDownloadURL: URL
        public let size: Int64
        public let digest: String?
        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try c.decode(String.self, forKey: .tagName)
        htmlURL = try c.decode(URL.self, forKey: .htmlURL)
        draft = try c.decode(Bool.self, forKey: .draft)
        prerelease = try c.decode(Bool.self, forKey: .prerelease)
        assets = try c.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    /// Only an exact, release-bound ZIP with a GitHub-provided digest can install.
    public var updateAsset: Asset? {
        guard isStable else { return nil }
        return assets.first { asset in
            let url = asset.browserDownloadURL
            return asset.name == "Igeolnaega-\(version)-macOS.zip" &&
                asset.size > 0 && asset.size <= 100 * 1024 * 1024 &&
                url.scheme == "https" && url.host == "github.com" &&
                url.user == nil && url.password == nil && url.port == nil &&
                url.query == nil && url.fragment == nil &&
                url.path == "/whalebanana86/ai-worklog/releases/download/\(tagName)/\(asset.name)" &&
                UpdateArchive.sha256Digest(asset.digest) != nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", htmlURL = "html_url", draft, prerelease, assets
    }

    public var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }

    public var isStable: Bool {
        !draft && !prerelease && AppVersion(tagName) != nil &&
        htmlURL.scheme == "https" && htmlURL.host == "github.com" &&
        htmlURL.user == nil && htmlURL.password == nil && htmlURL.port == nil &&
        htmlURL.path == "/whalebanana86/ai-worklog/releases/tag/\(tagName)"
    }

    public func isNewer(than current: String) -> Bool {
        guard isStable, let latest = AppVersion(tagName), let installed = AppVersion(current) else { return false }
        return latest > installed
    }
}
