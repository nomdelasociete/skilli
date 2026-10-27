import AppKit
import SkilliCore

/// What the user does with a recording once it is written out
/// (docs/meeting-recorder-views.md, "Phase 5"): the summary, the
/// chapters, the action items to Reminders, the recap mail. The user's
/// AI reads the transcript, only on their action; the rest is code. One
/// at a time per recording; the window says what is being done, the card
/// what failed. Made with the recorder's center, used from a recording's
/// ⌘K (and later its links and tools).
@MainActor
final class RecordingFollowUps {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let recordings: Recordings
    private let deletes: UndoableDeletes
    /// The user's AI (Settings → SI Accounts).
    var ai: AIStore?
    /// The user's reminders (Action Items to Reminders).
    var reminders: ReminderBook?
    /// A recording's window when one is open: told what to show.
    var window: (URL) -> RecordingWindowController? = { _ in nil }
    /// One line in the card: a failure, said once.
    var notify: (String) -> Void = { _ in }
    /// The mail app with a new message (the recap); the self-test watches.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// The user's own mail addresses (My Card), left out of the recap's.
    var ownAddresses: () async -> [String] = { [] }
    /// The user's own names (My Card), whose action items are theirs.
    var ownName: () async -> String? = { nil }
    /// The event's attendees' addresses, for a recording made before they
    /// were kept with it.
    var eventAddresses: (MeetingRecord.EventLink) -> [String] = { _ in [] }
    /// Ask about a meeting: the card answers `message` under `title`.
    var askInCard: (_ title: String, _ message: String) -> Void = { _, _ in }
    /// The user's skillies (all of them: those for recordings are picked).
    var skillies: () -> [ScriptCommand] = { [] }
    /// The skillie marked to run after every transcript (its path; empty:
    /// none, Settings → Recorder).
    var marked: () -> String = { "" }
    /// A skillie run as the launcher runs one (its "ask first", the card),
    /// on a recording; `ran` gets how it went.
    var runInCard: (_ skillie: ScriptCommand, _ folder: URL, _ ran: @escaping @MainActor @Sendable (ScriptLibrary.Run) -> Void) -> Void = { _, _, _ in }
    /// A skillie run out of sight (no card), on a recording.
    var runQuietly: (_ skillie: ScriptCommand, _ folder: URL) async throws -> ScriptLibrary.Run = { _, _ in
        throw Failure(message: "Skillies cannot run now.")
    }
    /// Reminders not allowed: macOS's question, or its list in Settings.
    var onPermissionNeeded: (Permission) -> Void = { _ in }
    /// What is being done for each recording now (its folder's path), as
    /// its window says it.
    private(set) var working: [String: String] = [:]

    init(recordings: Recordings, deletes: UndoableDeletes) {
        self.recordings = recordings
        self.deletes = deletes
    }

    private static func key(_ folder: URL) -> String {
        folder.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Who writes for the AI's actions now, as their titles name it.
    var provider: String { ai?.defaultModel.provider.title ?? WritingProvider.claude.title }

    /// What is being done for `folder` now, for a window opening meanwhile.
    func work(for folder: URL) -> String? { working[Self.key(folder)] }

    /// ⌘K's action on the recording in `folder`: done, or why not in the
    /// card. Its answer, for a tool (the summary, the chapters…).
    @discardableResult
    func run(_ action: MeetingFollowUp.Action, on folder: URL, question: String? = nil) async -> String? {
        do {
            return try await perform(action, on: folder, question: question)
        } catch {
            notify(Self.failed(action) + error.localizedDescription)
            return nil
        }
    }

    /// What the window says until the AI is asked.
    private static func starting(_ action: MeetingFollowUp.Action) -> String {
        switch action {
        case .summary: "Writing the summary…"
        case .chapters: "Finding chapters…"
        case .actionItems: "Reading the action items…"
        case .recapMail: "Writing the recap…"
        case .ask: "Answering a question…"
        }
    }

    /// How a failure starts in the card.
    private static func failed(_ action: MeetingFollowUp.Action) -> String {
        switch action {
        case .summary: "The summary was not written: "
        case .chapters: "The chapters were not made: "
        case .actionItems: "The action items were not read: "
        case .recapMail: "The recap was not written: "
        case .ask: "The question was not answered: "
        }
    }

    func perform(_ action: MeetingFollowUp.Action, on folder: URL, question: String? = nil) async throws -> String {
        guard let record = recordings.read(folder), let transcript = recordings.transcript(folder), !transcript.lines.isEmpty else {
            throw Failure(message: "it has no transcript yet.")
        }
        let key = Self.key(folder)
        if let busy = working[key] { throw Failure(message: "one at a time, and this one is \(busy.prefix(1).lowercased() + busy.dropFirst())") }
        // Taken before the first wait (Reminders' question, My Card), given
        // back once the action is done: one at a time, all the way.
        working[key] = Self.starting(action)
        window(folder)?.showWork(Self.starting(action))
        defer {
            working[key] = nil
            window(folder)?.showWork(nil)
        }
        switch action {
        case .summary:
            return try await summarize(folder, record: record, transcript: transcript)
        case .chapters:
            guard record.seconds >= MeetingFollowUp.shortestForChapters else {
                throw Failure(message: "“\(record.title)” is shorter than 3 minutes.")
            }
            return try await chapters(folder, record: record, transcript: transcript)
        case .actionItems:
            return try await actionItems(folder, record: record, transcript: transcript)
        case .recapMail:
            return try await recap(folder, record: record, transcript: transcript)
        case .ask:
            let question = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !question.isEmpty else { throw Failure(message: "there is no question.") }
            let writer = try writer()
            return try await write(MeetingFollowUp.askRequest(question, transcript: text(of: record, transcript, in: folder)), with: writer,
                                   in: folder, doing: "Answering a question")
        }
    }

    /// Ask about a meeting (the window's ⌘K, the launcher's row): the
    /// question and the transcript to Ask's writer, the answer in the card.
    func ask(_ question: String, about folder: URL) {
        guard let record = recordings.read(folder), let transcript = recordings.transcript(folder), !transcript.lines.isEmpty else {
            notify("The question was not answered: the recording has no transcript yet.")
            return
        }
        // One at a time per recording, Ask too.
        if let busy = working[Self.key(folder)] {
            notify("The question was not answered: one at a time, and this one is \(busy.prefix(1).lowercased() + busy.dropFirst())")
            return
        }
        askInCard(record.title, MeetingFollowUp.askRequest(question, transcript: text(of: record, transcript, in: folder)))
    }

    // MARK: - The AI

    /// The user's writer, or why there is none.
    private func writer() throws -> AIStore.Writer {
        guard let ai else { throw Failure(message: "Settings → SI Accounts cannot be read now.") }
        guard let writer = ai.writer(for: nil) else { throw Failure(message: ai.setupMessage(for: nil)) }
        return writer
    }

    /// The meeting as the AI reads it, from its files as they are now.
    private func text(of record: MeetingRecord, _ transcript: MeetingTranscript.File, in folder: URL) -> String {
        let date = record.started.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
        return MeetingFollowUp.transcript(title: record.title, date: date, lines: transcript.lines, names: record.speakers,
                                          slides: RecordingWindowController.slides(in: folder))
    }

    /// `message` written by `writer`, the window saying `doing` meanwhile
    /// (the action's slot, `perform`'s, given back when it is done);
    /// `chunk` gets the text so far.
    private func write(_ message: String, with writer: AIStore.Writer, in folder: URL, doing: String,
                       chunk: ((String) -> Void)? = nil) async throws -> String {
        let said = "\(doing) with \(writer.label)…"
        working[Self.key(folder)] = said
        window(folder)?.showWork(said)
        var text = ""
        Log.trace("Recorder: \(doing.lowercased()) of “\(folder.lastPathComponent)” with \(writer.label)")
        for try await piece in writer.engine.stream(AIRequest(message: message, model: writer.choice)) {
            text += piece
            chunk?(text)
        }
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw Failure(message: "\(writer.choice.provider.title) answered nothing.") }
        return answer
    }

    // MARK: - The summary

    private func summarize(_ folder: URL, record: MeetingRecord, transcript: MeetingTranscript.File) async throws -> String {
        let writer = try writer()
        let header = "SUMMARY BY \(writer.choice.provider.title.uppercased())"
        let before = window(folder)?.summary
        let summary: String
        do {
            summary = try await write(MeetingFollowUp.summaryRequest(text(of: record, transcript, in: folder), language: transcript.language),
                                      with: writer, in: folder, doing: "Writing the summary") { [weak self] text in
                self?.window(folder)?.showSummary(text, header: header + " · writing…")
            }
        } catch {
            // The one before stays.
            if let before { window(folder)?.showSummary(before.text, header: before.header) } else { window(folder)?.showSummary("", header: "") }
            throw error
        }
        try keep(summary, by: writer.label, in: folder)
        return summary
    }

    /// `summary.md` written; one there before goes to the Trash, the undo
    /// card puts it back. The window shows it.
    private func keep(_ summary: String, by: String, in folder: URL) throws {
        guard var record = recordings.read(folder) else { throw Failure(message: "the recording is gone.") }
        let file = folder.appendingPathComponent(Recordings.summary)
        let manager = FileManager.default
        var trashed: NSURL?
        let previous = record.summarized
        if manager.fileExists(atPath: file.path) { try manager.trashItem(at: file, resultingItemURL: &trashed) }
        try MeetingFollowUp.summaryFile(title: record.title, summary: summary).write(to: file, atomically: true, encoding: .utf8)
        record.summarized = MeetingRecord.Summarized(at: .now, by: by)
        try recordings.write(record, to: folder)
        refresh(folder)
        guard let trashed = trashed as URL? else { return }
        deletes.summaryReplaced(record.title, trashed: trashed) { [weak self] in
            guard let self, var record = self.recordings.read(folder) else { throw Failure(message: "The recording is gone.") }
            try? manager.removeItem(at: file)
            try manager.moveItem(at: trashed, to: file)
            record.summarized = previous
            try self.recordings.write(record, to: folder)
            self.refresh(folder)
        }
    }

    /// The summary as `summary.md` has it, nil when there is none.
    func summary(in folder: URL) -> String? {
        (try? String(contentsOf: folder.appendingPathComponent(Recordings.summary), encoding: .utf8))
            .map(MeetingFollowUp.summary(inFile:)).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Chapters

    private func chapters(_ folder: URL, record: MeetingRecord, transcript: MeetingTranscript.File) async throws -> String {
        let writer = try writer()
        let answer = try await write(MeetingFollowUp.chaptersRequest(text(of: record, transcript, in: folder), language: transcript.language),
                                     with: writer, in: folder, doing: "Finding chapters")
        // The lines as they are now: edited meanwhile, the window wrote them.
        let lines = recordings.transcript(folder)?.lines ?? transcript.lines
        guard let chapters = MeetingFollowUp.chapters(from: answer, lines: lines) else {
            throw Failure(message: "\(writer.choice.provider.title) gave no chapters.")
        }
        try setChapters(chapters, in: folder)
        return chapters.map { "\(MeetingTranscript.clock($0.start)) \($0.title)" }.joined(separator: "\n")
    }

    /// `meeting.json`'s chapters and `transcript.md`'s headings, as the
    /// record is on disk now (a window's edits kept).
    private func setChapters(_ chapters: [MeetingRecord.Chapter], in folder: URL) throws {
        guard var record = recordings.read(folder) else { throw Failure(message: "the recording is gone.") }
        record.chapters = chapters
        try recordings.write(record, to: folder)
        if let lines = recordings.transcript(folder)?.lines {
            try MeetingTranscriber.markdown(record, lines: lines).write(to: folder.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        }
        refresh(folder)
    }

    /// Remove Chapters: gone at once, the undo card puts them back.
    func removeChapters(in folder: URL) {
        guard let record = recordings.read(folder), !record.chapters.isEmpty else { return }
        let removed = record.chapters
        do {
            try setChapters([], in: folder)
        } catch {
            notify("The chapters were not removed: \(error.localizedDescription)")
            return
        }
        deletes.chaptersRemoved(record.title, count: removed.count) { [weak self] in
            try self?.setChapters(removed, in: folder)
        }
    }

    // MARK: - Action items

    private func actionItems(_ folder: URL, record: MeetingRecord, transcript: MeetingTranscript.File) async throws -> String {
        guard let reminders else { throw Failure(message: "Reminders cannot be reached now.") }
        if !reminders.isAllowed {
            guard await reminders.allow() else {
                onPermissionNeeded(.reminders)
                throw Failure(message: "skil.li may not add to Reminders: allow it in System Settings → Privacy & Security → Reminders.")
            }
        }
        let writer = try writer()
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: record.started)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let answer = try await write(MeetingFollowUp.actionItemsRequest(text(of: record, transcript, in: folder), language: transcript.language,
                                                                        date: day),
                                     with: writer, in: folder, doing: "Reading the action items")
        let own = [record.speakers[Voice.me.rawValue], await ownName()].compactMap { $0 }.filter { $0 != Voice.me.title }
        guard let items = MeetingFollowUp.actionItems(from: answer, ownNames: own) else {
            throw Failure(message: "\(writer.choice.provider.title)'s answer held no list.")
        }
        guard !items.isEmpty else {
            notify("No action items in “\(record.title)”.")
            return "No action items."
        }
        let when = record.started.formatted(.dateTime.day().month(.abbreviated))
        var added: [ReminderItem] = []
        for item in items {
            let at = item.at.map { ", at \(MeetingTranscript.clock($0))" } ?? ""
            let request = ReminderRequest(title: MeetingFollowUp.reminderTitle(item), due: item.due, notes: "From “\(record.title)”, \(when)\(at)",
                                          url: SkilliLink.openRecording(folder.lastPathComponent, at: item.at).url.absoluteString)
            do {
                added.append(try await reminders.add(request))
            } catch {
                // The ones added stay, with their undo.
                if added.isEmpty { throw error }
                notify("\(added.count) of \(items.count) reminders were added: \(error.localizedDescription)")
                break
            }
        }
        Log.trace("Recorder: \(added.count) reminders added from “\(record.title)”")
        deletes.remindersAdded(added, in: reminders)
        return added.map(\.title).joined(separator: "\n")
    }

    // MARK: - The recap mail

    private func recap(_ folder: URL, record: MeetingRecord, transcript: MeetingTranscript.File) async throws -> String {
        var summary = summary(in: folder)
        if summary == nil {
            let writer = try writer()
            let written = try await write(MeetingFollowUp.summaryRequest(text(of: record, transcript, in: folder), language: transcript.language),
                                          with: writer, in: folder, doing: "Writing the summary for the recap")
            try keep(written, by: writer.label, in: folder)
            summary = written
        }
        let own = Set(await ownAddresses().map { $0.lowercased() })
        let addresses = (record.addresses ?? record.event.map(eventAddresses) ?? []).filter { !own.contains($0.lowercased()) }
        let day = record.started.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let mail = MeetingFollowUp.recap(title: record.title, day: day, plain: CardMarkdown.plainText(summary ?? ""))
        guard let url = ContactBook.mailURL(to: addresses, subject: mail.subject, body: mail.body) else {
            throw Failure(message: "the mail could not be made.")
        }
        openURL(url)
        Log.trace("Recorder: recap of “\(record.title)” to \(addresses.count) addresses")
        return addresses.isEmpty ? "The mail is open, with no one in To." : "The mail is open, to \(addresses.joined(separator: ", "))."
    }

    // MARK: - Skillies for recordings

    /// The user's skillies for recordings (`@skilli.forRecordings`) that
    /// need no argument (nothing would give one), by title.
    func recordingSkillies() -> [ScriptCommand] {
        skillies().filter { $0.forRecordings && !$0.needsArguments }
    }

    /// Those that may run after each transcript, out of sight: never one
    /// that asks before it runs (`needsConfirmation`), whose card would be
    /// skipped.
    nonisolated static func runsOnItsOwn(_ skillie: ScriptCommand) -> Bool {
        skillie.forRecordings && !skillie.needsArguments && !skillie.needsConfirmation
    }

    /// Whether `skillie` is the one marked (`marked`, a path): by the file
    /// it is (`/var` and `/private/var` are one folder).
    nonisolated static func isMarked(_ skillie: ScriptCommand, _ marked: String) -> Bool {
        !marked.isEmpty && URL(fileURLWithPath: skillie.path).resolvingSymlinksInPath().path
            == URL(fileURLWithPath: marked).resolvingSymlinksInPath().path
    }

    /// ⌘K on a recording: the skillie run on it, in the card.
    func run(_ skillie: ScriptCommand, on folder: URL) {
        runInCard(skillie, folder) { [weak self] run in self?.note(skillie, run, on: folder, automatic: false) }
    }

    /// A recording's transcript first made (after Stop, an import, a
    /// launch's transcript; not Transcribe Again): the skillie marked runs on
    /// it once, out of sight; the window says it ran, the card only a
    /// failure (docs/meeting-recorder-views.md, "Skillies for recordings").
    func transcriptDone(_ folder: URL) {
        let path = marked()
        guard !path.isEmpty, let skillie = recordingSkillies().first(where: { Self.isMarked($0, path) }), Self.runsOnItsOwn(skillie),
              let record = recordings.read(folder), record.state == .done,
              !(record.skillies ?? []).contains(where: { $0.automatic && $0.path == skillie.path }) else { return }
        Log.trace("Recorder: “\(skillie.title)” runs after the transcript of “\(record.title)”")
        Task { [weak self] in
            guard let self else { return }
            let run: ScriptLibrary.Run
            do {
                run = try await self.runQuietly(skillie, folder)
            } catch {
                run = ScriptLibrary.Run(output: error.localizedDescription, status: -1)
            }
            self.note(skillie, run, on: folder, automatic: true)
            guard !run.succeeded else { return }
            let line = ScriptCommand.lastLine(run.output)
            self.notify("“\(skillie.title)” failed after the transcript of “\(record.title)”: "
                        + (line.isEmpty ? "exit \(run.status)." : line))
        }
    }

    /// A run kept in `meeting.json` (the last 20), the window told.
    private func note(_ skillie: ScriptCommand, _ run: ScriptLibrary.Run, on folder: URL, automatic: Bool) {
        guard var record = recordings.read(folder) else { return }
        let ran = MeetingRecord.SkillieRun(title: skillie.title, path: skillie.path, at: .now, automatic: automatic, status: run.status,
                                           line: String(ScriptCommand.lastLine(run.output).prefix(200)))
        record.skillies = Array(((record.skillies ?? []) + [ran]).suffix(20))
        try? recordings.write(record, to: folder)
        refresh(folder)
    }

    // MARK: - The window

    /// The window shows the recording as its files are now.
    private func refresh(_ folder: URL) {
        NotificationCenter.default.post(name: Recordings.changed, object: nil)
        guard let window = window(folder), let record = recordings.read(folder) else { return }
        window.show(record, transcript: recordings.transcript(folder))
    }
}
