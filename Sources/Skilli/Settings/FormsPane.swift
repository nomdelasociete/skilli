import AppKit
import SkilliCore
import SwiftUI

/// Settings → Your Details, in the order of the Settings plan's rules: how
/// it is reached (Ask's keys, then the words), whose details "do it here"
/// types into a form: the user's own card in Contacts (My Card; Contacts'
/// permission beside it, only while missing) and the fields kept here
/// beyond it (a SIRET, an IBAN); About You, the text sent with Ask and the
/// commands that include it; what leaves the Mac and to whom; last, the
/// long lists: the people and companies kept here (their Contacts card by
/// name, fields of their own), and what forms get from the card. Typed on
/// this Mac; the decision model only reads what each field asks. Sensitive
/// values stay in the Keychain and are typed only after ↩ in the card.
struct FormsPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    @Bindable var aiCommands: AICommandsModel
    /// Shows another pane (Privacy).
    let open: (SettingsPane) -> Void
    @State private var card: ContactRecord?
    @State private var loaded = false
    @State private var newPerson = ""

    private var contacts: PermissionCenter.State { context.permissions.state(.contacts) }

    var body: some View {
        Form {
            Section {
                ReachRow(title: "With Ask", detail: "In the window with the form: “fill this with my details”, or “… for Margot”.",
                         chords: context.shortcuts.config.shortcuts.first { $0.action == .aiPrompt(PromptLibrary.askID) }?.chords)
                if contacts != .granted {
                    PermissionRow(permission: .contacts, state: contacts, notNeeded: false) {
                        context.permissions.grant(.contacts)
                    }
                } else if let card {
                    LabeledContent {
                        Button("Edit in Contacts") { ContactBook.openInContacts(card.id) }
                    } label: {
                        LabelDetail("Your card", card.name)
                    }
                } else if loaded {
                    LabeledContent {
                        Button("Open Contacts") {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.AddressBook") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    } label: {
                        LabelDetail("Your card", "None yet: in Contacts, select yours, then Card › Make This My Card.")
                    }
                }
            } header: {
                PaneHeader(pane: .yourDetails)
            } footer: {
                Text("Your card and your other details below go into the form, typed by skil.li on this Mac.")
            }

            Section {
                ForEach($preferences.formProfiles.mine) { $extra in
                    ExtraRow(extra: $extra) { context.deletes.myDetail(extra, in: preferences) }
                        .settingAnchor(UndoDelete.row(.detail, extra.id))
                }
                AddFieldMenu(present: preferences.formProfiles.mine.map(\.label)) { preferences.formProfiles.mine.append($0) }
            } header: {
                Text("Your other details")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("otherDetails")
            } footer: {
                Text("What Contacts does not keep: a SIRET, a VAT number… The lock keeps a value in the Keychain (an IBAN, a social security number): it is typed only after ↩ in the card.")
            }

            Section {
                ZStack(alignment: .topLeading) {
                    if aiCommands.profile.isEmpty {
                        Text("Who you are, in a few lines: name, role, languages, how you like to write.")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $aiCommands.profile)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(height: 76)
                        .onChange(of: aiCommands.profile) { aiCommands.saveProfile() }
                }
            } header: {
                Text("About You")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("aboutYou")
            } footer: {
                SIText("Sent to your SI with Ask and the commands that include it (Include About You, or {profile} in a prompt). Saved on this Mac in about-you.md.")
            }

            if let line = PrivacyMap.line(for: SettingsPane.yourDetails.rawValue, .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            // The long lists, last.
            Section {
                ForEach($preferences.formProfiles.others) { $person in
                    PersonRow(person: $person, context: context, preferences: preferences) {
                        context.deletes.person(person, in: preferences)
                    }
                    .settingAnchor(UndoDelete.row(.person, person.id))
                }
                HStack {
                    TextField("Person or company", text: $newPerson, prompt: Text("A person or a company: Margot Martin, Nimbus SAS"))
                        .labelsHidden()
                        .onSubmit(addPerson)
                    Button("Add", action: addPerson)
                        .disabled(newPerson.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("People and companies")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("people")
            } footer: {
                Text("“Fill this for Margot”: Margot's Contacts card, found by her name, and the fields kept here. Anyone with a Contacts card works without being added; add someone for fields Contacts does not keep, or a company without a card.")
            }

            if let card {
                Section {
                    ForEach(FormProfile.details(of: card), id: \.key) { detail in
                        LabeledContent(detail.description.components(separatedBy: " (").first ?? detail.key, value: detail.value)
                    }
                } header: {
                    Text("What forms get from your card")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            aiCommands.refresh()
            context.permissions.startWatching()
        }
        .onDisappear { context.permissions.stopWatching() }
        // Again once Contacts is allowed here.
        .task(id: contacts) {
            card = contacts == .granted ? await context.myCard() : nil
            loaded = true
        }
    }

    private func addPerson() {
        let name = newPerson.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        preferences.formProfiles.others.append(FormPerson(name: name))
        newPerson = ""
    }
}

/// One field kept in skil.li: its name, its value (in the Keychain when
/// locked), the lock, remove.
private struct ExtraRow: View {
    @Binding var extra: FormExtra
    let onRemove: () -> Void
    @State private var secret = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("Field", text: $extra.label, prompt: Text("Field: SIRET, IBAN…"))
                .labelsHidden()
                .frame(width: 200)
            if extra.isSensitive {
                SecureField("Value", text: $secret, prompt: Text("Value, kept in the Keychain"))
                    .labelsHidden()
                    .onChange(of: secret) { FormSecrets.save(secret, for: extra) }
            } else {
                TextField("Value", text: $extra.value, prompt: Text("Value"))
                    .labelsHidden()
            }
            Button {
                toggleLock()
            } label: {
                Image(systemName: extra.isSensitive ? "lock.fill" : "lock.open")
            }
            .buttonStyle(.borderless)
            .help(extra.isSensitive ? "In the Keychain, typed only after ↩. Click to keep it in plain text."
                                    : "Click to keep it in the Keychain and type it only after ↩")
            // At once, its Keychain value with it; ⌘Z in the card puts
            // both back (`UndoableDeletes`).
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Forget this field")
        }
        .onAppear {
            if extra.isSensitive { secret = FormSecrets.value(of: extra) ?? "" }
        }
    }

    /// The value moves with the lock: into the Keychain, or back out.
    private func toggleLock() {
        if extra.isSensitive {
            extra.value = secret
            FormSecrets.forget(extra)
            extra.isSensitive = false
        } else {
            secret = extra.value
            extra.value = ""
            extra.isSensitive = true
            FormSecrets.save(secret, for: extra)
        }
    }
}

/// "Add a Field": the usual ones not there yet, then any other.
private struct AddFieldMenu: View {
    let present: [String]
    let add: (FormExtra) -> Void

    var body: some View {
        Menu("Add a Field") {
            ForEach(FormProfile.suggestedFields.filter { !present.contains($0.label) }, id: \.label) { field in
                Button(field.sensitive ? "\(field.label) (in the Keychain)" : field.label) {
                    add(FormExtra(label: field.label, isSensitive: field.sensitive))
                }
            }
            Divider()
            Button("Another Field") { add(FormExtra(label: "", isSensitive: false)) }
        }
        .fixedSize()
    }
}

/// A person or company kept in skil.li: their name, whether a Contacts card
/// has it, their fields.
private struct PersonRow: View {
    @Binding var person: FormPerson
    let context: SettingsContext
    let preferences: Preferences
    let onRemove: () -> Void
    @State private var card: ContactRecord?

    var body: some View {
        DisclosureGroup {
            ForEach($person.extras) { $extra in
                ExtraRow(extra: $extra) { context.deletes.detail(extra, of: person.id, in: preferences) }
                    .settingAnchor(UndoDelete.row(.detail, extra.id))
            }
            HStack {
                AddFieldMenu(present: person.extras.map(\.label)) { person.extras.append($0) }
                Spacer()
                Button("Remove \(person.name.isEmpty ? "It" : person.name)", role: .destructive, action: onRemove)
            }
        } label: {
            HStack {
                TextField("Name", text: $person.name, prompt: Text("Name"))
                    .labelsHidden()
                Text(card.map { "Contacts: \($0.name)" } ?? "No Contacts card")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .task(id: person.name) {
            card = await context.contactNamed(person.name.split(separator: " ").map(String.init))
        }
    }
}

// MARK: - Sensitive values

/// The values of sensitive form fields (an IBAN, a social security
/// number): in skil.li's Keychain items, one per field, never in the
/// preferences. The self-test keeps its own (`prefix`).
@MainActor
enum FormSecrets {
    /// "selftest-" in the self-test, so it never touches the user's items.
    static var prefix = ""

    static func value(of extra: FormExtra) -> String? {
        extra.isSensitive ? Keychain.read(account: account(extra)) : extra.value
    }

    static func save(_ value: String, for extra: FormExtra) {
        if value.isEmpty {
            Keychain.delete(account: account(extra))
        } else {
            try? Keychain.save(value, account: account(extra))
        }
    }

    /// A field removed (or made not sensitive): its Keychain item goes.
    static func forget(_ extra: FormExtra) {
        Keychain.delete(account: account(extra))
    }

    private static func account(_ extra: FormExtra) -> String {
        "\(prefix)form-\(extra.id.uuidString)"
    }
}
