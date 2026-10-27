import AppKit
import SkilliCore
import SwiftUI

/// Settings → Recorder (docs/meeting-recorder-views.md, phase 2), in the
/// order of the Settings plan's rules: how to reach it first (its keys,
/// `rec` and `recs` in the launcher, Record ⌘R on the meeting card); the
/// sources and the language; where recordings are kept and for how long;
/// the recordings themselves last, by month.
struct RecorderPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane.
    let open: (SettingsPane) -> Void
    /// The languages this Mac transcribes, read as the pane opens.
    @State private var languages: [(id: String, name: String)] = []
    @State private var moveRefused: String?
    /// Better transcription's download, made as the pane shows.
    @State private var better: BetterTranscription?
    @State private var removeFailed: String?

    private enum Keep: Hashable {
        case never, week, month, quarter, year, custom
    }

    var body: some View {
        Form {
            Section {
                ForEach(shortcutRows, id: \.id) { row in
                    ShortcutRow(store: context.shortcuts, id: row.id, title: row.title, chords: row.chords)
                }
                LabeledContent {
                    KeycapLabel(RecordRequest.word)
                        .padding(.trailing, 8)
                } label: {
                    LabelDetail("From the launcher", "Type “\(RecordRequest.word)”, or “\(RecordRequest.word) Weekly sync” to name it, then ↩.")
                }
                if let prefix = LauncherPrefix.shown(for: .searchRecordings)?.trimmingCharacters(in: .whitespaces) {
                    LabeledContent {
                        KeycapLabel(prefix)
                            .padding(.trailing, 8)
                    } label: {
                        LabelDetail("Search Recordings", "Type “\(prefix)” and a space, then a title, a name, a date or what was said.")
                    }
                }
                Toggle(isOn: $preferences.recorderMeetingCard) {
                    LabelDetail("Record ⌘R on the meeting card", "As a meeting starts, its card offers to record it: your key, never on its own.")
                }
                .settingAnchor("recorderMeetingCard")
            } header: {
                PaneHeader(pane: .recorder)
            } footer: {
                Text("⌘R records the meeting where it shows: its card, its row in the launcher, its menu in the menu bar once you are in the call.")
            }

            Section {
                Toggle("Microphone", isOn: $preferences.recorderMicrophone)
                    .settingAnchor("recorderMicrophone")
                Toggle("The Mac's sound", isOn: $preferences.recorderMacSound)
                    .settingAnchor("recorderMacSound")
                Toggle("Webcam", isOn: $preferences.recorderWebcam)
                    .settingAnchor("recorderWebcam")
                Toggle("Screen", isOn: $preferences.recorderScreen)
                    .settingAnchor("recorderScreen")
                Picker("Language", selection: $preferences.recorderLanguage) {
                    Text("As Ask").tag("")
                    if !preferences.recorderLanguage.isEmpty, !languages.contains(where: { $0.id == preferences.recorderLanguage }) {
                        Text(MeetingTranscriber.name(of: preferences.recorderLanguage)).tag(preferences.recorderLanguage)
                    }
                    ForEach(languages, id: \.id) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                .settingAnchor("recorderLanguage")
            } header: {
                Text("Sources")
            } footer: {
                Text("On when the meeting says nothing else. In person, only the microphone; a call, both sides. The screen is the meeting's window, never in person.")
            }

            if let better {
                BetterTranscriptionSection(better: better, preferences: preferences, removeFailed: removeFailed,
                                           remove: { removeBetterTranscription(better) })
            }

            afterTranscript

            if let line = PrivacyMap.line(for: SettingsPane.recorder.rawValue, .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            Section {
                LabeledContent("Keep recordings in") {
                    HStack {
                        Text(FileManager.default.displayName(atPath: preferences.recordingsFolder.path))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Change…") { chooseFolder() }
                            .disabled(library?.moving != nil)
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([preferences.recordingsFolder]) }
                    }
                }
                .settingAnchor("recorderFolderPath")
                if let moving = library?.moving {
                    Text("Moving \(moving.done) of \(moving.of) recordings…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ForEach(([moveRefused].compactMap { $0 } + (library?.moveFailures ?? [])), id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Picker("Delete after", selection: keep) {
                    Text("Never").tag(Keep.never)
                    Text("1 week").tag(Keep.week)
                    Text("1 month").tag(Keep.month)
                    Text("3 months").tag(Keep.quarter)
                    Text("1 year").tag(Keep.year)
                    Text("Custom").tag(Keep.custom)
                }
                .settingAnchor("recorderRetention")
                if case .days(let days) = preferences.recorderRetention {
                    Stepper(value: customDays, in: 1...3650) {
                        Text(days == 1 ? "1 day" : "\(days) days")
                            .monospacedDigit()
                    }
                }
                // Nothing goes as the choice changes: the next hourly pass
                // moves them to the Trash, and this says it first.
                if let line = preferences.recorderRetention.removalLine(older: library?.expiredCount(preferences.recorderRetention) ?? 0) {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text(preferences.recorderRetention == .never
                     ? "Recordings stay until you delete them."
                     : "Expired recordings go to the Trash each hour, never deleted for good.")
            }

            // The long list last, by month.
            ForEach(months, id: \.title) { month in
                Section {
                    ForEach(month.recordings, id: \.folder) { recording in
                        RecordingRow(recording: recording,
                                     open: { context.openRecording(recording.folder) },
                                     reveal: { revealRecording(recording.folder) },
                                     delete: { context.deleteRecording(recording) })
                    }
                } header: {
                    Text(month.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if library?.isLoaded == true, months.isEmpty {
                Section {
                    Text("No recording yet: ⌘R on a meeting's card records it.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Recordings")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            library?.reload()
            languages = await MeetingTranscriber.languages()
        }
        .onAppear {
            better = context.betterTranscription()
            better?.refresh()
            better?.isShown = true
        }
        .onDisappear { better?.isShown = false }
    }

    /// Remove: to the Trash, the undo card offers it back for 10 s.
    /// After each transcript (phase 5): None, the default, or one skillie
    /// for recordings that gets every recording from now on, said under it
    /// and in the undo card (⌘Z puts back what was there).
    private var afterTranscript: some View {
        // Never one that asks first: after a transcript nobody is there to answer.
        let skillies = context.skillies().filter(RecordingFollowUps.runsOnItsOwn)
        let marked = preferences.recorderAfterTranscript
        let title = skillies.first { RecordingFollowUps.isMarked($0, marked) }?.title
        return Section {
            Picker("After each transcript", selection: Binding(get: { marked }, set: { mark($0, among: skillies) })) {
                Text("None").tag("")
                if !marked.isEmpty, title == nil {
                    Text("A skillie no longer there").tag(marked)
                }
                // The one marked under the path it was saved with.
                ForEach(skillies, id: \.path) { skillie in
                    Text(skillie.title).tag(RecordingFollowUps.isMarked(skillie, marked) ? marked : skillie.path)
                }
            }
            .disabled(skillies.isEmpty && marked.isEmpty)
            .settingAnchor("recorderAfterTranscript")
        } footer: {
            if let title {
                Text("“\(title)” gets every recording from now on: its folder, with the sound, the pictures and the words. What it does with them is its own script's.")
            } else if skillies.isEmpty {
                Text("No skillie for recordings that runs without asking: one says @skilli.forRecordings true in its header, and not needsConfirmation. ⌘K in a recording's window runs one on it.")
            } else {
                Text("A skillie for recordings can run on each recording once its transcript is made. ⌘K in a recording's window runs one on it.")
            }
        }
    }

    private func mark(_ path: String, among skillies: [ScriptCommand]) {
        let previous = preferences.recorderAfterTranscript
        guard path != previous else { return }
        preferences.recorderAfterTranscript = path
        if let skillie = skillies.first(where: { $0.path == path }) {
            context.deletes.skillieMarked(skillie.title, previous: previous, in: preferences)
        }
    }

    private func removeBetterTranscription(_ better: BetterTranscription) {
        do {
            removeFailed = nil
            try context.deletes.betterTranscription(better)
        } catch {
            removeFailed = "Not moved to the Trash: \(error.localizedDescription)"
        }
    }

    private var library: RecordingLibrary? { context.recordings }

    /// The recordings by month, newest first ("October 2026").
    private var months: [(title: String, recordings: [RecordingSummary])] {
        let summaries = library?.summaries.filter { $0.state != .recording && $0.state != .paused } ?? []
        var months: [(title: String, recordings: [RecordingSummary])] = []
        for summary in summaries {
            let title = summary.started.formatted(.dateTime.month(.wide).year())
            if months.last?.title == title { months[months.count - 1].recordings.append(summary) } else { months.append((title, [summary])) }
        }
        return months
    }

    private var shortcutRows: [(id: String, title: String, chords: [Chord]?)] {
        [(SkilliAction.launcherCommand(.recordMeeting), "Record Meeting"), (SkilliAction.launcherCommand(.searchRecordings), "Search Recordings")]
            .compactMap { action, title in
                context.shortcuts.config.shortcuts.first { $0.action == action }.map { ($0.id, title, $0.chords) }
            }
    }

    private var keep: Binding<Keep> {
        Binding(
            get: {
                switch preferences.recorderRetention {
                case .never: .never
                case .week: .week
                case .month: .month
                case .quarter: .quarter
                case .year: .year
                case .days: .custom
                }
            },
            set: { choice in
                preferences.recorderRetention = switch choice {
                case .never: .never
                case .week: .week
                case .month: .month
                case .quarter: .quarter
                case .year: .year
                case .custom: preferences.recorderRetention.asCustom
                }
            }
        )
    }

    private var customDays: Binding<Int> {
        Binding(
            get: { preferences.recorderRetention.days ?? 365 },
            set: { preferences.recorderRetention = .days($0) }
        )
    }

    private func revealRecording(_ folder: String) {
        guard let library else { return }
        NSWorkspace.shared.activateFileViewerSelecting([library.folder(folder)])
    }

    /// Where recordings go from now on: the ones made move there.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Recordings are kept in this folder: the ones made move there, one by one."
        panel.directoryURL = preferences.recordingsFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        moveRefused = nil
        Task {
            let said = await context.moveRecordings(url)
            // A move that failed says so in its own lines.
            moveRefused = context.recordings?.moveFailures.isEmpty == false ? nil : said
        }
    }
}

/// One recording in the list: its title, when and how long; a click opens
/// its window, its menu shows it in Finder or deletes it (⌘Z brings it
/// back).
private struct RecordingRow: View {
    let recording: RecordingSummary
    let open: () -> Void
    let reveal: () -> Void
    let delete: () -> Void

    var body: some View {
        LabeledContent {
            Menu {
                Button("Open", action: open)
                Button("Show in Finder", action: reveal)
                Divider()
                Button("Delete", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        } label: {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.title)
                        .foregroundStyle(.primary)
                    Text(RecordingSearch.detail(recording, length: MeetingTranscriber.length(recording.seconds)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("Open", action: open)
            Button("Show in Finder", action: reveal)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
    }
}

/// Better transcription (docs/meeting-recorder-views.md, phase 4): what it
/// is and where it comes from, its download as it goes, then the engine.
/// Nothing is downloaded but from its button.
private struct BetterTranscriptionSection: View {
    let better: BetterTranscription
    @Bindable var preferences: Preferences
    let removeFailed: String?
    let remove: () -> Void

    var body: some View {
        Section {
            LabeledContent {
                buttons
            } label: {
                LabelDetail("Better transcription", detail)
            }
            .settingAnchor("section.betterTranscription")
            if case .downloading(let received, let total, let line) = better.state {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(received), total: Double(max(1, total)))
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if let warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if better.state == .downloaded {
                Picker("Engine", selection: engine) {
                    Text(TranscriptEngine.whisper.title).tag(TranscriptEngine.whisper.rawValue)
                    Text(TranscriptEngine.macOS.title).tag(TranscriptEngine.macOS.rawValue)
                }
                .settingAnchor("recorderEngine")
            }
        } footer: {
            Text(better.state == .downloaded
                 ? "Transcripts are made with the engine picked; a language it lacks goes to the other."
                 : "Until it is downloaded, macOS's own engine makes the transcripts.")
        }
    }

    private var detail: String {
        switch better.state {
        case .downloaded:
            "Downloaded · \(ModelDownload.size(better.total)) · whisper large-v3-turbo, on this Mac. For the recorder only."
        case .checking:
            "Checking the file…"
        default:
            "whisper large-v3-turbo, on this Mac: 40 % fewer errors than macOS's engine, two names in three right. Downloaded from huggingface.co, nothing sent. For the recorder only."
        }
    }

    /// What went wrong, or why it cannot start.
    private var warning: String? {
        switch better.state {
        // Not enough room to go on: said instead of the stop's reason.
        case .stopped(let why, _): better.roomLine ?? why
        case .wrongFile: "The file downloaded is not the one expected (another checksum): nothing was kept."
        case .notDownloaded: better.roomLine
        default: removeFailed
        }
    }

    @ViewBuilder private var buttons: some View {
        switch better.state {
        case .notDownloaded, .wrongFile:
            Button("Download (\(ModelDownload.size(better.total)))") { better.download() }
                .disabled(better.roomLine != nil)
        case .stopped(_, let resumable):
            Button(resumable ? "Resume" : "Download") { better.download() }
                .disabled(better.roomLine != nil)
        case .downloading:
            Button("Cancel") { better.cancel() }
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .downloaded:
            Button("Remove") { remove() }
        }
    }

    private var engine: Binding<String> {
        Binding(
            get: { TranscriptEngine.standard(preferred: TranscriptEngine(stored: preferences.recorderEngine), whisperReady: true).rawValue },
            set: { preferences.recorderEngine = $0 }
        )
    }
}
