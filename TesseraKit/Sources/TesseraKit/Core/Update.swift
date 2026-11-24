import CryptoKit
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
    /// The appcast must carry a valid `appcast.json.sig`. Throws on network,
    /// signature or parse failures; returns nil when the release asset is
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
        guard let sigAsset = assets.first(where: { ($0["name"] as? String) == "appcast.json.sig" }),
              let sigString = sigAsset["browser_download_url"] as? String,
              let sigURL = URL(string: sigString) else { throw UpdateVerificationError.missingSignature }
        let (appcastData, _) = try await session.data(from: url)
        let (signature, _) = try await session.data(from: sigURL)
        try UpdateVerifier.verifySignature(of: appcastData, signature: signature)
        return try UpdateAppcast.parse(appcastData, currentVersion: currentVersion)
    }
}

public enum UpdateVerificationError: LocalizedError, Equatable {
    case missingSignature
    case invalidSignature
    case sizeMismatch
    case checksumMismatch

    public var errorDescription: String? {
        switch self {
        case .missingSignature: return "The update is not signed."
        case .invalidSignature: return "The update's signature is not valid."
        case .sizeMismatch: return "The downloaded update has the wrong size."
        case .checksumMismatch: return "The downloaded update does not match its signed checksum."
        }
    }
}

/// Trust root for updates. The release only holds the signed appcast; the key
/// that verifies it ships inside the installed app, so changing a release is
/// not enough to push an update. The appcast's sha256 extends that to the zip.
public enum UpdateVerifier {
    /// Base64 Ed25519 public key. `scripts/build_release.sh` reads this line.
    public static let publicKeyBase64 = "4xGHl1YdDs1cS4Av8MXwkJ8g5PVHPg/0g27nh3gqBtQ="

    /// `signature` is the base64 text of `appcast.json.sig`.
    public static func verifySignature(of data: Data, signature: Data,
                                       publicKeyBase64: String = publicKeyBase64) throws {
        let text = String(decoding: signature, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sig = Data(base64Encoded: text),
              let rawKey = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey),
              key.isValidSignature(sig, for: data)
        else { throw UpdateVerificationError.invalidSignature }
    }

    public static func verifyPackage(_ data: Data, matches info: UpdateReleaseInfo) throws {
        guard data.count == info.size else { throw UpdateVerificationError.sizeMismatch }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == info.sha256.lowercased() else { throw UpdateVerificationError.checksumMismatch }
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
    /// Download the update zip to a unique file in the temp dir. Nothing is
    /// written unless it matches the signed appcast's size and sha256.
    public static func download(_ info: UpdateReleaseInfo,
                                session: URLSession = .shared) async throws -> URL {
        guard let url = URL(string: info.url) else { throw AppInstallerError.downloadFailed }
        var request = URLRequest(url: url)
        request.setValue("TesseraUpdater/\(info.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppInstallerError.downloadFailed
        }
        try UpdateVerifier.verifyPackage(data, matches: info)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("TesseraUpdate-\(UUID().uuidString).zip")
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