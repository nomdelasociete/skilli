import Foundation
import os

/// What the main-thread watchdog does at each of its ticks
/// (`MainThreadWatchdog`, in the app): the main run loop is asked to answer;
/// an ask left unanswered for `held` seconds is a main thread that is held.
/// Its stacks are captured once, then skil.li is relaunched at the next tick
/// if it is still held.
///
/// Times are seconds the Mac was awake (they stop while it sleeps: a night
/// asleep is not a main thread held).
public struct HangWatch: Sendable, Equatable {
    /// Between two ticks.
    public static let tick: Double = 5
    /// An ask unanswered this long: the main thread is held.
    public static let held: Double = 30
    /// Between two relaunches: a main thread held at each launch does not
    /// make skil.li start over and over.
    public static let relaunchSpacing: Double = 600

    public enum Step: Equatable, Sendable {
        /// Ask the main run loop to answer.
        case ask
        /// An ask is out, or nothing more to do for a main thread held.
        case wait
        /// Held: write its stacks down.
        case capture
        /// Still held once captured: start skil.li again.
        case relaunch
    }

    /// When the ask not answered yet was made.
    private var asked: Double?
    private var captured = false

    public init() {}

    /// The main run loop answered: it runs.
    public mutating func answered() {
        asked = nil
        captured = false
    }

    /// - Parameters:
    ///   - recording: a meeting is being recorded; its files are written off
    ///     the main thread, and a relaunch would cut it short.
    ///   - sinceRelaunch: seconds since the watchdog last relaunched skil.li,
    ///     nil when it never did.
    public mutating func tick(now: Double, recording: Bool, sinceRelaunch: Double?) -> Step {
        guard let asked else {
            self.asked = now
            return .ask
        }
        guard now - asked >= Self.held else { return .wait }
        guard captured else {
            captured = true
            return .capture
        }
        if recording { return .wait }
        if let sinceRelaunch, sinceRelaunch >= 0, sinceRelaunch < Self.relaunchSpacing { return .wait }
        return .relaunch
    }
}

/// Whether a meeting records, as the watchdog reads it from its own queue,
/// and the relaunch itself, one after the other and never both: said
/// recording before a first file is made, a meeting waits for a relaunch
/// under way (which ends the process) and a relaunch finds the meeting.
public final class RecordingGate: Sendable {
    private let recording = OSAllocatedUnfairLock(initialState: false)

    public init() {}

    public var isRecording: Bool {
        get { recording.withLock { $0 } }
        set { recording.withLock { $0 = newValue } }
    }

    /// Runs `body` with the state held, unless a meeting records.
    /// `isRecording` set meanwhile waits for `body` to end.
    @discardableResult
    public func unlessRecording(_ body: @Sendable () -> Void) -> Bool {
        recording.withLock { recording in
            guard !recording else { return false }
            body()
            return true
        }
    }
}
