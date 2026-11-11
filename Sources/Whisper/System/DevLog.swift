import Foundation

/// A plain-text trace of what the recording pipeline decided, written only by
/// the dev build (`debug.log` in its support folder). It records events and
/// numbers, never audio or transcript text.
enum DevLog {
    private static let url = AppPaths.support.appendingPathComponent("debug.log")
    private static let queue = DispatchQueue(label: "sh.looped.whisper.devlog")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: @autoclosure () -> String) {
        guard AppPaths.isDev else { return }
        let line = "\(stamp.string(from: Date())) \(message())\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url)
            }
        }
    }
}
