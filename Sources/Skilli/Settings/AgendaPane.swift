import AppKit
import SkilliCore
import SwiftUI

/// Settings → Calendar, by the Settings rules: how it is reached (the
/// agenda's prefix, adding an event), the three settings that matter (the
/// next meeting in the menu bar, the alerts, what happens as a meeting
/// starts) with their previews, the rest under Advanced, what leaves the
/// Mac (nothing); then every calendar, by account (long lists go last).
struct AgendaPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Privacy, from what leaves the Mac).
    let open: (SettingsPane) -> Void
    @State private var accounts: [CalendarAccount] = []

    /// Calendar apps ⌘↩ may open events in, when installed.
    private static let calendarApps: [(id: String, name: String)] = [
        ("com.apple.iCal", "Calendar"), ("com.flexibits.fantastical2.mac", "Fantastical"), ("com.cron.electron", "Notion Calendar"),
        ("com.busymac.busycal3", "BusyCal"), ("com.microsoft.Outlook", "Outlook")
    ]

    /// The ones on this Mac (Calendar always): the pane's choices, and
    /// set_setting's.
    static var installedCalendarApps: [(id: String, name: String)] {
        calendarApps.filter { $0.id == "com.apple.iCal" || NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }

    var body: some View {
        Form {
            // What matters first: the meeting in the menu bar, the alerts,
            // what happens as a meeting starts. The rest under Advanced.
            Section {
                missing(.calendar)
                Picker("Next meeting in the menu bar", selection: $preferences.agendaMenuBar) {
                    ForEach(MeetingMenuBar.allCases) { Text($0.title).tag($0) }
                }
                .settingAnchor("agendaMenuBar")
                if preferences.agendaMenuBar != .never {
                    MeetingMenuBarPreview(options: MeetingBar.Options(preferences))
                }
            } header: {
                VStack(spacing: 10) {
                    PaneHeader(pane: .calendar)
                    PaneReach(entries: ["cmd:agenda", "catalog.event"], aliases: preferences.launcherAliases)
                        .padding(.bottom, 12)
                }
            } footer: {
                Text("Red: the call started and you have not joined it from this Mac (no Join from skil.li, no app on the microphone since just before it). Its menu joins the call, shows it in Calendar, opens the agenda, or dismisses it until the next one. In the launcher, the next meeting comes first: ↩ joins.")
            }

            Section {
                ForEach(preferences.agendaAlerts.indices, id: \.self) { index in
                    HStack {
                        Picker("When", selection: $preferences.agendaAlerts[index].minutes) {
                            ForEach(MeetingAlert.choices, id: \.self) { Text(MeetingAlert.spoken($0)).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Picker("How", selection: $preferences.agendaAlerts[index].style) {
                            ForEach(MeetingAlert.Style.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Spacer()
                        Button("Try") { context.tryMeetingAlert(preferences.agendaAlerts[index]) }
                        Button {
                            preferences.agendaAlerts.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove this alert")
                    }
                }
                Button("Add Alert") {
                    let taken = Set(preferences.agendaAlerts.map(\.minutes))
                    let minutes = [0, 5, 10, 2, 15, 1, 30, 60].first { !taken.contains($0) } ?? 5
                    preferences.agendaAlerts.append(MeetingAlert(minutes: minutes, style: .card))
                }
                if let first = preferences.agendaAlerts.first {
                    MeetingCardPreview(dark: preferences.agendaAlerts.contains { $0.style == .dark }, minutes: first.minutes)
                }
            } header: {
                Text("Alerts")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("agendaAlerts")
            } footer: {
                Text("A card in the middle of the screen, the time counting down: ↩ joins, ⌘↩ shows it in Calendar, ⇥ checks your camera and microphone first, esc lets it go. Screens dark: every screen goes black around it until it goes, for the meetings you cannot miss. None for a call you are in already (joined from skil.li, or an app on the microphone since just before it); a card still up goes as you join.")
            }

            Section {
                Picker("When a meeting starts", selection: $preferences.agendaAutoJoin) {
                    ForEach(MeetingAutoJoin.allCases) { Text($0.title).tag($0) }
                }
                .settingAnchor("agendaAutoJoin")
            } footer: {
                Text("Join at once opens its call as it starts: no alert On time for it. A call you are in already is not opened again.")
            }

            if let line = PrivacyMap.line(for: SettingsPane.calendar.rawValue, .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            AdvancedSection(summary: "When the launcher shows it, the menu bar's details, where events open",
                            footer: "The next meeting is first in the empty launcher from that long before it starts to as long after. ⌘↩ on an event shows it in the app chosen; Zoom and Teams calls open in their own app when it is installed.",
                            anchors: ["agendaLauncherMinutes", "agendaMenuBarCallsOnly", "agendaCountdown", "agendaHideAfter", "agendaNextDuringMeeting",
                                     "agendaAlertWithoutCall", "agendaApp", "agendaMeetBrowser"]) {
                Picker("Before you type, the meeting shows", selection: $preferences.agendaLauncherMinutes) {
                    ForEach([2, 5, 10, 15, 30], id: \.self) { Text("From \($0) minutes before").tag($0) }
                }
                .settingAnchor("agendaLauncherMinutes")
                if preferences.agendaMenuBar != .never {
                    Toggle("Only meetings with a call in the menu bar", isOn: $preferences.agendaMenuBarCallsOnly)
                        .settingAnchor("agendaMenuBarCallsOnly")
                    Toggle("Count down to its end", isOn: $preferences.agendaCountdown)
                        .settingAnchor("agendaCountdown")
                    if !preferences.agendaCountdown {
                        Picker("Leaves the menu bar", selection: $preferences.agendaHideAfter) {
                            ForEach([5, 10, 15], id: \.self) { Text("\($0) minutes after it starts").tag($0) }
                            Text("When it ends").tag(-1)
                        }
                        .settingAnchor("agendaHideAfter")
                    }
                    Toggle("The next one too, during a meeting", isOn: $preferences.agendaNextDuringMeeting)
                        .settingAnchor("agendaNextDuringMeeting")
                }
                if !preferences.agendaAlerts.isEmpty {
                    Toggle("Alerts for events without a call too", isOn: $preferences.agendaAlertWithoutCall)
                        .settingAnchor("agendaAlertWithoutCall")
                }
                Picker("Open events in", selection: $preferences.agendaApp) {
                    ForEach(Self.installedCalendarApps, id: \.id) { Text($0.name).tag($0.id) }
                }
                .settingAnchor("agendaApp")
                Picker("Google Meet opens in", selection: $preferences.agendaMeetBrowser) {
                    Text("Default browser").tag("")
                    ForEach(Self.browsers(), id: \.id) { Text($0.name).tag($0.id) }
                }
                .settingAnchor("agendaMeetBrowser")
            }

            // The long lists last: every calendar, by account.
            ForEach(accounts) { account in
                Section {
                    ForEach(account.calendars) { calendar in
                        Toggle(isOn: shown(calendar.id)) {
                            HStack(spacing: 8) {
                                Circle().fill(Color(nsColor: calendar.color)).frame(width: 9, height: 9)
                                Text(calendar.title)
                            }
                        }
                    }
                } header: {
                    // The first account's name: where the calendars start.
                    if account.id == accounts.first?.id {
                        Text(account.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .settingAnchor("agendaHiddenCalendars")
                    } else {
                        Text(account.name)
                    }
                } footer: {
                    if account.id == accounts.last?.id {
                        Text("Every account in the Calendar app. A calendar turned off stays out of the agenda, the next meeting and Ask.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accounts = context.calendarAccounts()
            context.permissions.startWatching()
        }
        .onDisappear { context.permissions.stopWatching() }
        .onChange(of: context.permissions.state(.calendar)) { accounts = context.calendarAccounts() }
    }

    /// Rule 6: the permission beside the feature, only while it is missing.
    @ViewBuilder
    private func missing(_ permission: Permission) -> some View {
        let state = context.permissions.state(permission)
        if state != .granted {
            PermissionRow(permission: permission, state: state, notNeeded: false) { context.permissions.grant(permission) }
        }
    }

    private func shown(_ id: String) -> Binding<Bool> {
        Binding {
            !preferences.agendaHiddenCalendars.contains(id)
        } set: { isShown in
            var hidden = Set(preferences.agendaHiddenCalendars)
            if isShown { hidden.remove(id) } else { hidden.insert(id) }
            preferences.agendaHiddenCalendars = hidden.sorted()
        }
    }

    /// The apps that open web links, by name.
    static func browsers() -> [(id: String, name: String)] {
        guard let probe = URL(string: "https://meet.google.com") else { return [] }
        var list: [(id: String, name: String)] = []
        for url in NSWorkspace.shared.urlsForApplications(toOpen: probe) {
            guard let id = Bundle(url: url)?.bundleIdentifier, !list.contains(where: { $0.id == id }) else { continue }
            list.append((id, FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")))
        }
        return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
