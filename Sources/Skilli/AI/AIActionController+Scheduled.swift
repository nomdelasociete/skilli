import AppKit
import SkilliCore

/// Asks on a schedule (`AskScheduler`), run out of sight at their time.
extension AIActionController {
    /// What a scheduled run may use without the user at the keyboard: no
    /// selection, no window or menus of whatever app is in front, and none
    /// of skil.li's own settings (it never schedules more).
    static let scheduledGroups = Set(ToolGroup.allCases).subtracting([.selection, .screen, .menus, .settings])

    /// Runs a scheduled ask now, out of sight, as Ask would: Jev or
    /// Decisions picks the route from the request alone (no selection, no
    /// app in front); a Mac command or an app is done at once, an answer is
    /// written by the writer, the rest done by the agent
    /// (`scheduledGroups`, the connected servers signed in to). Its answer
    /// then waits for the user in the card (`presentScheduled`); its
    /// approvals take the card as an outside agent's do. Returns the answer,
    /// or why it failed, for the list, without waiting for the user.
    func runScheduled(_ scheduled: ScheduledAsk) async -> (answer: String, failed: Bool) {
        let instruction = scheduled.ask
        let started = ContinuousClock.now
        let when = scheduled.schedule.spoken
        guard let command = library.command(PromptLibrary.askID) else { return ("Ask is missing from Commands.", true) }
        library.reload()
        let profile = library.profile
        let message = Self.message(for: command, values: Self.values(selection: "", clipboard: "", app: "", window: "", profile: profile),
                                   answers: ["instruction": instruction], selection: nil, profile: profile)
        let canAct = ai.subscription.binary != nil && tools?.socketPath != nil
        let writer = ai.writer(for: command.model)

        var route: AskRoute
        var decision: AskRouter.Decision?
        if let routeOverride {
            route = routeOverride
        } else if let decisionOverride {
            decision = decisionOverride
            route = decisionOverride.route
        } else {
            let entries = installedApps?() ?? []
            let apps = await Task.detached(priority: .utility) { AppCandidates.apps(entries) }.value
            let services = canAct ? (tools?.settings.servers ?? []).map { server in
                (name: server.name, tools: tools?.settings.serverTools[server.name]?.map(\.name) ?? [])
            } : []
            decision = await AskRouter.decide(instruction, hasSelection: false, app: "", menu: [], apps: apps,
                                              projects: recentProjects?() ?? [],
                                              scripts: (scriptCommands?() ?? []).filter { $0.arguments.allSatisfy(\.optional) },
                                              services: services, keys: decisionKeysOverride ?? AskRouter.keys(ai))
            route = decision?.route ?? (canAct ? .act : .answer)
        }
        Log.trace("Scheduled “\(instruction)” (\(when)): \(route.rawValue)")

        switch route {
        case .command:
            if let action = decision?.command?.command, systemCommands != nil, (decision?.command?.probability ?? 0) >= 0.5 {
                // Seen done (dark mode, the volume): not said; a reading
                // (speed, system info) shows its own card.
                runMac(action)
                return ("Ran \(action.title).", false)
            }
        case .open:
            if let best = decision?.apps.first, best.probability >= 0.6 {
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: best.app.url, configuration: NSWorkspace.OpenConfiguration())
                    return ("Opened \(best.app.name).", false)
                } catch {
                    let said = "\(best.app.name) did not open: \(error.localizedDescription)"
                    show(scheduled, answer: said, failed: true, status: when, by: nil)
                    return (said, true)
                }
            }
        default:
            break
        }
        // Answers in words go to the writer; everything else to the agent.
        if route == .answer || !canAct {
            guard let writer else {
                let said = ai.setupMessage(for: command.model)
                show(scheduled, answer: said, failed: true, status: when, by: nil)
                return (said, true)
            }
            return await writeScheduled(scheduled, message: message, writer: writer, started: started)
        }
        return await actScheduled(scheduled, message: message, started: started)
    }

    private func writeScheduled(_ scheduled: ScheduledAsk, message: String, writer: AIStore.Writer,
                                started: ContinuousClock.Instant) async -> (answer: String, failed: Bool) {
        let when = scheduled.schedule.spoken
        var answer = ""
        do {
            for try await chunk in writer.engine.stream(AIRequest(message: message, model: writer.choice)) {
                answer += chunk
            }
        } catch {
            let said = error.localizedDescription
            show(scheduled, answer: said, failed: true, status: "\(when) · \(writer.label)", by: nil)
            return (said, true)
        }
        answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else {
            let said = "\(writer.choice.provider.title) answered nothing."
            show(scheduled, answer: said, failed: true, status: when, by: nil)
            return (said, true)
        }
        let status = "\(when) · \(writer.label) · \(Self.duration(.now - started))"
        show(scheduled, answer: answer, failed: false, status: status, by: .writer(writer))
        return (answer, false)
    }

    private func actScheduled(_ scheduled: ScheduledAsk, message: String, started: ContinuousClock.Instant) async -> (answer: String, failed: Bool) {
        let when = scheduled.schedule.spoken
        guard let tools, let socketPath = tools.socketPath, let binary = ai.subscription.binary else {
            return ("Claude Code is not set up: Settings → SI Accounts.", true)
        }
        // The servers it can reach now: one not signed in to is left out.
        var servers = tools.settings.servers
        var headers: [String: [String: String]] = [:]
        for server in servers where server.auth != nil {
            do {
                headers[server.name] = try await tools.settings.auth.headers(for: server)
            } catch {
                servers.removeAll { $0.name == server.name }
            }
        }
        let groups = Self.scheduledGroups
        let context = AgentContext(title: "\(when): \(scheduled.ask)", groups: groups, read: nil, targetPID: nil, background: true)
        let model = ai.claudeModel
        tools.register(context)
        defer { tools.unregister(context) }
        let run: AgentRun
        do {
            run = try AgentRun(binary: binary, model: model, runID: context.id, socketPath: socketPath, servers: servers,
                               skilliTools: tools.allToolNames, headers: headers, blockedTools: tools.settings.blockedTools(on: servers),
                               skills: agentSkills?() ?? [])
        } catch {
            let said = "Could not start Claude Code: \(error.localizedDescription)"
            show(scheduled, answer: said, failed: true, status: when, by: nil)
            return (said, true)
        }
        defer { run.terminate() }
        let request = "(The user scheduled this \(when.lowercased()); it is that time now. Do it once, now, and reply with the result for them to read. Schedule nothing.)\n\n" + message
        var steps: [String] = []
        var answer = ""
        var failed = false
        do {
            // Long enough for the user to come back to an approval.
            for try await event in run.start(request, timeout: .seconds(900)) {
                switch event {
                case .toolUse(_, let name, _): steps.append(Self.stepTitle(name))
                case .finished(let text, let isError, _):
                    answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    failed = isError
                default: break
                }
            }
        } catch {
            answer = error.localizedDescription
            failed = true
        }
        if answer.isEmpty, !failed {
            answer = "Claude Code answered nothing."
            failed = true
        }
        let status = "\(when) · Claude Code · \(model.title) · \(Self.duration(.now - started))"
        show(scheduled, answer: answer, failed: failed, status: failed ? when : status,
                               by: failed ? nil : .agent(groups: groups, servers: servers), steps: steps)
        return (answer, failed)
    }

    /// Its answer waits for the user on its own: the run is done, the row
    /// says so meanwhile.
    private func show(_ scheduled: ScheduledAsk, answer: String, failed: Bool, status: String, by answerer: ScheduledAnswerer?,
                      steps: [String] = []) {
        Task { await presentScheduled(scheduled, answer: answer, failed: failed, status: status, by: answerer, steps: steps) }
    }

    /// "12.3 s".
    static func duration(_ duration: Duration) -> String {
        String(format: "%.1f s", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }

    // MARK: - Whether the user is there

    /// The screen locked or asleep, or the session not the one in front.
    static func userIsAway() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        if (session?["CGSSessionScreenIsLocked"] as? Bool) == true { return true }
        if (session?[kCGSessionOnConsoleKey as String] as? Bool) == false { return true }
        return CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    static func secondsSinceLastKey() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }

    /// Returns when macOS says the user may be back: the screen unlocked,
    /// the displays or the Mac awake, the session in front again.
    static func untilTheUserIsBack() async {
        final class Waiter: @unchecked Sendable {
            var observers: [(NotificationCenter, NSObjectProtocol)] = []
            var continuation: CheckedContinuation<Void, Never>?
            func resume() {
                for (center, observer) in observers { center.removeObserver(observer) }
                observers = []
                continuation?.resume()
                continuation = nil
            }
        }
        let waiter = Waiter()
        await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            let workspace = NSWorkspace.shared.notificationCenter
            let distributed = DistributedNotificationCenter.default()
            let back: @Sendable (Notification) -> Void = { _ in MainActor.assumeIsolated { waiter.resume() } }
            for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
                waiter.observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main, using: back)))
            }
            waiter.observers.append((distributed, distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil,
                                                                          queue: .main, using: back)))
            // Back already, between the look and the watch.
            if !userIsAway() { waiter.resume() }
        }
        // The screen comes on before it is unlocked: settle first.
        try? await Task.sleep(for: .seconds(1))
    }
}
