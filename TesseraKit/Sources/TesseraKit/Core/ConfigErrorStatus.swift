import Foundation

/// The most recent config.json load failure, as the daemon records it for the
/// menu app to show. Present only while the last load failed.
public struct ConfigErrorRecord: Codable, Sendable, Equatable {
    /// Path of the config file that failed to parse.
    public var path: String
    /// Human-readable reason (decoder message, including the offending key when known).
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// Shares the last config load error between the daemon (writer) and the menu
/// app (reader) through one small JSON file in the shared Application Support
/// folder. A file rather than IPC because the menu polls state anyway, the
/// daemon may not be running when the menu needs to show the warning, and the
/// file survives a daemon restart until the next successful load clears it.
public enum ConfigErrorStatus {
    /// `~/Library/Application Support/Tessera/config-error.json`.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tessera/config-error.json")
    }

    /// Decode `data` as `type`. On failure, returns a nil value and a record
    /// carrying a readable reason; on success returns the value and no record.
    public static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        path: String
    ) -> (value: T?, error: ConfigErrorRecord?) {
        do {
            return (try JSONDecoder().decode(type, from: data), nil)
        } catch {
            return (nil, ConfigErrorRecord(path: path, message: describe(error)))
        }
    }

    /// Turn a decoding error into a one-line reason, keeping the key path when
    /// the decoder reports one (e.g. `gapSize: Expected Double ...`).
    public static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        let context: DecodingError.Context
        switch decodingError {
        case .typeMismatch(_, let c), .valueNotFound(_, let c),
             .keyNotFound(_, let c), .dataCorrupted(let c):
            context = c
        @unknown default:
            return "\(decodingError)"
        }
        let keyPath = context.codingPath.map(\.stringValue).joined(separator: ".")
        return keyPath.isEmpty
            ? context.debugDescription
            : "\(keyPath): \(context.debugDescription)"
    }

    /// Write the record, or remove the file when `record` is nil. Failures are
    /// ignored: the warning is best-effort and must never affect config loading.
    public static func save(_ record: ConfigErrorRecord?, to url: URL = defaultURL) {
        let fm = FileManager.default
        guard let record else {
            try? fm.removeItem(at: url)
            return
        }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The recorded error, or nil when the file is missing or unreadable.
    public static func read(from url: URL = defaultURL) -> ConfigErrorRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ConfigErrorRecord.self, from: data)
    }
}
