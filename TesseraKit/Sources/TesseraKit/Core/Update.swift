import Foundation

/// A published update as described by the release pipeline's `appcast.json`
/// (attached to each GitHub release; see `scripts/build_release.sh`).
public struct UpdateReleaseInfo: Codable, Sendable, Equatable {
    public var version: String
    public var tag: String
    public var url: String
    public var sha256: String
    public var size: Int

    public init(version: String, tag: String, url: String, sha256: String, size: Int) {
        self.version = version
        self.tag = tag
        self.url = url
        self.sha256 = sha256
        self.size = size
    }
}

/// Semantic-ish version comparison for Tessera tags (`v0.4.0`, `0.5`, `1.2.3`).
/// Components are compared numerically left to right; missing components read 0,
/// and any leading `v` is ignored.
public enum ReleaseVersion {
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) > 0
    }

    /// -1 / 0 / 1: lhs < / == / > rhs.
    public static func compare(_ lhs: String, _ rhs: String) -> Int {
        let a = components(lhs)
        let b = components(rhs)
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    private static func components(_ version: String) -> [Int] {
        let cleaned = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return cleaned
            .split(separator: ".", omittingEmptySubsequences: true)
            .prefix(3)
            .map { component in
                let digits = component.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }
}

/// Discovers and parses the update published for the latest GitHub release.
public enum UpdateChecker {
    public static let releasesLatestURL = URL(string: "https://api.github.com/repos/Spidey03/tessera/releases/latest")!

    /// Fetch the latest release's appcast (the `appcast.json` release asset) and
    /// return it only when it describes a version newer than `currentVersion`.
    /// Throws on network/parse failures; returns nil when the release asset is
    /// missing or the version is not newer.
    public static func fetchLatestReleaseInfo(currentVersion: String,
                                              session: URLSession = .shared,
                                              latestURL: URL = releasesLatestURL) async throws -> UpdateReleaseInfo? {
        var request = URLRequest(url: latestURL)
        request.setValue("TesseraUpdater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let assets = json?["assets"] as? [[String: Any]] else { return nil }
        guard let appcast = assets.first(where: { ($0["name"] as? String) == "appcast.json" }),
              let urlString = appcast["browser_download_url"] as? String,
              let url = URL(string: urlString) else { return nil }
        let (appcastData, _) = try await session.data(from: url)
        return try UpdateAppcast.parse(appcastData, currentVersion: currentVersion)
    }
}

/// Pure parsing/decision logic, isolated so the test suite can exercise it
/// without network access.
public enum UpdateAppcast {
    public static func parse(_ data: Data, currentVersion: String) throws -> UpdateReleaseInfo? {
        let info = try JSONDecoder().decode(UpdateReleaseInfo.self, from: data)
        guard ReleaseVersion.isNewer(info.version, than: currentVersion) else { return nil }
        return info
    }
}

/// Downloads and stages an update package for installation. The swap itself is
/// performed by a detached helper after the menu app exits (see AutoUpdater).
public enum AppInstallerError: Error, Equatable {
    case downloadFailed
    case extractionFailed
    case invalidPackage(String)
}

public enum AppInstaller {
    /// Download the update zip to a unique file in the temp dir.
    public static func download(_ info: UpdateReleaseInfo,
                                session: URLSession = .shared) async throws -> URL {
        guard let url = URL(string: info.url) else { throw AppInstallerError.downloadFailed }
        var request = URLRequest(url: url)
        request.setValue("TesseraUpdater/\(info.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppInstallerError.downloadFailed
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("TesseraUpdate-\(info.version).zip")
        try data.write(to: file)
        return file
    }

    /// Extract `Tessera.app` from the zip into a staging folder and return its
    /// URL after verifying the executables are present and non-empty.
    public static func stage(zipURL: URL) throws -> URL {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("TesseraStage-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, stage.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AppInstallerError.extractionFailed }

        let app = stage.appendingPathComponent("Tessera.app")
        for binary in ["TesseraMenu", "TesseraDaemon"] {
            let url = app.appendingPathComponent("Contents/MacOS/\(binary)")
            guard fm.isReadableFile(atPath: url.path) else {
                throw AppInstallerError.invalidPackage("missing \(binary)")
            }
        }
        return app
    }
}