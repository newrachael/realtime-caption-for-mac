import Foundation
import Testing
@testable import SoundTranslatorCore

@Test func parsesOutputTranscriptDelta() throws {
    let payload = #"{"type":"session.output_transcript.delta","delta":"안녕하세요"}"#.data(using: .utf8)!
    let event = try RealtimeEventParser().parse(payload)
    #expect(event == .outputTranscriptDelta("안녕하세요"))
}

@Test func parsesOutputAudioDelta() throws {
    let payload = #"{"type":"session.output_audio.delta","delta":"AQID"}"#.data(using: .utf8)!
    let event = try RealtimeEventParser().parse(payload)
    #expect(event == .outputAudioDelta(Data([0x01, 0x02, 0x03])))
}

@Test func parsesInputTranscriptDelta() throws {
    let payload = #"{"type":"session.input_transcript.delta","delta":"hello"}"#.data(using: .utf8)!
    let event = try RealtimeEventParser().parse(payload)
    #expect(event == .inputTranscriptDelta("hello"))
}

@Test func buildsAppendAudioEvent() throws {
    let data = RealtimeOutboundEvent.appendAudio(Data([0x01, 0x02, 0x03]))
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(object?["type"] as? String == "session.input_audio_buffer.append")
    #expect(object?["audio"] as? String == "AQID")
}

@Test func buildsSessionUpdateEvent() throws {
    let data = RealtimeOutboundEvent.sessionUpdate(targetLanguage: "ko")
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let session = object?["session"] as? [String: Any]
    let audio = session?["audio"] as? [String: Any]
    let output = audio?["output"] as? [String: Any]

    #expect(object?["type"] as? String == "session.update")
    #expect(output?["language"] as? String == "ko")
}

@Test func parsesDoneTranscriptAliases() throws {
    let payload = #"{"type":"response.output_audio_transcript.done","transcript":"Hello world."}"#.data(using: .utf8)!
    let event = try RealtimeEventParser().parse(payload)
    #expect(event == .outputTranscriptCompleted("Hello world."))
}

@Test func parsesOutputTranscriptPatternAliases() throws {
    let payload = #"{"type":"translation.output_transcript.delta","text":"안녕하세요"}"#.data(using: .utf8)!
    let event = try RealtimeEventParser().parse(payload)
    #expect(event == .outputTranscriptDelta("안녕하세요"))
}

@Test func parsesNestedTranscriptText() throws {
    let payload = #"{"type":"session.output_transcript.delta","item":{"content":{"text":"반갑습니다"}}}"#.data(using: .utf8)!
    let event = try RealtimeEventParser().parse(payload)
    #expect(event == .outputTranscriptDelta("반갑습니다"))
}
