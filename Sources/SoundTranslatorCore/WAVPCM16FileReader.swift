import Foundation

public struct WAVPCM16Audio: Equatable, Sendable {
    public let pcm16Data: Data
    public let sampleRate: UInt32
    public let channelCount: UInt16
    public let bitsPerSample: UInt16

    public init(pcm16Data: Data, sampleRate: UInt32, channelCount: UInt16, bitsPerSample: UInt16) {
        self.pcm16Data = pcm16Data
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitsPerSample = bitsPerSample
    }
}

public enum WAVPCM16FileReader {
    public static func read(url: URL) throws -> WAVPCM16Audio {
        try read(Data(contentsOf: url))
    }

    public static func read(_ data: Data) throws -> WAVPCM16Audio {
        guard data.count >= 44,
              string(data, offset: 0, count: 4) == "RIFF",
              string(data, offset: 8, count: 4) == "WAVE"
        else {
            throw SoundTranslatorError.system("The selected file is not a RIFF/WAVE file.")
        }

        var offset = 12
        var formatCode: UInt16?
        var channelCount: UInt16?
        var sampleRate: UInt32?
        var bitsPerSample: UInt16?
        var pcm16Data: Data?

        while offset + 8 <= data.count {
            let chunkID = string(data, offset: offset, count: 4)
            let chunkSize = Int(readUInt32LE(data, offset: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + chunkSize
            guard chunkSize >= 0, chunkEnd <= data.count else {
                throw SoundTranslatorError.system("The WAV file has an invalid chunk size.")
            }

            if chunkID == "fmt " {
                guard chunkSize >= 16 else {
                    throw SoundTranslatorError.system("The WAV file has an invalid fmt chunk.")
                }
                formatCode = readUInt16LE(data, offset: chunkStart)
                channelCount = readUInt16LE(data, offset: chunkStart + 2)
                sampleRate = readUInt32LE(data, offset: chunkStart + 4)
                bitsPerSample = readUInt16LE(data, offset: chunkStart + 14)
            } else if chunkID == "data" {
                pcm16Data = data.subdata(in: chunkStart..<chunkEnd)
            }

            offset = chunkEnd + (chunkSize % 2)
        }

        guard formatCode == 1,
              channelCount == 1,
              sampleRate == 24_000,
              bitsPerSample == 16,
              let pcm16Data,
              !pcm16Data.isEmpty
        else {
            throw SoundTranslatorError.system("Debug WAV must be 24 kHz mono PCM16. Use a WAV saved by Realtime Caption for Mac.")
        }

        return WAVPCM16Audio(
            pcm16Data: pcm16Data,
            sampleRate: 24_000,
            channelCount: 1,
            bitsPerSample: 16
        )
    }

    private static func string(_ data: Data, offset: Int, count: Int) -> String {
        guard offset + count <= data.count else {
            return ""
        }
        return String(decoding: data[offset..<(offset + count)], as: UTF8.self)
    }

    private static func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
