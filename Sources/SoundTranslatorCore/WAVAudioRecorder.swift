import Foundation

public actor WAVAudioRecorder {
    private let sampleRate: UInt32
    private let channelCount: UInt16
    private let bitsPerSample: UInt16
    private var fileHandle: FileHandle?
    private var fileURL: URL?
    private var dataByteCount: UInt32 = 0

    public init(sampleRate: UInt32 = 24_000, channelCount: UInt16 = 1, bitsPerSample: UInt16 = 16) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitsPerSample = bitsPerSample
    }

    public func start(directory: URL, sessionID: String) throws -> URL {
        _ = try stop()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("input-audio-\(Self.sanitized(sessionID)).wav")
        let header = Self.header(
            dataByteCount: 0,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitsPerSample: bitsPerSample
        )
        try header.write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()

        fileHandle = handle
        fileURL = url
        dataByteCount = 0
        return url
    }

    public func append(_ pcm16Data: Data) {
        guard let fileHandle, !pcm16Data.isEmpty else {
            return
        }
        do {
            try fileHandle.write(contentsOf: pcm16Data)
            let nextCount = UInt64(dataByteCount) + UInt64(pcm16Data.count)
            dataByteCount = UInt32(min(nextCount, UInt64(UInt32.max)))
        } catch {
            try? fileHandle.close()
            self.fileHandle = nil
        }
    }

    @discardableResult
    public func stop() throws -> URL? {
        guard let fileHandle, let fileURL else {
            return nil
        }

        let header = Self.header(
            dataByteCount: dataByteCount,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitsPerSample: bitsPerSample
        )
        try fileHandle.seek(toOffset: 0)
        try fileHandle.write(contentsOf: header)
        try fileHandle.close()

        self.fileHandle = nil
        self.fileURL = nil
        self.dataByteCount = 0
        return fileURL
    }

    private static func header(
        dataByteCount: UInt32,
        sampleRate: UInt32,
        channelCount: UInt16,
        bitsPerSample: UInt16
    ) -> Data {
        let byteRate = sampleRate * UInt32(channelCount) * UInt32(bitsPerSample) / 8
        let blockAlign = channelCount * bitsPerSample / 8
        var data = Data()
        data.append(Data("RIFF".utf8))
        data.append(littleEndian(UInt32(36) + dataByteCount))
        data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8))
        data.append(littleEndian(UInt32(16)))
        data.append(littleEndian(UInt16(1)))
        data.append(littleEndian(channelCount))
        data.append(littleEndian(sampleRate))
        data.append(littleEndian(byteRate))
        data.append(littleEndian(blockAlign))
        data.append(littleEndian(bitsPerSample))
        data.append(Data("data".utf8))
        data.append(littleEndian(dataByteCount))
        return data
    }

    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = value.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
        return sanitized.isEmpty ? UUID().uuidString : sanitized
    }
}
