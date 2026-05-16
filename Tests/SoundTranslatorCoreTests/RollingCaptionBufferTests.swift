import Testing
@testable import SoundTranslatorCore

@Test func rollingCaptionKeepsLiveTextContinuous() {
    var buffer = RollingCaptionBuffer()

    #expect(buffer.appendDelta("Hello") == "Hello")
    #expect(buffer.appendDelta(", world") == "Hello, world")
}

@Test func rollingCaptionKeepsCompletedAndLiveLines() {
    var buffer = RollingCaptionBuffer(maxCommittedLines: 2)

    _ = buffer.appendDelta("First sentence")
    #expect(buffer.complete("First sentence.") == "First sentence.")
    #expect(buffer.appendDelta(" Second") == "First sentence. Second")
}

@Test func rollingCaptionDoesNotShrinkToShortDoneEvent() {
    var buffer = RollingCaptionBuffer()

    _ = buffer.appendDelta("This is already a longer caption")
    #expect(buffer.complete("caption") == "This is already a longer caption")
}

@Test func rollingCaptionAppendsCompletedSegments() {
    var buffer = RollingCaptionBuffer()

    #expect(buffer.complete("Hello") == "Hello")
    #expect(buffer.complete("world") == "Hello world")
}

@Test func rollingCaptionReplacesWhenCompletedTranscriptIsFuller() {
    var buffer = RollingCaptionBuffer()

    #expect(buffer.complete("Hello") == "Hello")
    #expect(buffer.complete("Hello world") == "Hello world")
}

@Test func rollingCaptionTreatsFullDeltaAsReplacement() {
    var buffer = RollingCaptionBuffer()

    #expect(buffer.appendDelta("Hello") == "Hello")
    #expect(buffer.appendDelta("Hello world") == "Hello world")
}

@Test func rollingCaptionAccumulatesSingleCharacterDeltas() {
    var buffer = RollingCaptionBuffer()

    #expect(buffer.appendDelta("안") == "안")
    #expect(buffer.appendDelta("녕") == "안녕")
    #expect(buffer.appendDelta("하") == "안녕하")
    #expect(buffer.appendDelta("세") == "안녕하세")
    #expect(buffer.appendDelta("요") == "안녕하세요")
}

@Test func rollingCaptionAccumulatesRealtimeWordDeltas() {
    var buffer = RollingCaptionBuffer()
    let deltas = ["How", " much", " I've", " looked", " for", " you", ",", " do", " you", " even", " know", "?"]

    let output = deltas.reduce("") { _, delta in
        buffer.appendDelta(delta)
    }

    #expect(output == "How much I've looked for you, do you even know?")
}
