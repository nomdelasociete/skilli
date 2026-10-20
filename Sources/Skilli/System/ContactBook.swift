import AppKit
import Contacts
import SkilliCore

/// The user's contacts, read through the Contacts framework once allowed,
/// kept in memory and read again when they change. Searched without a
/// model (`ContactSearch`); nothing leaves the Mac.
@MainActor
final class ContactBook {
    /// The self-test's contacts instead of the user's (never read then).
    var testRecords: [ContactRecord]? {
        didSet { testIndex = testRecords.map(ContactSearch.Index.init) }
    }
    private var testIndex: ContactSearch.Index?
    /// The self-test's "My Card" among `testRecords`.
    var testMeID: String?
    private var cache: (records: [ContactRecord], index: ContactSearch.Index)?
    private var loading: Task<(records: [ContactRecord], index: ContactSearch.Index), Never>?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cache = nil
                self?.loading = nil
            }
        }
    }

    /// Off in the self-test: macOS is never asked there.
    var asksTheMac = true

    var isAllowed: Bool {
        if testRecords != nil { return true }
        return CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    /// Never asked: the first use shows macOS's prompt.
    var canAsk: Bool {
        testRecords == nil && asksTheMac && CNContactStore.authorizationStatus(for: .contacts) == .notDetermined
    }

    /// Allowed, asking macOS the first time (its own prompt), where the
    /// feature needs it (D7). The async form: its answer comes back here,
    /// not on the queue a completion block runs on.
    func allow() async -> Bool {
        if isAllowed { return true }
        guard canAsk else { return false }
        let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        cache = nil
        loading = nil
        return granted
    }

    /// Every contact, read once and indexed (a few hundred ms for
    /// thousands, off the main thread) then from memory.
    func records() async -> [ContactRecord] {
        await loaded()?.records ?? []
    }

    private func loaded() async -> (records: [ContactRecord], index: ContactSearch.Index)? {
        if let testRecords, let testIndex { return (testRecords, testIndex) }
        guard isAllowed else { return nil }
        if let cache { return cache }
        if let loading { return await loading.value }
        let task = Task.detached(priority: .userInitiated) { () -> (records: [ContactRecord], index: ContactSearch.Index) in
            let records = Self.read()
            return (records, ContactSearch.Index(records))
        }
        loading = task
        let read = await task.value
        cache = read
        loading = nil
        Log.trace("Contacts: \(read.records.count) read and indexed")
        return read
    }

    /// From memory only, for a search that must not wait: empty until the
    /// contacts were read (which this starts).
    /// Names, nicknames and companies only, by a word or its start: for
    /// the launcher's every keystroke (well under a millisecond).
    func cachedMatches(_ query: String, limit: Int) -> [ContactSearch.Match] {
        if let testIndex { return ContactSearch.quickSearch(query, in: testIndex, limit: limit) }
        guard let cache else {
            if isAllowed, loading == nil { Task { _ = await loaded() } }
            return []
        }
        return ContactSearch.quickSearch(query, in: cache.index, limit: limit)
    }

    /// Every field, off the main thread.
    func search(_ query: String, limit: Int = 20) async -> [ContactSearch.Match] {
        guard let index = await loaded()?.index else { return [] }
        return await Task.detached(priority: .userInitiated) { ContactSearch.search(query, in: index, limit: limit) }.value
    }

    func record(id: String) async -> ContactRecord? {
        await records().first { $0.id == id }
    }

    /// The user's own card ("My Card" in Contacts).
    func me() async -> ContactRecord? {
        if testRecords != nil {
            guard let testMeID else { return nil }
            return await record(id: testMeID)
        }
        guard isAllowed else { return nil }
        let id = await Task.detached(priority: .userInitiated) { () -> String? in
            try? CNContactStore().unifiedMeContactWithKeys(toFetch: [CNContactIdentifierKey as CNKeyDescriptor]).identifier
        }.value
        guard let id else { return nil }
        return await record(id: id)
    }

    /// The address on the user's card labelled Home or Work, in one line
    /// ("12 rue des Lilas, 75011 Paris, France"): where "en arrivant à la
    /// maison" rings when no place is saved under that name.
    func myAddress(_ kind: SavedPlace.CardAddress) async -> String? {
        if let testMeAddresses { return testMeAddresses[kind] }
        guard isAllowed else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> String? in
            guard let me = try? CNContactStore().unifiedMeContactWithKeys(toFetch: [CNContactPostalAddressesKey as CNKeyDescriptor]) else { return nil }
            let label = kind == .home ? CNLabelHome : CNLabelWork
            guard let address = me.postalAddresses.first(where: { $0.label == label })?.value else { return nil }
            return CNPostalAddressFormatter.string(from: address, style: .mailingAddress)
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
        }.value
    }

    /// Self-test hook: the card's Home and Work addresses.
    var testMeAddresses: [SavedPlace.CardAddress: String]?

    /// The contact `words` name, first name first ("Margot", "Paul
    /// Martin"); nil when none or several fit.
    func person(named words: [String]) async -> ContactRecord? {
        guard let first = words.first.map(Self.folded) else { return nil }
        let all = await records()
        let named = all.filter { Self.folded($0.givenName) == first || Self.folded($0.nickname) == first }
        // "Paul Martin": the family name decides between two Pauls; a word
        // after the name that is not one ("pour Margot demain") does not.
        if let second = words.dropFirst().first.map(Self.folded) {
            let both = named.filter { Self.folded($0.familyName).hasPrefix(second) }
            if both.count == 1 { return both[0] }
        }
        return named.count == 1 ? named[0] : nil
    }

    private static func folded(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    }

    private nonisolated static func read() -> [ContactRecord] {
        let store = CNContactStore()
        // The note field needs Apple's com.apple.developer.contacts.notes,
        // which skil.li does not have yet: never asked for, so macOS does
        // not refuse the whole read.
        let keys = [
            CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
            CNContactOrganizationNameKey, CNContactDepartmentNameKey, CNContactJobTitleKey,
            CNContactEmailAddressesKey, CNContactPhoneNumbersKey, CNContactPostalAddressesKey,
            CNContactUrlAddressesKey, CNContactSocialProfilesKey, CNContactRelationsKey, CNContactBirthdayKey
        ] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var records: [ContactRecord] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in records.append(record(contact)) }
        } catch {
            Log.actions.error("Contacts not read: \(error.localizedDescription, privacy: .public)")
        }
        return records
    }

    private nonisolated static func record(_ contact: CNContact) -> ContactRecord {
        func label(_ raw: String?) -> String {
            raw.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? ""
        }
        var record = ContactRecord(id: contact.identifier)
        record.givenName = contact.givenName
        record.middleName = contact.middleName
        record.familyName = contact.familyName
        record.nickname = contact.nickname
        record.organization = contact.organizationName
        record.department = contact.departmentName
        record.jobTitle = contact.jobTitle
        record.emails = contact.emailAddresses.map { .init(label($0.label), $0.value as String) }
        record.phones = contact.phoneNumbers.map { .init(label($0.label), $0.value.stringValue) }
        let formatter = CNPostalAddressFormatter()
        record.addresses = contact.postalAddresses.map {
            .init(label($0.label), formatter.string(from: $0.value).replacingOccurrences(of: "\n", with: ", "))
        }
        record.postal = contact.postalAddresses.map {
            .init(label: label($0.label), street: $0.value.street.replacingOccurrences(of: "\n", with: ", "), postalCode: $0.value.postalCode,
                  city: $0.value.city, country: $0.value.country)
        }
        record.urls = contact.urlAddresses.map { .init(label($0.label), $0.value as String) }
        record.social = contact.socialProfiles.map { .init($0.value.service, $0.value.username.isEmpty ? $0.value.urlString : $0.value.username) }
        record.relations = contact.contactRelations.map { .init(label($0.label), $0.value.name) }
        if let birthday = contact.birthday, birthday.year != nil, let date = Calendar.current.date(from: birthday) {
            record.birthdayNumeric = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
        }
        if let birthday = contact.birthday, let date = Calendar.current.date(from: birthday) {
            record.birthday = DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .none)
        }
        return record
    }

    /// The contact in the Contacts app.
    /// The contact's photo, small, as Contacts keeps it; nil without one.
    /// Read off the main thread, on this Mac only.
    static func thumbnail(id: String) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            let keys = [CNContactThumbnailImageDataKey as CNKeyDescriptor]
            return (try? CNContactStore().unifiedContact(withIdentifier: id, keysToFetch: keys))?.thumbnailImageData
        }.value
    }

    static func openInContacts(_ id: String) {
        guard let url = URL(string: "addressbook://\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Says what failed and what to do (the card), never a bare beep.
    static var onFailure: ((String) -> Void)?

    /// The contact's card (.vcf) in a new message: Messages opens with it
    /// attached and nothing sent. `failed`: what went wrong, in one line
    /// (without it, `onFailure`).
    static func sendCard(id: String, failed: (@MainActor @Sendable (String) -> Void)? = nil) {
        Task.detached(priority: .userInitiated) {
            let keys = [CNContactVCardSerialization.descriptorForRequiredKeys()]
            guard let contact = try? CNContactStore().unifiedContact(withIdentifier: id, keysToFetch: keys),
                  let data = try? CNContactVCardSerialization.data(with: [contact]) else {
                await MainActor.run {
                    let said = "Contacts did not give this card: open it in Contacts and share it from there."
                    if let failed { failed(said) } else { onFailure?(said) }
                }
                return
            }
            let name = (CNContactFormatter.string(from: contact, style: .fullName) ?? "Contact")
                .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("contact-cards", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(name + ".vcf")
            guard (try? data.write(to: file)) != nil else { return }
            await MainActor.run {
                if NSSharingService(named: .composeMessage)?.canPerform(withItems: [file]) == true {
                    NSSharingService(named: .composeMessage)?.perform(withItems: [file])
                } else if let failed {
                    failed("Messages cannot send a contact card here: set up Messages, then try again.")
                } else {
                    onFailure?("Messages cannot take “\(name)”'s card on this Mac: share it from the Contacts app (⌘↩ on the contact).")
                }
            }
        }
    }

    /// A new message in the user's mail app: mailto, nothing sent.
    static func mailURL(to addresses: [String], subject: String = "", body: String = "") -> URL? {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = addresses.joined(separator: ",")
        // "ç" as one letter, as mail apps expect.
        let subject = subject.precomposedStringWithCanonicalMapping, body = body.precomposedStringWithCanonicalMapping
        var items: [URLQueryItem] = []
        if !subject.isEmpty { items.append(URLQueryItem(name: "subject", value: subject)) }
        if !body.isEmpty { items.append(URLQueryItem(name: "body", value: body)) }
        if !items.isEmpty { parts.queryItems = items }
        return parts.url
    }
}
