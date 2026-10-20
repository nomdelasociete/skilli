import MapKit
import SkilliCore
import SwiftUI

/// Settings → Reminders, by the Settings rules: how it is reached ("todo",
/// "remind me"), the two settings that matter (where said reminders go,
/// today's in the menu bar, with its preview), then the places "en
/// arrivant au bureau" rings at (the list last) and what leaves the Mac
/// for them.
struct RemindersPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Privacy, from what leaves the Mac).
    let open: (SettingsPane) -> Void
    @State private var lists: [String] = []
    @State private var newName = ""
    @State private var newAddress = ""
    @State private var finding = false
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                let state = context.permissions.state(.reminders)
                if state != .granted {
                    // Where said reminders go waits for this: found here.
                    PermissionRow(permission: .reminders, state: state, notNeeded: false) { context.permissions.grant(.reminders) }
                        .settingAnchor("remindersDefaultList")
                } else {
                    Picker("Said reminders go to", selection: $preferences.remindersDefaultList) {
                        Text("The Reminders app's default list").tag("")
                        ForEach(lists, id: \.self) { Text($0).tag($0) }
                    }
                    .settingAnchor("remindersDefaultList")
                }
            } header: {
                VStack(spacing: 10) {
                    PaneHeader(pane: .reminders)
                    PaneReach(entries: ["cmd:reminders", "catalog.remind"], aliases: preferences.launcherAliases)
                        .padding(.bottom, 12)
                }
            } footer: {
                Text("Said in one sentence, in the launcher or Ask: “rappelle-moi d'appeler Paul demain 9h !! #courses”. # picks a list, ! to !!! the priority. “todo” lists them.")
            }

            Section {
                Picker("Today's reminders in the menu bar", selection: $preferences.remindersMenuBar) {
                    ForEach(RemindersMenuBar.allCases) { Text($0.title).tag($0) }
                }
                .settingAnchor("remindersMenuBar")
                if preferences.remindersMenuBar != .never {
                    RemindersMenuBarPreview(mode: preferences.remindersMenuBar)
                }
            } footer: {
                Text("Due today or overdue; hidden when there are none. Click one in its menu to check it off.")
            }

            if let line = PrivacyMap.line(for: SettingsPane.reminders.rawValue, .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            // The long list last: the places.
            Section {
                ForEach(preferences.reminderPlaces) { place in
                    LabeledContent(place.name) {
                        HStack {
                            Text(place.address).foregroundStyle(.secondary).lineLimit(1)
                            Button {
                                context.deletes.place(place, in: preferences)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Forget this place")
                        }
                    }
                }
                HStack {
                    TextField("Name", text: $newName, prompt: Text("Name: Bureau"))
                        .labelsHidden()
                        .frame(width: 140)
                    TextField("Address", text: $newAddress, prompt: Text("Address: 12 rue de la Paix, Paris"))
                        .labelsHidden()
                    Button(finding ? "Finding…" : "Add") { add() }
                        .disabled(finding || newName.trimmingCharacters(in: .whitespaces).isEmpty || newAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let problem {
                    Text(problem).foregroundStyle(.red)
                }
            } header: {
                Text("Places")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("reminderPlaces")
            } footer: {
                Text("“rappelle-moi d'acheter du pain en partant du bureau”, “remind me when I get home”: the reminder rings there, on your iPhone too. Maison and home, bureau and work are the same place.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            lists = context.reminderLists()
            context.permissions.startWatching()
        }
        .onDisappear { context.permissions.stopWatching() }
        .onChange(of: context.permissions.state(.reminders)) { lists = context.reminderLists() }
    }

    /// The address found by Apple Maps, then saved with its name.
    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let address = newAddress.trimmingCharacters(in: .whitespaces)
        guard let request = MKGeocodingRequest(addressString: address) else { return }
        finding = true
        problem = nil
        Task {
            defer { finding = false }
            guard let location = (try? await request.mapItems)?.first?.location else {
                problem = "Apple Maps found no place at “\(address)”."
                return
            }
            preferences.reminderPlaces.append(SavedPlace(name: name, address: address, latitude: location.coordinate.latitude,
                                                         longitude: location.coordinate.longitude))
            newName = ""
            newAddress = ""
        }
    }
}
