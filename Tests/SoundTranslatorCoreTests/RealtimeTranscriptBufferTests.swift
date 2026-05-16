import Testing
@testable import SoundTranslatorCore

@Test func realtimeTranscriptBufferAppendsKoreanCharacterDeltasVerbatim() {
    var buffer = RealtimeTranscriptBuffer()
    let deltas = ["여", "러", "분", ",", " 실", "수", "할", "까", " 봐", " 걱", "정", "돼", "요"]

    let output = deltas.reduce("") { _, delta in
        buffer.appendDelta(delta)
    }

    #expect(output == "여러분, 실수할까 봐 걱정돼요")
}

@Test func realtimeTranscriptBufferKeepsSpacingFromRealtimeDeltas() {
    var buffer = RealtimeTranscriptBuffer()
    let deltas = ["인", "문", "계", "가", " 요", "즘", "은", " 잘", " 안", " 하는", "데"]

    let output = deltas.reduce("") { _, delta in
        buffer.appendDelta(delta)
    }

    #expect(output == "인문계가 요즘은 잘 안 하는데")
}

@Test func realtimeTranscriptBufferUsesLongerFinalTranscript() {
    var buffer = RealtimeTranscriptBuffer()

    #expect(buffer.appendDelta("안녕") == "안녕")
    #expect(buffer.complete("안녕하세요.") == "안녕하세요.")
}
