import AppKit
import SkilliCore

// ⌘K: what can be done with each kind of row. Few actions, the likely ones
// first, in three groups: doing, copying, removing. ↩, ⌘↩ and ⇧↩ do here
// what they do in the list; ⌘C copies the row's main value (its title when
// it has none), ⇧⌘C its second; ⌘⌫ removes it (in a mode: outside, ⌘⌫ edits
// the search field). The first action is the row's ↩, which the footer
// names (`mainAction`).

extension LauncherController {
    /// The row's actions, then its alias's and Pin (outside the modes),
    /// before the copies.
    func actions(for item: LauncherItem) -> [LauncherAction] {
        if case .catalog(let entry) = item { return catalogActions(entry) }
        var list = itemActions(for: item)
        // Its skil.li link, last of the copies.
        if let link = skilliLink(for: item) {
            list.insert(copyLinkAction(link, title: Self.copyLinkTitle(item)), at: list.firstIndex { $0.group == .remove } ?? list.count)
        }
        guard takesAlias(item) else { return list }
        let at = list.firstIndex { $0.group != .act } ?? list.count
        list.insert(contentsOf: aliasActions(for: item) + (mode == nil && takesPin(item) ? [pinAction(for: item)] : []), at: at)
        return list
    }

    /// The `skilli://` link that runs what the row does, for the rows the
    /// Catalog lists (commands, Mac commands and window places, the user's
    /// commands, snippets, skillies, quicklinks with what is typed for
    /// them, layouts): built from the row, nothing read.
    func skilliLink(for item: LauncherItem) -> SkilliLink? {
        switch item {
        case .command, .siCommand, .snippet: return .run(item.learningID)
        case .system(let action, _):
            switch action {
            case .system, .window: return .run(item.learningID)
            // The command, not a variant: links run Catalog entries.
            case .appLink(_, nil): return .run(item.learningID)
            // Asked first from a link: a shortcut can do anything.
            case .shortcut(_, false): return .run(item.learningID)
            case .sound, .project, .script, .settings, .bluetooth, .volume, .appLink, .shortcut: return nil
            }
        case .script(let command, _): return .skillie(skilliePath(command.path), arguments: [])
        case .quicklink(let link, let typed, _):
            return .quicklink(link.linkName(among: quicklinks?() ?? [link]), query: typed.isEmpty ? nil : typed)
        case .layout(let layout): return .layout(layout.id)
        default: return nil
        }
    }

    /// Copies the link, nothing said (the launcher closes). Never ⌘C's.
    func copyLinkAction(_ link: SkilliLink, title: String = "Copy Link") -> LauncherAction {
        var action = LauncherAction(title: title, symbol: "link", group: .copy) { [weak self] in
            self?.hide()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
        }
        action.isLink = true
        return action
    }

    /// ⌘C on a row with nothing of its own to copy: its words (what was
    /// asked, a skillie's line, an argument typed, else its title), nothing
    /// said; the launcher closes as for any copy.
    func copyTitleAction(_ item: LauncherItem) -> LauncherAction {
        let text: String = switch item {
        case .ask(let asked): asked
        case .script(let command, let inline): inline ?? command.title
        case .scriptArgument(let command, let index, let typed):
            command.arguments[index].kind == .password || typed.isEmpty ? command.title : typed
        default: item.title
        }
        return LauncherAction(title: "Copy Title", symbol: "doc.on.doc", key: .copy, group: .copy) { [weak self] in
            self?.hide()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    /// The row's ↩: its first action in ⌘K and the footer's first hint.
    /// Read on every key and selection (the footer): a switch, nothing
    /// built or read.
    func mainAction(for item: LauncherItem) -> (title: String, symbol: String)? {
        switch item {
        case .app, .file, .project: ("Open", "arrow.up.forward.app")
        case .layout: ("Apply Layout", "rectangle.3.group")
        case .command(let command): (Self.returnTitle(command.id), "return")
        case .system(.settings, _): ("Open", "return")
        case .scriptArgument(let command, let index, _): (index == command.arguments.count - 1 ? "Run" : "Next", "return")
        case .scriptChoice:
            (scriptInput.map { $0.values.count == $0.command.arguments.count - 1 } ?? true ? "Run" : "Next", "return")
        case .saveLayout, .openWindow, .startTimer, .keepAwake, .runningTimer, .createEvent, .addReminder,
             .brewUpgradeAll, .setup, .ask, .siCommand, .system:
            (Self.openTitle(item), "return")
        case .keptAwake: (AwakeStatus.turnOff, "power")
        case .recordNamed: ("Open", "record.circle")
        case .recording: ("Stop and Transcribe", "stop.circle")
        case .recorded: ("Open", "waveform")
        case .process: ("Quit", "xmark.circle")
        case .clip, .snippet, .emoji: ("Paste", "doc.on.clipboard")
        case .gif(let gif):
            GIFPaste.style(for: gif, frontApp: gifFrontApp, editors: gifEditors) == .markdown ? ("Paste Markdown", "text.badge.plus") : ("Paste", "doc.on.clipboard")
        // The day's rates not here yet: ↩ does nothing, the footer offers nothing.
        case .calculation(let result): result.isWaiting ? nil : ("Paste Result", "doc.on.clipboard")
        case .browserTab: ("Go to Tab", "macwindow")
        case .contact: ("Show Contact", "person.text.rectangle")
        case .event(let event): event.meeting != nil ? ("Join", "video") : ("Open in Calendar", "calendar")
        case .reminder(let reminder): (reminder.isCompleted ? "Not Done" : "Done", "checkmark.circle")
        case .pullRequest, .githubNotification, .quicklink: ("Open", "arrow.up.forward")
        case .script: ("Run", "play")
        case .visit: ("Open", "safari")
        case .brew(let package):
            package.installed == nil ? ("Install", "arrow.down.circle") : package.update != nil ? ("Upgrade", "arrow.down.circle") : ("Open Page", "safari")
        case .menuItem: ("Choose", "filemenu.and.selection")
        case .catalog(let entry): (catalogReturnTitle(entry), "return")
        case .catalogHeader: nil
        }
    }

    /// What ↩ does on a built-in command: a mode or a window opens, the
    /// rest runs (the Catalog's "?" says the same).
    static func returnTitle(_ id: LauncherCommand.ID) -> String {
        mode(for: id) != nil || [.openSettings, .newWindowLayout, .newEmptyWindowLayout, .newSnippet, .newQuicklink, .newCommand, .recordMeeting, .importRecording].contains(id)
            ? "Open" : "Run"
    }

    /// "Copy Link"; on a quicklink, whose Copy Link is its web address,
    /// "Copy skil.li Link".
    private static func copyLinkTitle(_ item: LauncherItem) -> String {
        if case .quicklink = item { return "Copy skil.li Link" }
        return "Copy Link"
    }

    /// Set Alias…, or Change Alias “e”… and Remove Alias.
    func aliasActions(for item: LauncherItem) -> [LauncherAction] {
        let current = aliases().first { $0.id == item.learningID }?.alias
        var alias = [LauncherAction(title: current.map { "Change Alias “\($0)”…" } ?? "Set Alias…", symbol: "character.cursor.ibeam",
                                    keepsOpen: true) { [weak self] in self?.askAlias(for: item) }]
        if current != nil {
            alias.append(LauncherAction(title: "Remove Alias", symbol: "xmark.circle") { [weak self] in
                self?.onSetAlias?(item.learningID, item.title, "")
                self?.refreshResults()
            })
        }
        return alias
    }

    /// What the linked apps installed do with a file a row holds
    /// (Annotate in CleanShot, Pin in CleanShot, Add to CleanShot Quick
    /// Access): only what its type takes, read from its name, nothing
    /// from the disk.
    private func openFileActions(_ file: URL) -> [LauncherAction] {
        LinkedApps.fileActions(for: file).map { action, command in
            LauncherAction(title: action.title, symbol: action.symbol) { [weak self] in
                self?.hide()
                self?.onOpenFile?(file, command, action.title)
            }
        }
    }

    /// The file a copy is: an image's in the history's own folder, or the
    /// one file copied in Finder.
    private func clipFile(_ clip: ClipboardStore.Item) -> URL? {
        switch clip.kind {
        case .image:
            return clipboardImageURL?(clip)
        case .files:
            let paths = clip.text.split(separator: "\n")
            return paths.count == 1 ? URL(fileURLWithPath: String(paths[0])) : nil
        case .text:
            return nil
        }
    }

    private func itemActions(for item: LauncherItem) -> [LauncherAction] {
        guard let main = mainAction(for: item) else { return [] }
        /// What the list does with ↩, ⌘↩ or ⇧↩ on the row.
        func key(_ title: String, _ symbol: String, _ key: LauncherAction.Key, group: LauncherAction.Group = .act) -> LauncherAction {
            let flags: NSEvent.ModifierFlags = switch key {
            case .openSecond: .command
            case .openThird: .shift
            default: []
            }
            return LauncherAction(title: title, symbol: symbol, key: key, group: group) { [weak self] in self?.launchSelected(flags: flags) }
        }
        /// The launcher closes, then it runs.
        func act(_ title: String, _ symbol: String, _ run: @escaping @MainActor () -> Void) -> LauncherAction {
            LauncherAction(title: title, symbol: symbol) { [weak self] in
                self?.hide()
                run()
            }
        }
        func open(_ title: String, _ symbol: String, _ url: URL?) -> LauncherAction? {
            url.map { url in act(title, symbol) { [weak self] in self?.openURL(url) } }
        }
        func reveal(_ url: URL) -> LauncherAction {
            act("Show in Finder", "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        func copy(_ title: String, _ text: String, _ key: LauncherAction.Key? = nil) -> LauncherAction {
            LauncherAction(title: title, symbol: "doc.on.doc", key: key, group: .copy) { [weak self] in
                self?.hide()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
        let removeKey: LauncherAction.Key? = mode == nil ? nil : .delete
        func remove(_ title: String, _ run: @escaping @MainActor () -> Void) -> LauncherAction {
            LauncherAction(title: title, symbol: "trash", key: removeKey, group: .remove, run: run)
        }
        /// ↩, as the footer names it.
        let first = key(main.title, main.symbol, .open)

        switch item {
        case .app(let entry):
            var list = [first, reveal(entry.url)]
            if let running = index.runningApp(entry), running.processIdentifier != getpid() {
                let pid = running.processIdentifier
                list.append(act("Quit", "xmark.circle") { [weak self] in self?.quitApp(entry, pid: pid, force: false) })
                list.append(act("Force Quit", "bolt.circle") { [weak self] in self?.quitApp(entry, pid: pid, force: true) })
            }
            // Its keys, recorded right away; said in the card.
            let open = SkilliAction.openApp(entry.url.path)
            let keys = shortcutKeys?()[open.id].map { $0.map { $0.keycaps.joined() }.joined(separator: " ") }
            list.append(act(keys.map { "Change Shortcut \($0)…" } ?? "Set Shortcut…", "keyboard") { [weak self] in
                self?.onSetShortcut?(open, entry.name)
            })
            list += [copy("Copy Name", entry.name, .copy), copy("Copy Path", entry.url.path, .copySecond)]
            // Not macOS's own apps, not skil.li.
            if !AppLeftovers.isProtected(entry.url.path, bundleID: Bundle(url: entry.url)?.bundleIdentifier) {
                list.append(LauncherAction(title: "Uninstall…", symbol: "trash", group: .remove) { [weak self] in
                    self?.hide()
                    self?.onUninstall?(entry.url)
                })
            }
            return list
        case .layout(let layout):
            return [first,
                    act("Edit Layout…", "slider.horizontal.3") { [weak self] in self?.onEditLayout?(layout) },
                    act("Update to the Windows Open…", "arrow.triangle.2.circlepath") { [weak self] in self?.onUpdateLayout?(layout) },
                    copy("Copy Name", layout.name, .copy),
                    remove("Delete Layout") { [weak self] in
                        self?.hide()
                        self?.onDeleteLayout?(layout)
                    }]
        // CleanShot's Capture Area, then what it does with the capture:
        // its variants, each run as its own key would.
        case .system(.appLink(let command, nil), _):
            return [first] + LinkedApps.variants(of: command).map { variant in
                act(variant.title, variant.symbol) { [weak self] in self?.onSystemCommand?(.appLink(command, variant: variant.id)) }
            }
        // A shortcut: on the text selected where the launcher opened (when
        // some was), and its editor in Shortcuts.
        case .system(.shortcut(let shortcut, false), _):
            var list = [first]
            if let selected = shownSelection {
                list.append(act("Run with the Selection", "text.line.first.and.arrowtriangle.forward") { [weak self] in self?.onRunShortcut?(shortcut, .text(selected)) })
            }
            list.append(act("Edit in Shortcuts", "square.and.pencil") { [weak self] in self?.onEditShortcut?(shortcut) })
            return list
        // A window open: every window where the user usually puts it.
        case .openWindow:
            return [first, act(SystemCommand.arrangeWindows.title, SystemCommand.arrangeWindows.symbol) { [weak self] in
                self?.onSystemCommand?(.system(.arrangeWindows))
            }]
        case .command, .saveLayout, .startTimer, .keepAwake, .runningTimer, .createEvent, .addReminder,
             .brewUpgradeAll, .setup, .ask, .siCommand, .system, .scriptArgument, .scriptChoice, .recordNamed:
            return [first]
        // A recording made: its folder, its words, gone to the Trash.
        case .recorded(let found):
            return [first,
                    LauncherAction(title: "Ask \(recordingProvider()) About This Meeting…", symbol: "questionmark.bubble", keepsOpen: true) { [weak self] in
                        self?.askAboutRecording(found.summary)
                    },
                    LauncherAction(title: "Rename Recording…", symbol: "pencil", keepsOpen: true) { [weak self] in
                        self?.renameRecording(found.summary)
                    },
                    key("Show in Finder", "folder", .openSecond),
                    LauncherAction(title: "Copy Transcript", symbol: "doc.on.doc", key: .copy, group: .copy) { [weak self] in
                        self?.hide()
                        self?.onCopyRecordingTranscript?(found.summary.folder)
                    },
                    remove("Delete Recording") { [weak self] in
                        self?.hide()
                        self?.onDeleteRecording?(found.summary)
                    }]
        // The recording on now: paused or resumed, its folder.
        case .recording(let live):
            return [first,
                    act(live.paused ? "Resume Recording" : "Pause Recording", live.paused ? "record.circle" : "pause.circle") { [weak self] in
                        self?.onRecordingControl?(live.paused ? .resume : .pause)
                    },
                    act("Show in Finder", "folder") { [weak self] in self?.onShowRecordingFolder?() }]
        // Kept awake: an hour more (timed), or an end in an hour (until
        // turned off).
        // The end read again as it runs: the row may be older than it.
        case .keptAwake(let until):
            return [first, act(until == nil ? "Turn Off in 1 h" : "Keep Awake 1 h Longer", "plus.circle") { [weak self] in
                guard let self else { return }
                let awake = self.awakeState()
                guard awake.awake else { return }
                self.onKeepAwake?(.awake(seconds: awake.until.map { AwakeStatus.secondsLonger(until: $0) } ?? AwakeStatus.longer))
            }]
        case .process(let group, let port):
            var list = [first, key("Force Quit", "bolt.circle", .openThird)]
            if let path = group.appPath { list.append(reveal(URL(fileURLWithPath: path))) }
            list.append(copy("Copy Name", group.name, .copy))
            if let port {
                list.append(copy("Copy Port", String(port), .copySecond))
            } else if let pid = group.entries.first?.pid {
                list.append(copy("Copy PID", String(pid), .copySecond))
            }
            return list
        case .clip(let clip):
            // An image (or one file copied in Finder): CleanShot's too.
            let inApps = clipFile(clip).map(openFileActions) ?? []
            return [first, key("Paste as Plain Text", "textformat", .openThird)] + inApps
                + [key("Copy", "doc.on.doc", .openSecond, group: .copy),
                   remove("Forget") { [weak self] in self?.forgetSelectedClip() }]
        case .snippet, .emoji:
            return [first, key("Copy", "doc.on.doc", .openSecond, group: .copy)]
        case .gif(let gif):
            let query = gifQuery
            func use(_ title: String, _ symbol: String, _ use: GIFUse, _ key: LauncherAction.Key? = nil,
                     group: LauncherAction.Group = .copy) -> LauncherAction {
                LauncherAction(title: title, symbol: symbol, key: key, group: group) { [weak self] in
                    self?.hide()
                    self?.onGIF?(gif, use, query)
                }
            }
            switch gif {
            case .klipy:
                return [first, use("Open in Browser", "safari", .open, group: .act),
                        key("Copy GIF", "doc.on.doc", .openSecond, group: .copy), use("Copy Link", "link", .copyLink, .copySecond),
                        use("Copy Markdown", "text.badge.plus", .copyMarkdown)]
            case .file(let url):
                return [first, reveal(url), key("Copy GIF", "doc.on.doc", .openSecond, group: .copy), copy("Copy Path", url.path, .copySecond)]
            }
        case .calculation(let result):
            // The day's rates are not here yet: nothing to paste or copy.
            if result.isWaiting { return [] }
            // ↩ pastes like a clip, a snippet or an emoji (D4); ⌘↩ and ⌘C copy.
            var list = [first, key("Copy Result", "doc.on.doc", .openSecond, group: .copy)]
            if result.currency != nil { list.append(copy("Copy with Currency", result.display, .copySecond)) }
            if let conversion = result.conversion { list.append(copy("Copy Rate", conversion.rate)) }
            return list
        case .browserTab(let tab):
            return [first, copy("Copy Title", tab.title, .copy)]
        case .file(let file):
            return [first, key("Show in Finder", "folder", .openSecond)] + openFileActions(file.url) + [
                LauncherAction(title: "Copy File", symbol: "doc.on.doc", key: .copy, group: .copy) { [weak self] in
                    self?.hide()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([file.url as NSURL])
                },
                copy("Copy Path", file.url.path, .copySecond),
                // At once; the undo card's ⌘Z moves it back for 10 s.
                remove("Move to Trash") { [weak self] in
                    self?.hide()
                    NSWorkspace.shared.recycle([file.url]) { moved, error in
                        MainActor.assumeIsolated {
                            if let trashed = moved[file.url] ?? moved.values.first, error == nil {
                                self?.onMovedToTrash?(file.url, trashed)
                            } else {
                                self?.onNotice?("“\(file.name)” was not moved to the Trash: \(error?.localizedDescription ?? "the Finder said no").")
                            }
                        }
                    }
                }
            ]
        case .contact(let match):
            return ContactActions.list(match.record,
                                       shown: [first,
                                               key("Open in Contacts", "person.crop.circle", .openSecond, group: .act)],
                                       act: act, open: { title, symbol, url, _ in open(title, symbol, url) }, copy: copy)
        case .event(let event):
            var list = event.meeting != nil ? [first, key("Open in Calendar", "calendar", .openSecond)] : [first]
            // On now or starting soon: Record ⌘R, as on its card.
            if let label = recordLabel(event) {
                list.insert(LauncherAction(title: label, symbol: "record.circle", key: .record) { [weak self] in
                    self?.hide()
                    self?.onRecordMeeting?(event)
                }, at: 1)
            }
            if event.attendees.contains(where: { $0.email != nil }) { list.append(key("Email Invitees", "envelope", .openThird)) }
            list.append(act("Show Details", "info.circle") { [weak self] in self?.onShowEvent?(event) })
            list.append(copy("Copy Details", Self.plain(Agenda.details(event, now: .now)), .copy))
            if let meeting = event.meeting { list.append(copy("Copy Meeting Link", meeting.url.absoluteString, .copySecond)) }
            list.append(remove("Delete Event") { [weak self] in self?.deleteSelectedEvent() })
            return list
        case .reminder(let reminder):
            var list = [first, key("Open in Reminders", "checklist", .openSecond)]
            if reminder.link != nil { list.append(key("Open Link", "link", .openThird)) }
            // Tomorrow and Next Week change the row where it is (⌘Z puts it
            // back); what needs more is asked in the card: a date, a list, a
            // priority.
            for (title, symbol, nextWeek) in [("Tomorrow", "sunrise", false), ("Next Week", "calendar", true)] {
                list.append(LauncherAction(title: title, symbol: symbol) { [weak self] in self?.moveReminder(reminder, nextWeek: nextWeek) })
            }
            for (title, symbol) in [("Pick a Date…", "calendar.badge.clock"), ("Move to List…", "folder"), ("Priority…", "exclamationmark.circle"),
                                    ("Make Event", "calendar.badge.plus")] {
                list.append(act(title, symbol) { [weak self] in self?.onReminderAction?(reminder, title) })
            }
            list.append(copy("Copy Title", reminder.title, .copy))
            list.append(remove("Delete Reminder") { [weak self] in
                self?.hide()
                self?.onDeleteReminder?(reminder)
            })
            return list
        case .pullRequest(let pullRequest):
            var list = [first]
            // The card asks again before merging.
            if pullRequest.canMerge, let merge = pullRequest.defaultMergeMethod?.title {
                list.append(act(merge + "…", "arrow.triangle.merge") { [weak self] in self?.onPullRequestAction?(pullRequest, merge) })
            }
            if pullRequest.canUpdateBranch {
                list.append(act("Update Branch", "arrow.triangle.2.circlepath") { [weak self] in self?.onPullRequestAction?(pullRequest, "Update Branch") })
            }
            list.append(act("Checks", "checkmark.seal") { [weak self] in self?.onPullRequestAction?(pullRequest, "Checks") })
            return list + [key("Copy Link", "doc.on.doc", .openSecond, group: .copy)]
        case .githubNotification(let notification):
            var list = [
                first,
                LauncherAction(title: "Mark as Read", symbol: "envelope.open", key: removeKey) { [weak self] in
                    guard let github = self?.github else { return }
                    Task { [weak self] in
                        do {
                            try await github.markRead(notification)
                        } catch {
                            self?.say("“\(notification.title)” is still unread: GitHub did not answer. Try again in a moment.")
                        }
                    }
                }
            ]
            // Every notification the list shows (the search narrows it).
            let listed = results.compactMap { if case .githubNotification(let note) = $0 { note } else { nil } }
            if listed.count > 1 {
                list.append(LauncherAction(title: "Mark All as Read", symbol: "envelope.open") { [weak self] in
                    guard let github = self?.github else { return }
                    Task { [weak self] in
                        do {
                            try await github.markRead(listed)
                        } catch {
                            let left = github.unreadNotifications.filter { note in listed.contains { $0.id == note.id } }.count
                            self?.say("\(left) still unread: GitHub did not answer. Try again in a moment.")
                        }
                    }
                })
            }
            return list + [key("Copy Link", "doc.on.doc", .openSecond, group: .copy)]
        case .project(let project):
            return [first, key("Show in Finder", "folder", .openSecond),
                    copy("Copy Path", project.path, .copy)]
        case .script(let command, _):
            return [first, reveal(URL(fileURLWithPath: command.path))]
        case .visit(let visit):
            return [first, key("Copy Link", "doc.on.doc", .openSecond, group: .copy),
                    copy("Copy as Markdown Link", "[\(visit.shownTitle)](\(visit.url))", .copySecond)]
        case .brew(let package):
            var list = [first]
            if main.title != "Open Page" { list.append(key("Open Page", "safari", .openSecond)) }
            list.append(copy("Copy Install Command", "brew install " + (package.isCask ? "--cask " : "") + package.name, .copy))
            if package.installed != nil { list.append(remove("Uninstall") { [weak self] in self?.uninstallSelectedBrew() }) }
            return list
        case .quicklink(let link, let typed, _):
            // What Return opens: what is typed, else the selected text.
            let address = link.address(for: quicklinkQuery(link, typed: typed))
            return [first] + [address.map { copy("Copy Link", $0.absoluteString, .copy) }].compactMap { $0 }
        case .menuItem:
            return [first]
        case .catalog, .catalogHeader:
            // `catalogActions`; a group's name has none.
            return []
        }
    }

    /// Quit and Force Quit on an app's row: the app and its processes, as
    /// Kill Process lists them; Quit goes at once, Force Quit is asked.
    private func quitApp(_ entry: AppIndex.Entry, pid: pid_t, force: Bool) {
        Task { [weak self] in
            let group = ProcessListing.groups(await Processes.snapshot()).first { $0.pids.contains(pid) }
            guard let self else { return }
            guard let group else {
                self.say("\(entry.name) had already quit: nothing to \(force ? "force quit" : "quit").")
                return
            }
            self.onQuitProcess?(ProcessListing.Group(key: group.key, name: entry.name, appPath: group.appPath, entries: group.entries), force)
        }
    }

    /// The card's Markdown as plain lines, for the clipboard.
    private static func plain(_ markdown: String) -> String {
        markdown.split(separator: "\n").map { line in
            let text = line.replacingOccurrences(of: "**", with: "")
            return text.hasPrefix("- ") ? String(text.dropFirst(2)) : text
        }.joined(separator: "\n")
    }

    /// The one action of rows that do one thing.
    private static func openTitle(_ item: LauncherItem) -> String {
        switch item {
        case .command: "Open"
        case .layout: "Apply Layout"
        case .saveLayout: "Save Layout"
        case .openWindow: "Bring Forward"
        case .startTimer: "Start Timer"
        case .keepAwake(let request): request == .allowSleep ? AwakeStatus.turnOff : "Keep Awake"
        case .runningTimer: "Cancel Timer"
        case .createEvent: "Add to Calendar"
        case .addReminder: "Add Reminder"
        case .brewUpgradeAll: "Upgrade All"
        case .setup: "Allow"
        case .ask: "Ask"
        case .scriptArgument, .scriptChoice: "Continue"
        default: "Run"
        }
    }
}
