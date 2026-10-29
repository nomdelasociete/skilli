import AppKit
import Observation
import SkilliCore
import SwiftUI

/// Rule 2 in Settings: a delete made there is undone by the window itself,
/// not by the card over the screen (`AIActionController.offerUndo`, which
/// the launcher keeps). ⌘Z is the window's Edit → Undo, through its undo
/// manager: nothing is taken from the keys, a field being typed in keeps
/// its own ⌘Z. The strip at the bottom of the pane says what went, with
/// its Undo, for the same 10 s; then the undo goes with it (a key, a token
/// never waits longer). Once back, its row is scrolled to and glows, as a
/// row found by the search does. One at a time, as the card: a newer
/// delete takes the older one's place.
@MainActor
@Observable
final class SettingsUndo {
    /// What the strip says.
    struct Shown: Equatable {
        let id: Int
        let title: String
        /// Markdown, as the card's (`UndoDelete.details`).
        let details: String
        /// Why it could not come back (rule 6), in place of Undo.
        var failure: String?
    }

    private(set) var shown: Shown?

    /// Registered with the window's undo manager: one per delete, so it
    /// alone is taken off when its time is up.
    private final class Entry {
        let id: Int
        let pane: SettingsPane
        let row: String?
        let undo: @MainActor () throws -> Void
        weak var manager: UndoManager?

        init(id: Int, pane: SettingsPane, row: String?, manager: UndoManager, undo: @escaping @MainActor () throws -> Void) {
            self.id = id
            self.pane = pane
            self.row = row
            self.manager = manager
            self.undo = undo
        }
    }

    @ObservationIgnored private var pending: Entry?
    @ObservationIgnored private var offers = 0
    /// The row back in its pane: scrolled to, glowing
    /// (`SettingsSearchModel.showRestored`).
    @ObservationIgnored var showRow: @MainActor (_ anchor: String, _ pane: SettingsPane) -> Void = { _, _ in }

    /// Self-test hook: ⌘Z would undo the delete the strip shows.
    var canUndo: Bool { pending?.manager?.canUndo == true }

    /// Done at once in `pane`; ⌘Z or the strip's Undo brings it back for
    /// `seconds`, and `row` into sight.
    func offer(_ title: String, details: String, row: String?, pane: SettingsPane, in manager: UndoManager,
               seconds: Double = UndoDelete.seconds, _ undo: @escaping @MainActor () throws -> Void) {
        drop()
        offers += 1
        let entry = Entry(id: offers, pane: pane, row: row, manager: manager, undo: undo)
        pending = entry
        manager.registerUndo(withTarget: entry) { [weak self] entry in
            MainActor.assumeIsolated { self?.perform(entry) }
        }
        withAnimation(.easeOut(duration: 0.18)) { shown = Shown(id: entry.id, title: title, details: details) }
        let id = entry.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            // Only this delete's strip: a newer one keeps its own time.
            guard let self, self.shown?.id == id else { return }
            self.drop()
            self.hide()
        }
    }

    /// The strip's Undo: this delete, even when something was typed since
    /// (⌘Z would undo the typing first).
    func undoNow() {
        guard let entry = pending else { return }
        entry.manager?.removeAllActions(withTarget: entry)
        perform(entry)
    }

    /// The window closed: its undo manager goes with it.
    func windowClosed() {
        drop()
        shown = nil
    }

    private func perform(_ entry: Entry) {
        guard pending === entry else { return }
        pending = nil
        do {
            try entry.undo()
            hide()
            if let row = entry.row { showRow(row, entry.pane) }
        } catch {
            // Said where the user looks, a moment longer than a glance.
            withAnimation(.easeOut(duration: 0.18)) { shown?.failure = error.localizedDescription }
            let id = entry.id
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard let self, self.shown?.id == id else { return }
                self.hide()
            }
        }
    }

    private func drop() {
        guard let entry = pending else { return }
        pending = nil
        entry.manager?.removeAllActions(withTarget: entry)
    }

    private func hide() {
        withAnimation(.easeIn(duration: 0.18)) { shown = nil }
    }
}

/// The strip at the bottom of the pane while a delete can be undone: what
/// went, its name in bold, Undo ⌘Z. Never takes the keys; a click on Undo
/// is the only thing it does.
struct SettingsUndoStrip: View {
    let undo: SettingsUndo

    var body: some View {
        if let shown = undo.shown {
            HStack(spacing: 10) {
                Image(systemName: shown.failure == nil ? "arrow.uturn.backward" : "exclamationmark.triangle.fill")
                    .foregroundStyle(shown.failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                VStack(alignment: .leading, spacing: 1) {
                    Text(shown.title)
                        .font(.callout.weight(.semibold))
                    Text(Self.line(shown))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(shown.failure == nil ? 1 : 2)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 12)
                if shown.failure == nil {
                    HStack(spacing: 6) {
                        Button("Undo") { undo.undoNow() }
                        KeycapLabel("⌘Z")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: 480)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(shown.id)
        }
    }

    private static func line(_ shown: SettingsUndo.Shown) -> AttributedString {
        if let failure = shown.failure { return AttributedString(failure) }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: shown.details, options: options)) ?? AttributedString(shown.details)
    }
}
