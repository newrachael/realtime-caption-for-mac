import Foundation

enum DiagnosticsLogger {
    static func resetSession(id: String) {
        write("SESSION_START id=\(id)")
    }

    static func log(_ message: String) {
        write(message)
    }

    private static func write(_ line: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SoundTranslator", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent("diagnostics.log")
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let data = Data("\(timestamp) \(line)\n".utf8)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            // Diagnostics must never interrupt capture or translation.
        }
    }
}
