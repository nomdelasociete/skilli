import AVFoundation
import Foundation
import SkilliCore
import UniformTypeIdentifiers

/// A sound or video file made a recording (docs/meeting-recorder-views.md,
/// phase 4, "Import"): a folder in the Recordings folder as a recording
/// made here, its title the file's name, its date the file's; its sound
/// as one track (`me.m4a`), a video's picture as `screen.mp4`. The file
/// itself stays where it was, untouched. Then transcribed as any
/// recording, voices told apart.
enum RecordingImport {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// What the open panel lists and a drop takes.
    static let types: [UTType] = [.audiovisualContent]

    /// The one track's name, its lane in the window.
    static let laneName = "Sound"

    static func isImportable(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return types.contains { type.conforms(to: $0) }
    }

    /// The recording's folder made for `file` (its sound checked first:
    /// none, nothing made), and the record it starts with.
    static func prepare(_ file: URL, in recordings: Recordings, language: String) async throws -> (folder: URL, record: MeetingRecord) {
        let asset = AVURLAsset(url: file)
        let audio = try? await asset.loadTracks(withMediaType: .audio)
        guard let audio else { throw Failure(message: "“\(file.lastPathComponent)” could not be read.") }
        guard !audio.isEmpty else { throw Failure(message: "“\(file.lastPathComponent)” has no sound to transcribe.") }
        let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let started = values?.creationDate ?? values?.contentModificationDate ?? .now
        let title = file.deletingPathExtension().lastPathComponent
        let folder = try recordings.makeFolder(title: title, started: started)
        var record = MeetingRecord(title: title, started: started, language: language,
                                   recorder: Recordings.ownProcess)
        record.state = .transcribing
        record.unused = [.them]
        record.imported = file.lastPathComponent
        record.speakers = [Voice.me.rawValue: laneName]
        return (folder, record)
    }

    /// `file`'s sound into `folder` as `me.m4a`, a video's picture as
    /// `screen.mp4` (as it is, when MP4 can hold it; else left out);
    /// `meeting.json` written with its length. Each is written under a
    /// staging name and moved in once whole: the window opened meanwhile
    /// never plays or draws a file still being written. A failure takes the
    /// folder away.
    static func copy(_ file: URL, into folder: URL, record: MeetingRecord, progress: @escaping @Sendable (Double) -> Void) async throws -> MeetingRecord {
        do {
            let asset = AVURLAsset(url: file)
            let hasPicture = !((try? await asset.loadTracks(withMediaType: .video)) ?? []).isEmpty
            try await export(asset, preset: AVAssetExportPresetAppleM4A, to: folder.appendingPathComponent(Speaker.me.file), as: .m4a) { done in
                progress(hasPicture ? done * 0.7 : done)
            }
            if hasPicture {
                do {
                    try await export(asset, preset: AVAssetExportPresetPassthrough, to: folder.appendingPathComponent(RecorderPictures.screenFile),
                                     as: .mp4) { done in progress(0.7 + done * 0.3) }
                } catch {
                    Log.trace("Recorder: the picture of “\(file.lastPathComponent)” left out (\(error.localizedDescription))")
                }
            }
            var made = record
            let sound = try AVAudioFile(forReading: folder.appendingPathComponent(Speaker.me.file))
            made.seconds = Double(sound.length) / sound.processingFormat.sampleRate
            made.stopped = .now
            try made.encoded().write(to: folder.appendingPathComponent(Recordings.record), options: .atomic)
            progress(1)
            return made
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// `asset` written to `url` through a staging file beside it (a
    /// leading dot: no list shows it), moved in once whole.
    private static func export(_ asset: AVURLAsset, preset: String, to url: URL, as type: AVFileType,
                               progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure(message: "“\(url.lastPathComponent)” cannot be written from this file.")
        }
        let staging = url.deletingLastPathComponent().appendingPathComponent(".importing-" + url.lastPathComponent)
        try? FileManager.default.removeItem(at: staging)
        let states = session.states(updateInterval: 0.2)
        let watch = Task {
            for await state in states {
                if case .exporting(let done) = state { progress(done.fractionCompleted) }
            }
        }
        defer { watch.cancel() }
        do {
            try await session.export(to: staging, as: type)
            try FileManager.default.moveItem(at: staging, to: url)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }
}
