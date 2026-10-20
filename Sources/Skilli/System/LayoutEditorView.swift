import AppKit
import SkilliCore
import SwiftUI
import UniformTypeIdentifiers

/// The layout editor: the displays drawn with every window kept (drag to
/// move, a corner to resize; they stick to halves, thirds and quarters, ⌥
/// places freely), the apps and windows to keep or leave out, the name.
struct LayoutEditorView: View {
    @Bindable var draft: LayoutDraft
    let arranger: WindowArranger
    let save: () -> Void
    let cancel: () -> Void
    let tryIt: () -> Void
    /// Left out of every layout from now on (true) or not any more.
    let alwaysIgnore: (String, Bool) -> Void
    @FocusState private var naming: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    placeBar
                    LayoutCanvas(draft: draft)
                        .padding(12)
                }
                .frame(minWidth: 560)
                Divider()
                LayoutWindowList(draft: draft, alwaysIgnore: alwaysIgnore)
                    .frame(width: 320)
            }
            Divider()
            footer
        }
        .frame(minWidth: 900, minHeight: 560)
        // A new layout: the name to type first.
        .onAppear { naming = draft.name.isEmpty }
    }

    /// The selected window's quick places, or how to use the canvas.
    private var placeBar: some View {
        HStack(spacing: 6) {
            if let id = draft.selection, let item = draft.item(id) {
                Text(item.window.title.isEmpty ? item.window.appName : item.window.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .leading)
                ForEach(Self.places, id: \.self) { place in
                    Button { draft.place(id, place) } label: { Image(systemName: place.symbol) }
                        .buttonStyle(.borderless)
                        .help(place.title)
                }
                if draft.displays.count > 1 {
                    Menu {
                        ForEach(draft.displays.indices, id: \.self) { index in
                            Button(draft.displays[index].fingerprint.name) { draft.send(id, to: index) }
                                .disabled(item.window.display == index)
                        }
                    } label: {
                        Image(systemName: "display.2")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Move to another display")
                }
                Spacer()
            } else {
                Text(draft.items.isEmpty
                     ? "Add an app on the right: its window takes a free half of the display, then drag it where you want."
                     : "Drag a window to move it, a corner to resize it. It sticks to halves, thirds and quarters; hold ⌥ to place it freely.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    /// Another saved layout with the name typed: saving replaces it.
    private var overwritten: SavedWindowLayout? {
        _ = arranger.revision
        return draft.overwrites(among: arranger.layouts())
    }

    private static let places: [WindowLayout] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf, .leftThird, .centerThird, .rightThird,
        .topLeft, .topRight, .bottomLeft, .bottomRight, .maximize, .center
    ]

    private var footer: some View {
        HStack(spacing: 10) {
            TextField("Name", text: $draft.name, prompt: Text("Name, like “Coding”"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .focused($naming)
                .onSubmit(save)
            if let other = overwritten {
                Text("Replaces “\(other.name)”")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text("\(draft.includedCount) of \(draft.items.count) windows")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("Clear") { draft.clear() }
                .help("Every window out: start from an empty layout and add apps")
                .disabled(draft.items.isEmpty)
            Button("Revert") { draft.revert() }
                .help("Every window as it was taken")
            Button("Try It", action: tryIt)
                .help("Puts the windows there now, without saving")
                .disabled(draft.includedCount == 0)
            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
            Button("Save", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Canvas

/// The displays where they sit, each window kept drawn on them.
struct LayoutCanvas: View {
    @Bindable var draft: LayoutDraft

    var body: some View {
        GeometryReader { proxy in
            let map = LayoutCanvasMap(displays: draft.displays.map(\.frame), size: proxy.size, padding: 8)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { draft.selection = nil }
                ForEach(draft.displays.indices, id: \.self) { index in
                    DisplayTile(display: draft.displays[index], connected: draft.connected.contains(index), map: map)
                }
                ForEach(drawn) { item in
                    WindowTile(draft: draft, item: item, map: map, selected: draft.selection == item.id)
                }
            }
        }
    }

    /// Kept windows, the front one last, the selected one on top.
    private var drawn: [LayoutDraft.Item] {
        let kept = draft.items.filter(\.included).reversed()
        return kept.filter { $0.id != draft.selection } + kept.filter { $0.id == draft.selection }
    }
}

/// A display: its usable area, its menu bar, its name and how surely it is
/// known.
private struct DisplayTile: View {
    let display: LayoutDisplay
    let connected: Bool
    let map: LayoutCanvasMap

    var body: some View {
        let rect = map.canvas(display.frame)
        let menuBar = max(display.visible.minY - display.frame.minY, 0) * map.scale
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(connected ? 1 : 0.4))
                .strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: connected ? [] : [4, 3]))
            VStack(spacing: 0) {
                Rectangle().fill(.secondary.opacity(0.18)).frame(height: menuBar)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 4) {
                Image(systemName: display.fingerprint.certainty == .unit ? "checkmark.seal" : "seal")
                    .help(display.fingerprint.certainty == .unit
                          ? "Known by its own serial number"
                          : "Known by its model only: it gives no serial number of its own")
                Text("\(display.fingerprint.name) · \(Int(display.frame.width))×\(Int(display.frame.height))\(connected ? "" : " · not connected")")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
    }
}

/// A window on the canvas: drag to move, a corner to resize.
private struct WindowTile: View {
    @Bindable var draft: LayoutDraft
    let item: LayoutDraft.Item
    let map: LayoutCanvasMap
    let selected: Bool
    /// Its frame when the drag began.
    @State private var start: CGRect?

    /// Never smaller than this, in screen points.
    private static let minimum = CGSize(width: 160, height: 100)

    var body: some View {
        let frame = shownFrame
        let rect = map.canvas(frame)
        let tint = Self.tint(item.window.bundleID)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(tint.opacity(selected ? 0.5 : 0.3))
                .strokeBorder(tint.opacity(selected ? 1 : 0.7),
                              style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: item.window.state == .minimized ? [4, 3] : []))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(nsImage: draft.icon(item.window.bundleID))
                        .resizable()
                        .frame(width: 14, height: 14)
                    Text(item.window.appName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                if !item.window.title.isEmpty, rect.height > 34 {
                    Text(item.window.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let opens = item.window.opens, rect.height > 48 {
                    Label("Opened with the layout", systemImage: LayoutOpening.kind(of: opens) == .link ? "link" : "doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let badge = Self.badge(item.window.state), rect.height > 48 {
                    Label(badge.0, systemImage: badge.1)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(5)
            if selected, item.window.state != .fullScreen {
                ForEach(Self.corners, id: \.rawValue) { corner in
                    handle(corner, in: rect)
                }
            }
        }
        .frame(width: max(rect.width, 8), height: max(rect.height, 8))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .position(x: rect.midX, y: rect.midY)
        .opacity(item.window.state == .minimized ? 0.7 : 1)
        .onTapGesture { draft.selection = item.id }
        .gesture(move, including: item.window.state == .fullScreen ? .none : .all)
        .help(item.window.title.isEmpty ? item.window.appName : "\(item.window.appName) — \(item.window.title)")
    }

    /// A full-screen window fills its display.
    private var shownFrame: CGRect {
        guard item.window.state == .fullScreen, let display = item.window.display, draft.displays.indices.contains(display) else {
            return item.window.frame
        }
        return draft.displays[display].frame
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = start ?? item.window.frame
                self.start = start
                draft.selection = item.id
                let delta = map.screen(value.translation)
                var frame = start.offsetBy(dx: delta.width, dy: delta.height)
                if !NSEvent.modifierFlags.contains(.option), let visible = visible(at: CGPoint(x: frame.midX, y: frame.midY)) {
                    frame = LayoutSnap.move(frame, in: visible, tolerance: 10 / map.scale, gap: draft.gap)
                }
                draft.move(item.id, to: frame)
            }
            .onEnded { _ in start = nil }
    }

    private static let corners: [LayoutSnap.Edges] = [[.left, .top], [.right, .top], [.left, .bottom], [.right, .bottom]]

    private func handle(_ edges: LayoutSnap.Edges, in rect: CGRect) -> some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(.secondary, lineWidth: 1))
            .frame(width: 10, height: 10)
            .position(x: edges.contains(.left) ? 5 : rect.width - 5, y: edges.contains(.top) ? 5 : rect.height - 5)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = start ?? item.window.frame
                        self.start = start
                        var frame = LayoutSnap.resized(start, by: map.screen(value.translation), edges: edges, minimum: Self.minimum)
                        if !NSEvent.modifierFlags.contains(.option), let visible = visible(at: CGPoint(x: start.midX, y: start.midY)) {
                            frame = LayoutSnap.resize(frame, edges: edges, in: visible, tolerance: 10 / map.scale, minimum: Self.minimum,
                                                      gap: draft.gap)
                        }
                        draft.move(item.id, to: frame)
                    }
                    .onEnded { _ in start = nil }
            )
    }

    /// The usable area of the display under `point`.
    private func visible(at point: CGPoint) -> CGRect? {
        draft.displays.first { $0.frame.contains(point) }?.visible
    }

    private static func badge(_ state: SavedWindowLayout.Window.State) -> (String, String)? {
        switch state {
        case .normal: nil
        case .minimized: ("In the Dock", "dock.rectangle")
        case .fullScreen: ("Full screen", "arrow.up.left.and.arrow.down.right")
        }
    }

    /// One color per app, the same every time.
    static func tint(_ bundleID: String) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .mint, .cyan, .brown, .red, .yellow]
        let sum = bundleID.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
    }
}

// MARK: - List

/// The apps and their windows: kept or left out, their state, hidden.
private struct LayoutWindowList: View {
    @Bindable var draft: LayoutDraft
    let alwaysIgnore: (String, Bool) -> Void

    var body: some View {
        List(selection: $draft.selection) {
            if !draft.pluggable.isEmpty {
                Section {
                    Picker("When plugged in", selection: $draft.automatic) {
                        Text("Ask").tag(SavedWindowLayout.Automatic.ask)
                        Text("Apply Without Asking").tag(SavedWindowLayout.Automatic.always)
                        Text("Never").tag(SavedWindowLayout.Automatic.never)
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text("\(draft.pluggable.joined(separator: ", ")): " + (draft.automatic == .always
                         ? "put back at once when the display is surely this one (its serial number); asked otherwise."
                         : draft.automatic == .ask
                         ? "skil.li asks in the middle of the display."
                         : "never on its own."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                addApp
                if draft.items.isEmpty {
                    Text("No windows yet. Each app added gets a window on the display, to move and resize.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            LayoutOpeningsSection(draft: draft)
            ForEach(draft.apps, id: \.bundleID) { app in
                Section {
                    ForEach(app.items) { item in
                        row(item).tag(item.id)
                            .contextMenu {
                                Button("Remove from the Layout") { draft.remove(item.id) }
                            }
                    }
                } header: {
                    header(app.bundleID, app.name, app.items)
                }
            }
        }
        .listStyle(.sidebar)
        // ⌫ removes the selected window from the layout.
        .onDeleteCommand {
            if let id = draft.selection { draft.remove(id) }
        }
    }

    /// The apps open now, then any app: a window of it added to the layout.
    private var addApp: some View {
        Menu {
            ForEach(Self.runningApps(), id: \.bundleID) { app in
                Button {
                    draft.add(app: app.bundleID, name: app.name)
                } label: {
                    Label { Text(app.name) } icon: { Image(nsImage: draft.icon(app.bundleID)) }
                }
            }
            Divider()
            Button("Other App…") { chooseApp() }
        } label: {
            Label("Add App", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// The apps with a Dock icon running now (skil.li aside), by name.
    private static func runningApps() -> [(bundleID: String, name: String)] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .compactMap { app -> (bundleID: String, name: String)? in
                guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Any app installed, from the Applications folder.
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        draft.add(app: bundleID, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
    }

    private func header(_ bundleID: String, _ name: String, _ items: [LayoutDraft.Item]) -> some View {
        let kept = items.filter(\.included).count
        let ignored = draft.alwaysIgnored.contains(bundleID)
        return HStack(spacing: 6) {
            Button {
                draft.setIncluded(app: bundleID, kept < items.count)
            } label: {
                Image(systemName: kept == items.count ? "checkmark.square.fill" : kept == 0 ? "square" : "minus.square.fill")
                    .foregroundStyle(kept == 0 ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(kept < items.count ? "Keep every window of \(name)" : "Leave \(name) out")
            Image(nsImage: draft.icon(bundleID))
                .resizable()
                .frame(width: 16, height: 16)
            Text(name)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
            if ignored {
                Text("always left out")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if draft.hiddenApps.contains(bundleID) {
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Hidden (⌘H) once in place")
            }
            Spacer()
            Menu {
                Button("Add Another Window") { draft.add(app: bundleID, name: name) }
                Divider()
                Toggle("Hide Once in Place", isOn: Binding(
                    get: { draft.hiddenApps.contains(bundleID) },
                    set: { if $0 { draft.hiddenApps.insert(bundleID) } else { draft.hiddenApps.remove(bundleID) } }
                ))
                Divider()
                if ignored {
                    Button("Stop Leaving \(name) Out") { alwaysIgnore(bundleID, false) }
                } else {
                    Button("Always Leave \(name) Out") { alwaysIgnore(bundleID, true) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .textCase(nil)
    }

    private func row(_ item: LayoutDraft.Item) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(get: { draft.item(item.id)?.included ?? false }, set: { draft.setIncluded(item.id, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            Text(item.window.title.isEmpty ? "Window \(item.window.index + 1)" : item.window.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(item.included ? .primary : .secondary)
            Spacer()
            Picker("", selection: Binding(get: { draft.item(item.id)?.window.state ?? .normal }, set: { draft.setState(item.id, $0) })) {
                Label("Open", systemImage: "macwindow").tag(SavedWindowLayout.Window.State.normal)
                Label("In the Dock", systemImage: "dock.rectangle").tag(SavedWindowLayout.Window.State.minimized)
                Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right").tag(SavedWindowLayout.Window.State.fullScreen)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(!item.included)
        }
    }
}

// MARK: - What the layout opens

/// The files, folders and links the layout opens when it is applied: each
/// a window on the canvas, to drag where it goes. + adds (a file or a
/// folder from the Finder's panel, a link typed), − takes one out.
private struct LayoutOpeningsSection: View {
    @Bindable var draft: LayoutDraft
    @State private var typingLink = false
    @State private var link = ""

    var body: some View {
        Section {
            ForEach(draft.openings) { item in
                row(item).tag(item.id)
            }
            if draft.openings.isEmpty {
                Text("Files, folders and links opened with the layout, each in the place you give its window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Menu {
                Button("File or Folder…") { chooseFiles() }
                Button("Link…") {
                    link = ""
                    typingLink = true
                }
            } label: {
                Label("Add File, Folder or Link", systemImage: "plus.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .popover(isPresented: $typingLink, arrowEdge: .bottom) { linkField }
        } header: {
            Text("Opens when applied")
        } footer: {
            Text("Opened when the layout is put back, unless a window shows it already; the window it opens in takes its place.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ item: LayoutDraft.Item) -> some View {
        let opens = item.window.opens ?? ""
        return HStack(spacing: 8) {
            Image(nsImage: icon(opens, app: item.window.bundleID))
                .resizable()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(LayoutOpening.name(of: opens))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("in \(item.window.appName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                draft.remove(item.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Do not open it with this layout")
            .accessibilityLabel("Remove")
        }
        .help(opens)
    }

    /// Typed in its own popover: Return adds the link there, never saves
    /// the layout.
    private var linkField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A link the layout opens")
                .font(.headline)
            TextField("Link", text: $link, prompt: Text("github.com/nomdelasociete"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(addLink)
            HStack {
                Text(LayoutOpening.link(link) == nil && !link.isEmpty ? "A web address: https://…" : " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { typingLink = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: addLink)
                    .keyboardShortcut(.defaultAction)
                    .disabled(LayoutOpening.link(link) == nil)
            }
        }
        .padding(14)
    }

    private func addLink() {
        guard let url = LayoutOpening.link(link) else { return }
        add(url)
        typingLink = false
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Files and folders the layout opens when it is put back."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let folder = values?.isDirectory == true && values?.isPackage != true
            add(URL(fileURLWithPath: url.path, isDirectory: folder))
        }
    }

    /// In the app that opens it now (the default browser for a link, the
    /// Finder for a folder).
    private func add(_ url: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url), let bundleID = Bundle(url: app)?.bundleIdentifier else {
            NSSound.beep()
            return
        }
        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        draft.add(opening: url.absoluteString, appID: bundleID, appName: name)
    }

    private func icon(_ opens: String, app bundleID: String) -> NSImage {
        if let url = URL(string: opens), url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return draft.icon(bundleID)
    }
}
