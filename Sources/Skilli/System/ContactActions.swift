import AppKit
import SkilliCore

/// What can be done with a contact: the same list in the launcher's ⌘K and
/// in the contact's card, each with the same key. `shown`: the first rows,
/// what the place itself does with ↩ and ⌘↩ (the launcher shows the card
/// and opens Contacts; the card, already showing it, reaches them with ↩).
@MainActor
enum ContactActions {
    /// `afterReach`: rows after the ways to reach them (the card's Open in
    /// Contacts, so its ↩ row comes first). `say`: what failed, in one line.
    static func list(_ record: ContactRecord, shown: [LauncherAction], afterReach: [LauncherAction] = [],
                     act: (String, String, @escaping @MainActor () -> Void) -> LauncherAction,
                     open: (String, String, URL?, LauncherAction.Key?) -> LauncherAction?,
                     copy: (String, String, LauncherAction.Key?) -> LauncherAction,
                     reachKey: LauncherAction.Key? = nil, say: (@MainActor @Sendable (String) -> Void)? = nil) -> [LauncherAction] {
        let first = record.givenName.isEmpty ? record.name : record.givenName
        let phones = mobileFirst(record.phones)
        let dialable = phones.first.map { $0.value.filter { $0.isNumber || $0 == "+" } }
        let message = dialable.map { "sms:" + $0 } ?? record.emails.first.map { "imessage:" + $0.value }
        // `reachKey` (the card's ↩): a message with a number, else a mail.
        let messageURL = message.flatMap(URL.init(string:))
        let mailURL = record.emails.first.flatMap { ContactBook.mailURL(to: [$0.value]) }
        let keyed = dialable != nil ? "message" : mailURL != nil ? "mail" : nil
        var list = shown
        list += [messageURL.flatMap { open("Message \(first)", "message", $0, keyed == "message" ? reachKey : nil) },
                 dialable.flatMap { URL(string: "tel:" + $0) }.flatMap { open("Call \(first)", "phone", $0, nil) },
                 mailURL.flatMap { open("Email \(first)", "envelope", $0, keyed == "mail" ? reachKey : nil) }].compactMap { $0 }
        list += afterReach
        list.append(act("Send Contact Card…", "person.crop.square.filled.and.at.rectangle") { ContactBook.sendCard(id: record.id, failed: say) })
        list.append(copy("Copy Name", record.name, .copy))
        // Each number and address with its label; ⇧⌘C the first.
        let items = phones.prefix(3).map { ("Phone", $0) } + record.emails.prefix(3).map { ("Email", $0) }
        for (index, (kind, item)) in items.enumerated() {
            list.append(copy(item.label.isEmpty ? "Copy \(kind)" : "Copy \(kind) (\(item.label))", item.value, index == 0 ? .copySecond : nil))
        }
        if let address = record.addresses.first { list.append(copy("Copy Address", address.value, nil)) }
        return list
    }

    /// The mobile first: the one to text or call.
    static func mobileFirst(_ phones: [ContactRecord.Item]) -> [ContactRecord.Item] {
        phones.sorted { isMobile($0.label) && !isMobile($1.label) }
    }

    static func isMobile(_ label: String) -> Bool {
        ["mobile", "iphone", "portable", "cell"].contains { label.lowercased().contains($0) }
    }
}
