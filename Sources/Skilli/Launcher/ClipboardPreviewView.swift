import AppKit
import ImageIO
import QuickLookThumbnailing
import SkilliCore
import UniformTypeIdentifiers

/// The clipboard history's right side: a view made for each kind of copy
/// (`CopiedValue`): a link's social card, a color's swatch and values, an
/// image with what SI saw and the words in it, a file's Quick Look
/// thumbnail, an address, a phone number or an email address on a card,
/// code in a monospaced face, then what is known about it. Fixed frames
/// like the rest of the launcher: showing a row costs no layout pass, and
/// nothing on that path reads a file or the network: pictures, file
/// details and link previews fill in from other threads.
@MainActor
final class ClipboardPreviewView: NSView {
    /// What the pane shows (self-test hook).
    enum Shown: String {
        case none, text, code, link, color, email, phone, address, image, file, files
    }

    /// Link previews (Settings → Clipboard → Show link previews).
    var links: ClipboardLinks?

    private let divider = HairlineView()
    private let tile = SoftTile()
    private let textScroll = NSScrollView()
    private let textView = NSTextView()
    private let textFade = CAGradientLayer()
    /// A code copy's language, atop its tile.
    private let language = NSTextField(labelWithString: "")
    private let languageLine = HairlineView()
    private let imageView = NSImageView()
    private let fileName = NSTextField(wrappingLabelWithString: "")
    private let placeholder = NSImageView()
    private let swatch = ColorSwatchView()
    private let linkCard = LinkCardView()
    private let valueCard = ValueCardView()
    private let fileList = FileListView()
    private let readingIcon = NSImageView()
    private let reading = SIRevealLabel(wrappingLabelWithString: "")
    private let ocrHeader = NSTextField(labelWithString: "Text in Image")
    private let ocrText = NSTextField(wrappingLabelWithString: "")
    private let infoHeader = NSTextField(labelWithString: "Information")
    private let infoLine = HairlineView()
    private var rows: [(label: NSTextField, value: NSTextField)] = []

    private var item: ClipboardStore.Item?
    private var imageURL: URL?
    /// Bumped by each `show`: what comes back late for another copy is dropped.
    private var token = 0
    private var linkTask: Task<Void, Never>?
    private var values: [Int64: CopiedValue] = [:]
    private var pictures = PictureCache()

    /// Self-test hooks: what is shown, and how long showing it took.
    private(set) var shown: Shown = .none
    private(set) var shownInfo: [(String, String)] = []
    /// A link's or a value's title, as the card shows it.
    var shownTitle: String { shown == .link ? linkCard.shownTitle : shown == .file ? fileName.stringValue : valueCard.shownTitle }
    var shownLinkHasPicture: Bool { linkCard.hasPicture }
    var shownLinkHasIcon: Bool { linkCard.hasIcon }
    private(set) var shownReading = ""
    private(set) var shownTextInImage = ""
    private(set) var hasPicture = false
    private(set) var lastShowTime: Duration = .zero
    /// Where that time went ("value 1.2 ms · views 0.4 ms").
    private(set) var lastShowSteps = ""
    private var laps = Laps()
    /// The kind of the copy shown, as the history keeps it.
    var shownKind: ClipboardStore.Item.Kind? { item?.kind }

    private static let rowHeight: CGFloat = 21
    private static let maxRows = 7

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(divider)
        addSubview(tile)

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textScroll.documentView = textView
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = false
        textScroll.hasHorizontalScroller = false
        // A long text fades out at the bottom instead of being cut through a line.
        textScroll.wantsLayer = true
        textFade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        textScroll.layer?.mask = textFade
        tile.addSubview(textScroll)
        language.font = Theme.Font.sectionHeader
        language.textColor = .secondaryLabelColor
        tile.addSubview(language)
        tile.addSubview(languageLine)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        tile.addSubview(imageView)
        fileName.font = .systemFont(ofSize: 13, weight: .medium)
        fileName.alignment = .center
        fileName.maximumNumberOfLines = 2
        fileName.lineBreakMode = .byTruncatingMiddle
        fileName.cell?.truncatesLastVisibleLine = true
        tile.addSubview(fileName)
        tile.addSubview(fileList)

        placeholder.image = Theme.symbol("doc.on.clipboard", pointSize: 34, weight: .light)
        placeholder.contentTintColor = .tertiaryLabelColor
        tile.addSubview(placeholder)
        addSubview(swatch)
        addSubview(linkCard)
        tile.addSubview(valueCard)

        readingIcon.image = Theme.symbol("sparkles", pointSize: 12, weight: .medium)
        readingIcon.contentTintColor = .controlAccentColor
        addSubview(readingIcon)
        reading.font = .systemFont(ofSize: 12, weight: .regular)
        reading.textColor = .labelColor
        reading.maximumNumberOfLines = 2
        reading.cell?.truncatesLastVisibleLine = true
        addSubview(reading)
        ocrHeader.font = Theme.Font.sectionHeader
        ocrHeader.textColor = .secondaryLabelColor
        addSubview(ocrHeader)
        ocrText.font = .systemFont(ofSize: 12)
        ocrText.textColor = .labelColor
        ocrText.maximumNumberOfLines = 3
        ocrText.lineBreakMode = .byTruncatingTail
        ocrText.cell?.truncatesLastVisibleLine = true
        addSubview(ocrText)

        infoHeader.font = Theme.Font.sectionHeader
        infoHeader.textColor = .secondaryLabelColor
        addSubview(infoHeader)
        addSubview(infoLine)
        for _ in 0..<Self.maxRows {
            let label = NSTextField(labelWithString: "")
            label.font = Theme.Font.rowAccessory
            label.textColor = .secondaryLabelColor
            let value = NSTextField(labelWithString: "")
            value.font = Theme.Font.rowAccessory
            value.textColor = .labelColor
            value.alignment = .right
            value.lineBreakMode = .byTruncatingMiddle
            addSubview(label)
            addSubview(value)
            rows.append((label, value))
        }
        show(nil, imageURL: nil)
    }

    private var warmed = false

    /// The history opens: Apple's detectors take a few ms the first time,
    /// so they are used once off the main thread now, not on a row shown
    /// (and not at launch: they would weigh on skil.li idle).
    func prepare() {
        guard !warmed else { return }
        warmed = true
        Task.detached(priority: .userInitiated) { CopiedValue.warmUp() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let inset: CGFloat = 16
        let width = bounds.width - inset - 20
        divider.frame = NSRect(x: 0, y: 12, width: 1, height: bounds.height - 24)

        // From the bottom: the information, then what an image adds.
        var y: CGFloat = 8
        let shownRows = rows.filter { !$0.label.stringValue.isEmpty }
        for row in shownRows.reversed() {
            row.label.frame = NSRect(x: inset, y: y, width: 120, height: 16)
            row.value.frame = NSRect(x: inset + 112, y: y, width: width - 112, height: 16)
            y += Self.rowHeight
        }
        for row in rows where row.label.stringValue.isEmpty {
            row.label.frame = .zero
            row.value.frame = .zero
        }
        if !shownRows.isEmpty {
            infoLine.frame = NSRect(x: inset, y: y + 1, width: width, height: 1)
            infoHeader.frame = NSRect(x: inset, y: y + 8, width: width, height: 14)
            y = infoHeader.frame.maxY + 14
        }
        if !ocrText.isHidden {
            let height = min(ocrText.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 200)).height ?? 15, 47)
            ocrText.frame = NSRect(x: inset, y: y, width: width, height: height)
            ocrHeader.frame = NSRect(x: inset, y: ocrText.frame.maxY + 4, width: width, height: 14)
            y = ocrHeader.frame.maxY + 14
        }
        if !reading.isHidden {
            let height = min(reading.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width - 20, height: 100)).height ?? 15, 32)
            reading.frame = NSRect(x: inset + 20, y: y, width: width - 20, height: height)
            readingIcon.frame = NSRect(x: inset, y: reading.frame.maxY - 15, width: 14, height: 14)
            y = reading.frame.maxY + 12
        }

        let hero = NSRect(x: inset, y: y, width: width, height: max(80, bounds.height - 12 - y))
        tile.frame = hero
        swatch.frame = hero
        linkCard.frame = hero
        let inner = tile.bounds
        // Code in a language: its name on a line of its own atop the code.
        let header: CGFloat = language.isHidden ? 0 : 30
        language.frame = NSRect(x: 14, y: inner.maxY - 22, width: inner.width - 28, height: 14)
        languageLine.frame = NSRect(x: 0, y: inner.maxY - header, width: inner.width, height: 1)
        textScroll.frame = NSRect(x: 0, y: 0, width: inner.width, height: inner.height - header)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textFade.frame = textScroll.bounds
        // From the top down: solid, then clear over the last 30 pt. The
        // scroll view is flipped: its layer's top is y 0.
        let fade = min(0.5, 30 / max(textScroll.bounds.height, 1))
        let top: CGFloat = textScroll.isFlipped ? 0 : 1
        textFade.locations = [0, NSNumber(value: 1 - fade), 1]
        textFade.startPoint = CGPoint(x: 0.5, y: top)
        textFade.endPoint = CGPoint(x: 0.5, y: 1 - top)
        CATransaction.commit()
        textView.frame = NSRect(origin: .zero, size: NSSize(width: inner.width, height: max(textScroll.frame.height, textView.frame.height)))
        textView.textContainer?.containerSize = NSSize(width: inner.width - 16, height: .greatestFiniteMagnitude)
        placeholder.frame = NSRect(x: inner.midX - 24, y: inner.midY - 24, width: 48, height: 48)
        valueCard.frame = inner
        fileList.frame = inner.insetBy(dx: 12, dy: 10)
        if shown == .file {
            let nameHeight = min(fileName.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner.width - 32, height: 100)).height ?? 16, 34)
            fileName.frame = NSRect(x: 16, y: 12, width: inner.width - 32, height: nameHeight)
            fit(imageView, in: NSRect(x: 12, y: fileName.frame.maxY + 10, width: inner.width - 24, height: inner.height - fileName.frame.maxY - 22))
        } else {
            fit(imageView, in: inner.insetBy(dx: 10, dy: 10))
        }
    }

    /// The picture fitted in `area`, never past its own size.
    private func fit(_ view: NSImageView, in area: NSRect) {
        guard let image = view.image, image.size.width > 0, image.size.height > 0, area.width > 0, area.height > 0 else { return }
        let scale = min(area.width / image.size.width, area.height / image.size.height, 1)
        let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        view.frame = NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: - Showing

    /// Shows `item`, or a quiet tile when there is none.
    func show(_ item: ClipboardStore.Item?, imageURL: URL?) {
        let start = ContinuousClock.now
        laps = Laps()
        defer {
            lastShowTime = ContinuousClock.now - start
            lastShowSteps = laps.steps.map { "\($0.name) \($0.took.compact)" }.joined(separator: " · ")
        }
        token += 1
        linkTask?.cancel()
        linkTask = nil
        self.item = item
        self.imageURL = imageURL
        hasPicture = false
        shownReading = ""
        shownTextInImage = ""
        for view in [textScroll, language, languageLine, imageView, fileName, fileList, placeholder, swatch, linkCard, valueCard,
                     readingIcon, reading, ocrHeader, ocrText] as [NSView] {
            view.isHidden = true
        }
        tile.isHidden = false
        imageView.image = nil
        imageView.contentTintColor = nil
        laps.lap("reset")
        var info: [(String, String)] = []
        guard let item else {
            shown = .none
            placeholder.isHidden = false
            setInfo([])
            return
        }
        switch item.kind {
        case .text:
            info = showText(item)
        case .image:
            info = showImage(item)
        case .files:
            info = showFiles(item)
        }
        laps.lap("kind")
        info.append(("Copied", Self.copied.string(from: item.copiedAt)))
        if item.copies > 1 { info.append(("Times copied", "\(item.copies)")) }
        setInfo(info)
        laps.lap("information")
    }

    /// The history closed: nothing shown, its decoded pictures let go
    /// (the launcher's memory budget).
    func release() {
        show(nil, imageURL: nil)
        pictures = PictureCache()
    }

    private func setInfo(_ info: [(String, String)]) {
        let info = Array(info.prefix(Self.maxRows))
        shownInfo = info
        infoHeader.isHidden = info.isEmpty
        infoLine.isHidden = info.isEmpty
        for (index, row) in rows.enumerated() {
            let pair = index < info.count ? info[index] : nil
            row.label.stringValue = pair?.0 ?? ""
            row.value.stringValue = pair?.1 ?? ""
        }
        needsLayout = true
    }

    /// One row of the information, filled in after it was shown.
    private func update(_ label: String, _ value: String) {
        if let index = shownInfo.firstIndex(where: { $0.0 == label }) {
            shownInfo[index].1 = value
            rows[index].value.stringValue = value
        }
    }

    private func value(of item: ClipboardStore.Item) -> CopiedValue {
        if let known = values[item.id] { return known }
        let value = CopiedValue.read(item.text)
        if values.count > 400 { values.removeAll() }
        values[item.id] = value
        return value
    }

    // MARK: Text

    private func showText(_ item: ClipboardStore.Item) -> [(String, String)] {
        let app = ("Application", item.appName ?? "Unknown")
        let value = value(of: item)
        laps.lap("value")
        switch value {
        case .link(let url):
            shown = .link
            tile.isHidden = true
            linkCard.isHidden = false
            showLink(item, url: url)
            return [app, ("Link", url.absoluteString)]
        case .color(let color):
            shown = .color
            tile.isHidden = true
            swatch.isHidden = false
            swatch.color = color
            var info = [("Hex", color.hex), ("RGB", color.rgb), ("HSL", color.hsl)]
            if color.alpha < 1 { info.append(("Opacity", color.opacity)) }
            return info + [app]
        case .email(let address):
            shown = .email
            valueCard.isHidden = false
            valueCard.show(symbol: "envelope.fill", tint: .systemBlue, title: address, caption: "Email address")
            return [app, ("Content", "Email address")]
        case .phone(let number):
            shown = .phone
            valueCard.isHidden = false
            valueCard.show(symbol: "phone.fill", tint: .systemGreen, title: number, caption: "Phone number")
            return [app, ("Content", "Phone number")]
        case .address(let address):
            shown = .address
            valueCard.isHidden = false
            valueCard.show(symbol: "mappin.and.ellipse", tint: .systemRed, title: address.lines.joined(separator: "\n"),
                           caption: address.country.map { "Address · \($0)" } ?? "Address", lines: 4)
            return [app, ("Content", "Address")]
        case .code(let language):
            shown = .code
            showPlain(item.text, code: true)
            self.language.isHidden = language == nil
            languageLine.isHidden = language == nil
            self.language.stringValue = language ?? ""
            let lines = item.text.split(whereSeparator: \.isNewline).count
            return [app, ("Content", language.map { "Code · \($0)" } ?? "Code"),
                    ("Size", "\(Self.count(lines, "line")) · \(Self.count(item.text.count, "character"))")]
        case .text:
            shown = .text
            showPlain(item.text, code: false)
            let words = item.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let lines = item.text.split(whereSeparator: \.isNewline).count
            var size = "\(Self.count(words, "word")) · \(Self.count(item.text.count, "character"))"
            if lines > 1 { size += " · \(Self.count(lines, "line"))" }
            var info = [app, ("Content", "Text"), ("Size", size)]
            // A long read says how long (238 words a minute).
            if words >= 400 { info.append(("Reading time", "About \(max(1, Int((Double(words) / 238).rounded()))) min")) }
            return info
        }
    }

    private func showPlain(_ text: String, code: Bool) {
        let shown = text.utf16.count > 4_000 ? String(text.prefix(4_000)) + "…" : text
        textView.font = code ? .monospacedSystemFont(ofSize: 11.5, weight: .regular) : .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.string = shown
        textView.scroll(.zero)
        textScroll.isHidden = false
    }

    // MARK: Link

    /// What is known at once (the link and its domain, or the preview kept
    /// in memory); the page read when due, after a short pause so arrows
    /// flying over links read none of them.
    private func showLink(_ item: ClipboardStore.Item, url: URL) {
        let on = links != nil && (links?.isOn() ?? false)
        let known = on ? links?.known(item.id) : nil
        applyLink(item.id, url: url, record: known)
        guard on, let links else { return }
        let id = item.id
        let token = self.token
        linkTask = Task { [weak self] in
            var record = known
            if record == nil {
                record = await links.preview(for: id, url: url, fetching: false)
                guard let self, self.token == token, !Task.isCancelled else { return }
                if record != nil { self.applyLink(id, url: url, record: record) }
            }
            guard LinkPreviewCache.needsFetch(record, for: url, now: .now) else { return }
            try? await Task.sleep(for: .milliseconds(160))
            guard let current = self, current.token == token, !Task.isCancelled else { return }
            let fetched = await links.preview(for: id, url: url, fetching: true)
            guard let again = self, again.token == token else { return }
            again.applyLink(id, url: url, record: fetched)
        }
    }

    private func applyLink(_ id: Int64, url: URL, record: LinkPreviewRecord?) {
        let picture = record?.image.flatMap { name in pictures[name + "@\(record?.fetched.timeIntervalSince1970 ?? 0)"] }
        let icon = record?.icon.flatMap { name in pictures[name + "@\(record?.fetched.timeIntervalSince1970 ?? 0)"] }
        linkCard.show(url: url, preview: record?.outcome == .found ? record?.preview : nil, picture: picture, icon: icon)
        // Its picture and icon, decoded off the main thread.
        guard let record, let links, picture == nil && record.image != nil || icon == nil && record.icon != nil else { return }
        let token = self.token
        let stamp = "@\(record.fetched.timeIntervalSince1970)"
        let files = [record.image, record.icon].compactMap(\.self).map { ($0 + stamp, links.fileURL($0)) }
        Task { [weak self] in
            var decoded: [(String, NSImage)] = []
            for (key, url) in files {
                guard let url, let image = await Self.decode(url, longest: key.contains(".icon.") ? 64 : 800) else { continue }
                decoded.append((key, image))
            }
            guard let self else { return }
            for (key, image) in decoded { self.pictures[key] = image }
            guard self.token == token else { return }
            self.linkCard.show(url: url, preview: record.outcome == .found ? record.preview : nil,
                               picture: record.image.flatMap { self.pictures[$0 + stamp] },
                               icon: record.icon.flatMap { self.pictures[$0 + stamp] })
        }
    }

    // MARK: Image

    private func showImage(_ item: ClipboardStore.Item) -> [(String, String)] {
        shown = .image
        let key = "image:\(item.id)"
        if let cached = pictures[key] {
            imageView.image = cached
            imageView.isHidden = false
            hasPicture = true
        }
        if let tags = item.tags.flatMap(ImageTags.init(words:)), let sentence = tags.sentence {
            reading.text = sentence
            reading.isHidden = false
            readingIcon.isHidden = false
            shownReading = sentence
        }
        if let text = item.ocr?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            ocrText.stringValue = text
            ocrText.isHidden = false
            ocrHeader.isHidden = false
            shownTextInImage = text
        }
        let tags = item.tags.flatMap(ImageTags.init(words:))
        var info: [(String, String)] = [("Content", tags.map { $0.kind.title + ($0.person ? ", with a person" : "") } ?? "Image")]
        if let size = item.size {
            info.append(("Dimensions", size.replacingOccurrences(of: "×", with: " × ") + " pixels"))
        }
        info.append(("File size", "…"))
        info.append(("From", item.app == nil ? item.appName.map { "\($0) (folder)" } ?? "A folder" : item.appName ?? "Unknown"))
        guard let url = imageURL else { return info }
        let token = self.token
        let needsPicture = pictures[key] == nil
        Task { [weak self] in
            let (picture, bytes) = await Task.detached(priority: .userInitiated) { () -> (NSImage?, Int?) in
                let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                return (needsPicture ? Self.thumbnail(url) : nil, bytes)
            }.value
            guard let self else { return }
            if let picture { self.pictures[key] = picture }
            guard self.token == token else { return }
            self.update("File size", bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "Unknown")
            if let picture {
                self.imageView.image = picture
                self.imageView.isHidden = false
                self.hasPicture = true
                self.needsLayout = true
            }
        }
        return info
    }

    // MARK: Files

    private func showFiles(_ item: ClipboardStore.Item) -> [(String, String)] {
        let paths = item.text.split(separator: "\n").map(String.init)
        let folder = paths.first.map { ($0 as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~") } ?? ""
        guard paths.count == 1, let path = paths.first else {
            shown = .files
            fileList.isHidden = false
            fileList.show(paths)
            return [("Content", "\(paths.count) Files"), ("Where", folder)]
        }
        shown = .file
        let url = URL(fileURLWithPath: path)
        fileName.stringValue = url.lastPathComponent
        fileName.isHidden = false
        let key = "file:\(path)"
        if let cached = pictures[key] {
            imageView.image = cached
            imageView.isHidden = false
            hasPicture = true
        }
        let token = self.token
        let scale = window?.backingScaleFactor ?? 2
        let side = max(tile.bounds.width, 300)
        let needsPicture = pictures[key] == nil
        Task { [weak self] in
            let details = await Task.detached(priority: .userInitiated) { FileDetails.read(url) }.value
            var picture: NSImage?
            if needsPicture, details.exists {
                picture = await Self.quickLook(url, side: side, scale: scale)
            }
            guard let self else { return }
            if let picture { self.pictures[key] = picture }
            guard self.token == token else { return }
            self.update("Kind", details.kind)
            self.update("Size", details.size)
            self.update("Modified", details.modified)
            if let picture {
                self.imageView.image = picture
                self.imageView.isHidden = false
                self.hasPicture = true
                self.needsLayout = true
            } else if !details.exists {
                self.imageView.image = Theme.symbol("questionmark.folder", pointSize: 40, weight: .light)
                self.imageView.contentTintColor = .tertiaryLabelColor
                self.imageView.isHidden = false
                self.needsLayout = true
            }
        }
        return [("Kind", "…"), ("Size", "…"), ("Where", folder), ("Modified", "…")]
    }

    // MARK: - Off the main thread

    /// At most 900 pixels wide: a big screenshot shows at once.
    nonisolated private static func thumbnail(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 900,
                  kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary)
        else { return nil }
        // Points, not pixels: a Retina screenshot shows at its own size.
        return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2))
    }

    /// A kept preview picture or icon.
    nonisolated private static func decode(_ url: URL, longest: Int) async -> NSImage? {
        await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: longest
                  ] as CFDictionary)
            else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2))
        }.value
    }

    /// Quick Look's thumbnail, else the file's icon.
    private static func quickLook(_ url: URL, side: CGFloat, scale: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side * 0.6), scale: scale,
                                                   representationTypes: [.icon, .thumbnail])
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return representation.nsImage
    }

    // MARK: - Words

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value.formatted()) \(noun)\(value == 1 ? "" : "s")"
    }

    /// "Today at 14:32", "Yesterday at 09:10", "3 Oct 2026 at 18:02".
    static let copied: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

/// A few decoded pictures, the last ones shown, by key: going back to a
/// row shows its picture at once. Eight at most (a 900 px picture is
/// ~2 MB), let go when the history closes.
private struct PictureCache {
    private var images: [String: NSImage] = [:]
    private var order: [String] = []

    subscript(key: String) -> NSImage? {
        get { images[key] }
        set {
            guard let newValue else {
                images[key] = nil
                order.removeAll { $0 == key }
                return
            }
            if images[key] == nil { order.append(key) }
            images[key] = newValue
            while order.count > 8 { images[order.removeFirst()] = nil }
        }
    }
}

/// A file's kind, size and date, read off the main thread.
private struct FileDetails: Sendable {
    var exists = false
    var kind = "Unknown"
    var size = "—"
    var modified = "—"

    static func read(_ url: URL) -> FileDetails {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isDirectoryKey, .contentModificationDateKey,
                                                              .isPackageKey]) else {
            return FileDetails(exists: false, kind: "No longer there", size: "—", modified: "—")
        }
        var details = FileDetails(exists: true)
        details.kind = values.contentType?.localizedDescription?.capitalizedFirst ?? (values.isDirectory == true ? "Folder" : "Document")
        if values.isDirectory == true, values.isPackage != true {
            details.size = "Folder"
        } else if let bytes = values.fileSize {
            details.size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        if let date = values.contentModificationDate {
            details.modified = ClipboardPreviewView.formatted(date)
        }
        return details
    }
}

extension ClipboardPreviewView {
    nonisolated static func formatted(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Parts

/// A soft rounded fill that follows the appearance, drawn at draw time.
private final class SoftTile: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
    }
}

/// A copied color, large: the color over a checkerboard when it is not
/// opaque, its hex and RGB written on it in whichever of black or white
/// reads better.
private final class ColorSwatchView: NSView {
    private let hex = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    var color = CopiedColor(red: 0, green: 0, blue: 0) {
        didSet {
            hex.stringValue = color.hex
            detail.stringValue = color.rgb
            let ink: NSColor = color.prefersDarkText || color.alpha < 0.45 ? .black : .white
            hex.textColor = ink.withAlphaComponent(0.88)
            detail.textColor = ink.withAlphaComponent(0.62)
            needsDisplay = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        hex.font = .monospacedSystemFont(ofSize: 20, weight: .semibold)
        detail.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        addSubview(hex)
        addSubview(detail)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        detail.frame = NSRect(x: 16, y: 14, width: bounds.width - 32, height: 16)
        hex.frame = NSRect(x: 16, y: detail.frame.maxY + 2, width: bounds.width - 32, height: 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        if color.alpha < 1 {
            // A checkerboard shows what shows through.
            NSColor.white.setFill()
            bounds.fill()
            NSColor(white: 0.84, alpha: 1).setFill()
            let square: CGFloat = 10
            var row = 0
            var y = bounds.minY
            while y < bounds.maxY {
                var x = bounds.minX + (row % 2 == 0 ? 0 : square)
                while x < bounds.maxX {
                    NSRect(x: x, y: y, width: square, height: square).fill()
                    x += square * 2
                }
                y += square
                row += 1
            }
        }
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha).setFill()
        bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        // A hairline keeps white on light glass and black on dark visible.
        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11.5, yRadius: 11.5)
        edge.lineWidth = 1
        edge.stroke()
    }
}

/// An email address, a phone number or a postal address on a small card:
/// its symbol in a tinted circle, the value, what it is.
private final class ValueCardView: NSView {
    private let badge = BadgeView()
    private let title = NSTextField(wrappingLabelWithString: "")
    private let caption = NSTextField(labelWithString: "")
    private(set) var shownTitle = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.alignment = .center
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.cell?.truncatesLastVisibleLine = true
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingTail
        addSubview(badge)
        addSubview(title)
        addSubview(caption)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(symbol: String, tint: NSColor, title text: String, caption detail: String, lines: Int = 2) {
        badge.show(symbol: symbol, tint: tint)
        title.stringValue = text
        title.font = lines > 2 ? .systemFont(ofSize: 15, weight: .semibold) : .systemFont(ofSize: 18, weight: .semibold)
        title.maximumNumberOfLines = lines
        caption.stringValue = detail
        shownTitle = text
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = bounds.width - 40
        let titleHeight = min(title.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 200)).height ?? 22, 96)
        let total: CGFloat = 52 + 14 + titleHeight + 6 + 16
        var y = (bounds.height - total) / 2
        caption.frame = NSRect(x: 20, y: y, width: width, height: 16)
        y += 16 + 6
        title.frame = NSRect(x: 20, y: y, width: width, height: titleHeight)
        y += titleHeight + 14
        badge.frame = NSRect(x: bounds.midX - 26, y: y, width: 52, height: 52)
    }
}

/// A symbol on a soft circle of its tint.
private final class BadgeView: NSView {
    private let symbol = NSImageView()
    private var tint: NSColor = .systemBlue

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(symbol)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static var symbols: [String: NSImage] = [:]

    func show(symbol name: String, tint: NSColor) {
        self.tint = tint
        if Self.symbols[name] == nil { Self.symbols[name] = Theme.symbol(name, pointSize: 22, weight: .medium) }
        symbol.image = Self.symbols[name]
        symbol.contentTintColor = tint
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        symbol.frame = bounds.insetBy(dx: 12, dy: 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        tint.withAlphaComponent(0.16).setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

/// Several files: each one's icon, name and kind, the first ones; how
/// many more. Read from the names only: nothing from the disk.
private final class FileListView: NSView {
    private var lines: [(icon: NSImageView, name: NSTextField, kind: NSTextField)] = []
    private let more = NSTextField(labelWithString: "")
    private static let shown = 6
    private static let rowHeight: CGFloat = 44

    override init(frame: NSRect) {
        super.init(frame: frame)
        for _ in 0..<Self.shown {
            let icon = NSImageView()
            icon.imageScaling = .scaleProportionallyUpOrDown
            let name = NSTextField(labelWithString: "")
            name.font = .systemFont(ofSize: 13, weight: .medium)
            name.lineBreakMode = .byTruncatingMiddle
            let kind = NSTextField(labelWithString: "")
            kind.font = .systemFont(ofSize: 11)
            kind.textColor = .secondaryLabelColor
            kind.lineBreakMode = .byTruncatingTail
            addSubview(icon)
            addSubview(name)
            addSubview(kind)
            lines.append((icon, name, kind))
        }
        more.font = .systemFont(ofSize: 12)
        more.textColor = .secondaryLabelColor
        addSubview(more)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Icons by kind of file, asked of macOS once each.
    private static var icons: [String: NSImage] = [:]

    func show(_ paths: [String]) {
        for (index, line) in lines.enumerated() {
            let path = index < paths.count ? paths[index] : nil
            line.name.stringValue = path.map { ($0 as NSString).lastPathComponent } ?? ""
            let ext = path.map { ($0 as NSString).pathExtension.lowercased() } ?? ""
            let type = ext.isEmpty ? UTType.folder : UTType(filenameExtension: ext) ?? .data
            line.kind.stringValue = path == nil ? "" : type.localizedDescription.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Document"
            line.icon.image = path.map { _ in
                // The kind's icon: nothing read from the file itself.
                if let icon = Self.icons[ext] { return icon }
                let icon = NSWorkspace.shared.icon(for: type)
                Self.icons[ext] = icon
                return icon
            }
        }
        more.stringValue = paths.count > Self.shown ? "and \(paths.count - Self.shown) more" : ""
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var y = bounds.maxY - Self.rowHeight
        for line in lines {
            line.icon.frame = NSRect(x: 0, y: y + 6, width: 32, height: 32)
            line.name.frame = NSRect(x: 44, y: y + 22, width: bounds.width - 44, height: 17)
            line.kind.frame = NSRect(x: 44, y: y + 6, width: bounds.width - 44, height: 15)
            y -= Self.rowHeight
        }
        more.frame = NSRect(x: 44, y: y + 20, width: bounds.width - 44, height: 16)
    }
}
