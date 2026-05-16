import Foundation
import SoundTranslatorCore

actor AudioSendBuffer {
    private let translator: RealtimeTranslator
    private let maxPendingBytes: Int
    private var pending = Data()
    private var isFlushing = false

    init(translator: RealtimeTranslator, maxPendingBytes: Int = 96_000) {
        self.translator = translator
        self.maxPendingBytes = maxPendingBytes
    }

    func enqueue(_ data: Data) async {
        guard !data.isEmpty else {
            return
        }
        appendBounded(data)
        guard !isFlushing else {
            return
        }
        isFlushing = true
        await flush()
    }

    private func appendBounded(_ data: Data) {
        pending.append(data)
        if pending.count > maxPendingBytes {
            pending.removeFirst(pending.count - maxPendingBytes)
        }
    }

    private func flush() async {
        while !pending.isEmpty {
            let chunk = pending
            pending.removeAll(keepingCapacity: true)
            await translator.sendAudio(chunk)
        }
        isFlushing = false
    }
}
