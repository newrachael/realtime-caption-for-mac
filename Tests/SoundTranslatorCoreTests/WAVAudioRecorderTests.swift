import Foundation
import Testing
@testable import SoundTranslatorCore

@Test func wavAudioRecorderWritesPcm16WaveFile() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SoundTranslatorTests-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let recorder = WAVAudioRecorder()
    let pcm = Data([0x01, 0x00, 0x02, 0x00])
    let url = try await recorder.start(directory: directory, sessionID: "test-session")
    await recorder.append(pcm)
    let stoppedURL = try await recorder.stop()

    #expect(stoppedURL == url)

    let data = try Data(contentsOf: url)
    #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
    #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
    #expect(String(decoding: data[36..<40], as: UTF8.self) == "data")
    #expect(readUInt32LE(data, offset: 24) == 24_000)
    #expect(readUInt16LE(data, offset: 22) == 1)
    #expect(readUInt16LE(data, offset: 34) == 16)
    #expect(readUInt32LE(data, offset: 40) == UInt32(pcm.count))
    #expect(Data(data.suffix(pcm.count)) == pcm)
}

@Test func wavPCM16FileReaderReadsRecorderOutput() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SoundTranslatorTests-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let recorder = WAVAudioRecorder()
    let pcm = Data([0x10, 0x00, 0x20, 0x00, 0x30, 0x00])
    let url = try await recorder.start(directory: directory, sessionID: "reader-session")
    await recorder.append(pcm)
    try await recorder.stop()

    let audio = try WAVPCM16FileReader.read(url: url)
    #expect(audio.pcm16Data == pcm)
    #expect(audio.sampleRate == 24_000)
    #expect(audio.channelCount == 1)
    #expect(audio.bitsPerSample == 16)
}

@Test func wavPCM16FileReaderRejectsUnsupportedFormat() throws {
    var data = Data("not a wav".utf8)
    #expect(throws: SoundTranslatorError.self) {
        _ = try WAVPCM16FileReader.read(data)
    }
    data.removeAll()
}

private func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
    UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}
