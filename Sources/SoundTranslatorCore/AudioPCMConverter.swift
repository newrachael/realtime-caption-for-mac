@preconcurrency import AVFoundation
import CoreMedia
import Foundation

public final class AudioPCMConverter: @unchecked Sendable {
    private let targetSampleRate: Double
    private let targetChannelCount: AVAudioChannelCount

    public init(targetSampleRate: Double = 24_000, targetChannelCount: AVAudioChannelCount = 1) {
        self.targetSampleRate = targetSampleRate
        self.targetChannelCount = targetChannelCount
    }

    public func convert(sampleBuffer: CMSampleBuffer) throws -> Data {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let sourceStreamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            throw SoundTranslatorError.audioConversionFailed
        }

        var sourceASBD = sourceStreamDescription.pointee
        guard let sourceFormat = AVAudioFormat(streamDescription: &sourceASBD),
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: targetSampleRate,
                channels: targetChannelCount,
                interleaved: true
              )
        else {
            throw SoundTranslatorError.audioConversionFailed
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0 else {
            return Data()
        }

        let audioBufferListSize = AudioBufferList.sizeInBytes(maximumBuffers: Int(max(sourceASBD.mChannelsPerFrame, 1)))
        let rawAudioBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: audioBufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            rawAudioBufferList.deallocate()
        }

        var retainedBlockBuffer: CMBlockBuffer?
        let bufferList = rawAudioBufferList.assumingMemoryBound(to: AudioBufferList.self)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferList,
            bufferListSize: audioBufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else {
            throw SoundTranslatorError.audioConversionFailed
        }

        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            bufferListNoCopy: bufferList,
            deallocator: nil
        ) else {
            throw SoundTranslatorError.audioConversionFailed
        }
        sourceBuffer.frameLength = frameCount

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw SoundTranslatorError.audioConversionFailed
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(frameCount) * ratio) + 512
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            throw SoundTranslatorError.audioConversionFailed
        }

        let inputState = ConverterInputState(buffer: sourceBuffer)
        var conversionError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if inputState.didProvideInput {
                status.pointee = .noDataNow
                return nil
            }
            inputState.didProvideInput = true
            status.pointee = .haveData
            return inputState.buffer
        }

        converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
        if conversionError != nil {
            throw SoundTranslatorError.audioConversionFailed
        }

        guard let dataPointer = outputBuffer.audioBufferList.pointee.mBuffers.mData else {
            return Data()
        }
        let byteCount = Int(outputBuffer.audioBufferList.pointee.mBuffers.mDataByteSize)
        return Data(bytes: dataPointer, count: byteCount)
    }
}

private final class ConverterInputState: @unchecked Sendable {
    var didProvideInput = false
    let buffer: AVAudioPCMBuffer

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
