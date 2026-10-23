// Measurement probe, not app code: who spoke when in a 16 kHz mono file,
// by FluidAudio's offline pipeline or Argmax's SpeakerKit. Writes the
// segments as JSON.
//
//   diarprobe --tool fluid|speakerkit --file them.wav --out out.json [--speakers N | --max-speakers N]
import AVFoundation
import FluidAudio
import Foundation
import SpeakerKit

struct Segment: Codable { let speaker: String; let start: Double; let end: Double }
struct Output: Codable {
    let tool: String
    let file: String
    let speakersGiven: Int?
    let audioSeconds: Double
    let loadSeconds: Double
    let wallSeconds: Double
    let maxRSSMB: Double
    let segments: [Segment]
}

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), a.indices.contains(i + 1) else { return nil }
    return a[i + 1]
}

func maxRSSMB() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_maxrss) / 1_048_576
}

func samples16k(_ path: String) throws -> [Float] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path), commonFormat: .pcmFormatFloat32, interleaved: false)
    precondition(file.processingFormat.sampleRate == 16000 && file.processingFormat.channelCount == 1, "16 kHz mono expected")
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

let tool = arg("--tool") ?? "fluid"
guard let path = arg("--file"), let out = arg("--out") else {
    FileHandle.standardError.write(Data("usage: diarprobe --tool fluid|speakerkit --file in.wav --out out.json [--speakers N]\n".utf8))
    exit(2)
}
let speakers = arg("--speakers").flatMap(Int.init)
/// FluidAudio only: at most N (an attendee may never speak).
let maxSpeakers = arg("--max-speakers").flatMap(Int.init)
let audio = try samples16k(path)

var segments: [Segment] = []
let loadStart = Date()
var started = Date()
switch tool {
case "fluid":
    var config = OfflineDiarizerConfig()
    if let speakers { config = config.withSpeakers(exactly: speakers) }
    if let maxSpeakers { config = config.withSpeakers(max: maxSpeakers) }
    let manager = OfflineDiarizerManager(config: config)
    try await manager.prepareModels()
    started = Date()
    let result = try await manager.process(audio: audio)
    segments = result.segments.map { Segment(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds)) }
case "speakerkit":
    let kit = try await SpeakerKit()
    try await kit.ensureModelsLoaded()
    started = Date()
    let options = PyannoteDiarizationOptions(numberOfSpeakers: speakers)
    let result = try await kit.diarize(audioArray: audio, options: options)
    segments = result.segments.map { Segment(speaker: $0.speaker.description, start: Double($0.startTime), end: Double($0.endTime)) }
default:
    FileHandle.standardError.write(Data("unknown tool\n".utf8))
    exit(2)
}
let wall = Date().timeIntervalSince(started)
let output = Output(tool: tool, file: path, speakersGiven: speakers ?? maxSpeakers, audioSeconds: Double(audio.count) / 16000,
                    loadSeconds: started.timeIntervalSince(loadStart), wallSeconds: wall, maxRSSMB: maxRSSMB(), segments: segments)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted]
try encoder.encode(output).write(to: URL(fileURLWithPath: out))
print(String(format: "%@ %.0fs audio in %.1fs (x%.0f), %d segments, %d speakers, rss %.0f MB", tool, output.audioSeconds, wall,
             output.audioSeconds / wall, segments.count, Set(segments.map(\.speaker)).count, maxRSSMB()))
