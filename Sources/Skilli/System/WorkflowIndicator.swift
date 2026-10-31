import AppKit
import SkilliCore

/// While a GitHub workflow started from skil.li runs
/// (docs/github-workflow-runs.md): a shipping box in the menu bar with
/// how far the newest run is ("3/7", "Waiting"), as Keep Awake's cup shows
/// its time. Its menu lists every run followed, each job and step with its
/// state, live while the menu is open; Open on GitHub, Cancel Run. Gone
/// when no run is followed: the end card says how it ended.
@MainActor
final class WorkflowIndicator: NSObject {
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var cancel: ((Int) -> Void)?
    private var item: NSStatusItem?
    private let menu = NSMenu()

    /// Self-test hooks: the text beside the box (nil while hidden), and
    /// the menu's lines.
    var shown: String? { item?.button?.title.trimmingCharacters(in: .whitespaces) }
    var lines: [String] { menu.items.filter { !$0.isSeparatorItem }.map(\.title) }

    /// Shown, changed or gone as the runs are now.
    func update(_ runs: [WorkflowProgress], problems: [Int: String]) {
        guard let newest = runs.last else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        if item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            item.button?.image?.isTemplate = true
            item.button?.imagePosition = .imageLeading
            item.menu = menu
            self.item = item
        }
        item?.button?.title = " " + newest.label
        item?.button?.setAccessibilityLabel("\(newest.run.title): \(newest.label)")
        // Filled in place: an open menu shows each step as it moves.
        menu.removeAllItems()
        for (index, progress) in runs.reversed().enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            add(progress, problem: problems[progress.run.id])
        }
    }

    private func add(_ progress: WorkflowProgress, problem: String?) {
        let headline = NSMenuItem(title: progress.headline, action: nil, keyEquivalent: "")
        headline.isEnabled = false
        menu.addItem(headline)
        if let problem {
            let said = NSMenuItem(title: problem, action: nil, keyEquivalent: "")
            said.isEnabled = false
            said.image = Self.symbol("exclamationmark.triangle")
            menu.addItem(said)
        }
        for job in progress.shownJobs {
            let row = NSMenuItem(title: job.name, action: job.url == nil ? nil : #selector(open(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = job.url
            row.image = Self.symbol(job.state.symbol)
            menu.addItem(row)
            for step in job.steps {
                let line = NSMenuItem(title: step.name, action: nil, keyEquivalent: "")
                line.isEnabled = false
                line.indentationLevel = 1
                line.image = Self.symbol(step.state.symbol)
                menu.addItem(line)
            }
        }
        let open = NSMenuItem(title: "Open on GitHub", action: #selector(open(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = progress.run.url
        menu.addItem(open)
        let stop = NSMenuItem(title: "Cancel Run", action: #selector(cancelRun(_:)), keyEquivalent: "")
        stop.target = self
        stop.tag = progress.run.id
        menu.addItem(stop)
    }

    @objc private func open(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { openURL(url) }
    }

    @objc private func cancelRun(_ sender: NSMenuItem) {
        cancel?(sender.tag)
    }

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        image?.isTemplate = true
        return image
    }
}
