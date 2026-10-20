import AppKit
import SkilliCore
import SwiftUI

/// Settings → Ask → Advanced → Skills: the folder of SKILL.md skills Ask's
/// agent reads, with Show in Finder and what it holds, and Claude Code's
/// own skills too when asked.
struct AskSkillsRows: View {
    @Bindable var preferences: Preferences
    /// The skills found now, skil.li's first.
    let skills: () -> [AgentSkill]
    @State private var found: [AgentSkill] = []

    static let folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("skil.li/skills", isDirectory: true)

    var body: some View {
        Group {
            LabeledContent {
                Button("Show in Finder") {
                    try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([Self.folder])
                }
            } label: {
                LabelDetail("Skills", detail)
            }
            .settingAnchor("skills")
            Toggle(isOn: $preferences.askUsesClaudeCodeSkills) {
                LabelDetail("Use Claude Code's skills too", "Those in ~/.claude/skills; one of yours with the same name comes first.")
            }
            .settingAnchor("askUsesClaudeCodeSkills")
        }
        .onAppear { found = skills() }
        .onChange(of: preferences.askUsesClaudeCodeSkills) { found = skills() }
        .onReceive(NotificationCenter.default.publisher(for: SettingTools.changed)) { _ in found = skills() }
    }

    /// What a skill is, then the ones found.
    private var detail: String {
        let what = "Folders with a SKILL.md in ~/Library/Application Support/skil.li/skills teach Ask's agent a job your way."
        guard !found.isEmpty else { return what + " None yet: ask an agent to write one." }
        let names = found.prefix(5).map(\.name)
        return what + " " + names.joined(separator: ", ") + (found.count > names.count ? " and \(found.count - names.count) more." : ".")
    }
}

/// Settings → Ask → On a Schedule: what Ask runs by itself, and when.
/// Each row says when, what, and its last run (a click shows that answer
/// again in the card); its switch pauses it, − deletes it. A new one is
/// said as in Ask. Last in the pane: the long list.
struct ScheduledAsksSection: View {
    @Bindable var scheduler: AskScheduler
    /// − deletes one at once; ⌘Z in the card puts it back.
    let deletes: UndoableDeletes
    /// Shows a last answer in the card.
    let showAnswer: (ScheduledAsk) -> Void
    @State private var said = ""
    @State private var problem: String?

    var body: some View {
        Section {
            ForEach(scheduler.asks) { ask in
                ScheduledAskRow(ask: ask, running: scheduler.running.contains(ask.id), next: scheduler.next(ask), scheduler: scheduler,
                                deletes: deletes, showAnswer: showAnswer)
            }
            HStack {
                TextField("New", text: $said, prompt: Text("every Monday at 9:00 sum up my pull requests"))
                    .labelsHidden()
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(said.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let problem {
                Text(problem).foregroundStyle(.red)
            }
        } header: {
            Text("On a Schedule")
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingAnchor("scheduledAsks")
        } footer: {
            Text("Or say it in Ask: “tous les lundis à 9h résume mes PR”. At its time it does what Ask would, and its answer waits for you in the card. A time missed while the Mac slept runs once when it wakes.")
        }
    }

    private func add() {
        let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let (schedule, ask) = AskSchedule.read(text) ?? AskSchedule.read(text, anywhere: true) else {
            problem = "Say when first: “every weekday at 8:30 tell me my day”, “le 1er de chaque mois à 9h …”."
            return
        }
        scheduler.add(ask, schedule: schedule)
        said = ""
        problem = nil
    }
}

private struct ScheduledAskRow: View {
    let ask: ScheduledAsk
    let running: Bool
    let next: Date?
    let scheduler: AskScheduler
    let deletes: UndoableDeletes
    let showAnswer: (ScheduledAsk) -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Toggle("On", isOn: Binding(get: { ask.isOn }, set: { scheduler.setOn(ask.id, $0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(ask.isOn ? "Pause it" : "Turn it on again")
                Button {
                    deletes.scheduledAsk(ask.id, in: scheduler)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Delete it")
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(ask.ask.prefix(1).uppercased() + ask.ask.dropFirst())
                    .foregroundStyle(ask.isOn ? .primary : .secondary)
                    .lineLimit(2)
                Text(ask.schedule.spoken)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                status
            }
            .padding(.vertical, 2)
        }
    }

    /// The last run's line (a click shows its answer), else the next run.
    @ViewBuilder private var status: some View {
        if running {
            Text("Running…").font(.caption).foregroundStyle(.secondary)
        } else if let last = ask.lastRun, let answer = ask.lastAnswer, !answer.isEmpty {
            Button {
                showAnswer(ask)
            } label: {
                Text(ScheduledAsks.moment(last) + " · " + ScheduledAsks.line(of: answer))
                    .font(.caption)
                    .foregroundStyle(ask.lastFailed ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)
            .help("Show the whole answer in the card")
        } else if !ask.isOn {
            Text("Paused").font(.caption).foregroundStyle(.secondary)
        } else if let next {
            Text("First: " + ScheduledAsks.moment(next)).font(.caption).foregroundStyle(.secondary)
        }
    }
}
