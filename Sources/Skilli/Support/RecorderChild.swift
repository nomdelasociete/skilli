// The meeting recorder's crash, for the self-test: compiled only with
// SKILLI_SELFTEST, never in a release.
#if SKILLI_SELFTEST
import AppKit

/// `Skilli recorderchild <recordings folder> <me.wav>`: records as skil.li
/// does (the Mac's sound, a file standing in for the microphone) until it is
/// killed, so the self-test finds a recording never stopped, as a crash or
/// a power cut leaves one. Prints its folder once it records.
@MainActor
enum RecorderChild {
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        guard arguments.dropFirst().first == "recorderchild", arguments.count >= 4 else { return nil }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: arguments[2]), me = URL(fileURLWithPath: arguments[3])
        let recorder = MeetingRecorder(recordings: Recordings(root: root))
        Task { @MainActor in
            recorder.standIn(microphone: me, alsoLeaveOut: [])
            await recorder.listen()
            do {
                try recorder.begin(title: "Never stopped", language: "en-US")
                try recorder.microphone.playStandIn(at: mach_absolute_time())
                print("recording \(recorder.folder?.path ?? "")")
                fflush(stdout)
            } catch {
                FileHandle.standardError.write(Data("recorderchild: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        withExtendedLifetime(recorder) { app.run() }
        return 0
    }
}
#endif
