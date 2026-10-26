// The meeting recorder's crash and quit, for the self-test: compiled only
// with SKILLI_SELFTEST, never in a release.
#if SKILLI_SELFTEST
import AppKit

/// `Skilli recorderchild <recordings folder> <me.wav> [finishing|encoder]`: records as
/// skil.li does (the Mac's sound, a file standing in for the microphone)
/// until it is killed, so the self-test finds a recording never stopped, as
/// a crash or a power cut leaves one; or until it is sent SIGTERM, which
/// quits it as skil.li quits (`NSApp.terminate`, then the recorder's
/// `closeForQuit`). `finishing` or `encoder`: what gets stuck as its files
/// close (`TrackWriter.Stall`). Prints its folder once it records.
@MainActor
enum RecorderChild {
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        guard arguments.dropFirst().first == "recorderchild", arguments.count >= 4 else { return nil }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: arguments[2]), me = URL(fileURLWithPath: arguments[3])
        let recorder = MeetingRecorder(recordings: Recordings(root: root))
        let delegate = Delegate(recorder: recorder)
        app.delegate = delegate
        // As skil.li hears `pkill`: the quit goes through NSApp.
        signal(SIGTERM, SIG_IGN)
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminate.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        terminate.resume()
        recorder.stalls = arguments.dropFirst(4).first.flatMap(TrackWriter.Stall.init(rawValue:))
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
        withExtendedLifetime((recorder, delegate, terminate)) { app.run() }
        return 0
    }

    /// Answers a quit as skil.li's `AppDelegate` does.
    private final class Delegate: NSObject, NSApplicationDelegate {
        let recorder: MeetingRecorder

        init(recorder: MeetingRecorder) {
            self.recorder = recorder
        }

        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            recorder.closeForQuit()
            return .terminateNow
        }
    }
}
#endif
