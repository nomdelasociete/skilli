import AppKit
import ImageIO
import SkilliCore

/// Search GIFs as a grid, four across, built like the emoji picker: it
/// draws the launcher's rows (`LauncherController.results`), the table
/// stays the selection every action reads (↩, ⌘↩, ⌘K). Every tile shows
/// its first frame; only the selected one plays: a grid of moving
/// pictures costs CPU and memory for nothing and reads worse.
final class GIFGridView: NSView {
    static let columns = 4
    private static let inset: CGFloat = 14
    private static let tileHeight: CGFloat = 128
    private static let headerHeight: CGFloat = 30
    /// The stills decoded, by URL: at most this many bytes, gone when the
    /// mode closes (`release`). Klipy's GIFs are never written to disk.
    private static let stillBytes = 16_000_000

    private let scroll = NSScrollView()
    private let collection = GIFCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    private var gifs: [GIF] = []
    private var sections: [EmojiList.Section] = []
    private var starts: [Int] = []
    private(set) var selected = 0
    private let stills = NSCache<NSURL, CGImage>()
    private var loading: [URL: Task<Void, Never>] = [:]
    /// The selected tile's animation, stopped as the selection moves.
    private var player: GIFPlayer?

    var onSelect: ((Int) -> Void)?
    var onOpen: ((Int) -> Void)?
    var onTopSection: ((String?) -> Void)?
    /// Self-test hooks: what plays, and the stills decoded so far.
    private(set) var playingIndex: Int?
    private(set) var stillsLoaded = 0
    /// Frames the playing tile showed since it was selected.
    private(set) var framesShown = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        stills.totalCostLimit = Self.stillBytes
        let width = ((frame.width - 2 * Self.inset) / CGFloat(Self.columns)).rounded(.down)
        layout.itemSize = NSSize(width: width, height: Self.tileHeight)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = NSEdgeInsets(top: 0, left: Self.inset, bottom: 6, right: Self.inset)
        collection.collectionViewLayout = layout
        collection.backgroundColors = [.clear]
        collection.isSelectable = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(GIFGridItem.self, forItemWithIdentifier: GIFGridItem.identifier)
        collection.register(EmojiGridHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                            withIdentifier: EmojiGridHeader.identifier)
        scroll.frame = bounds
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.documentView = collection
        addSubview(scroll)
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
                                               object: scroll.contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows `gifs` under `sections` (their counts adding up to the GIFs),
    /// from the top; the stills come as they load.
    func show(_ gifs: [GIF], sections: [EmojiList.Section]) {
        let same = gifs == self.gifs && sections == self.sections
        self.gifs = gifs
        self.sections = sections.isEmpty || sections.map(\.count).reduce(0, +) != gifs.count
            ? [EmojiList.Section(name: "", count: gifs.count)] : sections
        var start = 0
        starts = self.sections.map { section in
            defer { start += section.count }
            return start
        }
        // The same rows again (a key that changed nothing): no reload, no flash.
        guard !same else { return }
        stopPlaying()
        selected = 0
        collection.reloadData()
        collection.layoutSubtreeIfNeeded()
        collection.scroll(.zero)
        scrolled()
    }

    /// Shows `index` selected and playing, scrolled into sight.
    func select(_ index: Int) {
        guard gifs.indices.contains(index) else {
            stopPlaying()
            return
        }
        let old = selected
        selected = index
        for flat in [old, index] {
            (collection.item(at: path(of: flat)) as? GIFGridItem)?.isChosen = flat == index
        }
        collection.scrollToItems(at: [path(of: index)], scrollPosition: .nearestHorizontalEdge)
        play(index)
    }

    /// Nothing kept once the mode closes: stills, animation, loads.
    func release() {
        stopPlaying()
        for task in loading.values { task.cancel() }
        loading = [:]
        stills.removeAllObjects()
        stillsLoaded = 0
        gifs = []
        sections = []
        starts = []
        collection.reloadData()
    }

    /// The tile `direction` of `index` (rows end early before a section's name).
    func neighbor(of index: Int, _ direction: EmojiGridView.Direction) -> Int? {
        guard gifs.indices.contains(index) else { return nil }
        switch direction {
        case .left: return index > 0 ? index - 1 : nil
        case .right: return index + 1 < gifs.count ? index + 1 : nil
        case .up, .down:
            guard let here = frame(of: index) else { return nil }
            let step = direction == .down ? 1 : -1
            var row: CGFloat?
            var best: (index: Int, distance: CGFloat)?
            var next = index + step
            while gifs.indices.contains(next), let there = frame(of: next) {
                let other = direction == .down ? there.minY > here.midY : there.maxY < here.midY
                if other {
                    if row == nil { row = there.minY }
                    if there.minY != row { break }
                    let distance = abs(there.midX - here.midX)
                    if best == nil || distance < best!.distance { best = (next, distance) }
                }
                next += step
            }
            return best?.index
        }
    }

    /// Self-test hook: where a tile is in the grid.
    func frame(of index: Int) -> NSRect? {
        collection.layoutAttributesForItem(at: path(of: index))?.frame
    }

    /// Self-test hook: the section names shown, in order.
    var sectionNames: [String] { sections.map(\.name).filter { !$0.isEmpty } }

    // MARK: - Stills

    /// The tile's pixels: its size at the screen's scale.
    private var tilePixels: Int {
        Int((max(layout.itemSize.width, Self.tileHeight) * (window?.backingScaleFactor ?? 2)).rounded(.up))
    }

    fileprivate func still(for gif: GIF) -> CGImage? {
        stills.object(forKey: gif.stillURL as NSURL)
    }

    /// Loads a tile's still once; the tile showing it then is told.
    fileprivate func loadStill(_ gif: GIF) {
        let url = gif.stillURL
        guard still(for: gif) == nil, loading[url] == nil else { return }
        let pixels = tilePixels
        loading[url] = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let data = await GIFLibrary.data(url, limit: 8_000_000) else { return nil }
                return GIFLibrary.still(data, pixels: pixels)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.loading[url] = nil
            guard let image else { return }
            self.stills.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
            self.stillsLoaded += 1
            for item in self.collection.visibleItems() {
                guard let tile = item as? GIFGridItem, let shown = tile.gif, shown.stillURL == url else { continue }
                tile.showStill(image)
            }
        }
    }

    // MARK: - Playing

    private func play(_ index: Int) {
        guard playingIndex != index || player == nil else { return }
        stopPlaying()
        playingIndex = index
        framesShown = 0
        let gif = gifs[index]
        let pixels = tilePixels
        player = GIFPlayer(url: gif.playURL, pixels: pixels) { [weak self] frame in
            guard let self, self.playingIndex == index else { return }
            self.framesShown += 1
            (self.collection.item(at: self.path(of: index)) as? GIFGridItem)?.showFrame(frame)
        }
    }

    private func stopPlaying() {
        player?.stop()
        player = nil
        if let index = playingIndex, gifs.indices.contains(index) {
            (collection.item(at: path(of: index)) as? GIFGridItem)?.showFrame(nil)
        }
        playingIndex = nil
    }

    private func path(of index: Int) -> IndexPath {
        let section = (starts.lastIndex { $0 <= index }) ?? 0
        return IndexPath(item: index - (starts.indices.contains(section) ? starts[section] : 0), section: section)
    }

    private func index(of path: IndexPath) -> Int {
        (starts.indices.contains(path.section) ? starts[path.section] : 0) + path.item
    }

    @objc private func scrolled() {
        guard sections.count > 1 else {
            onTopSection?(nil)
            return
        }
        let top = collection.indexPathsForVisibleItems().min() ?? IndexPath(item: 0, section: 0)
        onTopSection?(sections.indices.contains(top.section) ? sections[top.section].name : nil)
    }

    fileprivate func clicked(_ item: GIFGridItem, count: Int) {
        guard let path = collection.indexPath(for: item) else { return }
        let flat = index(of: path)
        onSelect?(flat)
        if count > 1 { onOpen?(flat) }
    }
}

extension GIFGridView: NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        sections.indices.contains(section) ? sections[section].count : 0
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: GIFGridItem.identifier, for: indexPath)
        if let tile = item as? GIFGridItem {
            let flat = index(of: indexPath)
            tile.grid = self
            if gifs.indices.contains(flat) {
                let gif = gifs[flat]
                tile.show(gif, still: still(for: gif))
                if still(for: gif) == nil { loadStill(gif) }
            }
            tile.isChosen = flat == selected
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        let view = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: EmojiGridHeader.identifier, for: indexPath)
        (view as? EmojiGridHeader)?.label.stringValue = sections.indices.contains(indexPath.section) ? sections[indexPath.section].name : ""
        return view
    }

    /// The first section's name is the launcher's header; the others sit
    /// above their rows.
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> NSSize {
        NSSize(width: collectionView.bounds.width, height: section == 0 ? 0 : Self.headerHeight)
    }
}

/// Never takes the keys: the search field keeps them.
private final class GIFCollectionView: NSCollectionView {
    override var acceptsFirstResponder: Bool { false }
}

/// One GIF on a tile: its still, or its frames while selected; the
/// selected tile on the launcher's selection fill.
final class GIFGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("GIFGridItem")
    weak var grid: GIFGridView?
    private(set) var gif: GIF?

    var isChosen = false {
        didSet { (view as? GIFTile)?.isChosen = isChosen }
    }

    override func loadView() {
        let tile = GIFTile()
        tile.item = self
        view = tile
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        gif = nil
        (view as? GIFTile)?.set(still: nil, frame: nil)
    }

    func show(_ gif: GIF, still: CGImage?) {
        self.gif = gif
        (view as? GIFTile)?.set(still: still, frame: nil)
        view.setAccessibilityLabel(gif.title)
    }

    func showStill(_ image: CGImage) {
        (view as? GIFTile)?.set(still: image, frame: nil)
    }

    /// A frame while it plays; nil: back to the still.
    func showFrame(_ frame: CGImage?) {
        (view as? GIFTile)?.showFrame(frame)
    }

    fileprivate func clicked(count: Int) {
        grid?.clicked(self, count: count)
    }
}

/// The picture fills its rounded tile (cropped, never stretched); a soft
/// fill until it loads. Selected: the launcher's soft fill around it and a
/// thin accent line, which a picture's own colours cannot hide (the fill
/// alone vanished around a bright GIF in dark mode).
private final class GIFTile: NSView {
    private static let pad: CGFloat = 5
    private let picture = CALayer()
    private let ring = CALayer()
    private var still: CGImage?
    weak var item: GIFGridItem?
    var isChosen = false {
        didSet { ring.isHidden = !isChosen }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ring.cornerRadius = Theme.Radius.row
        ring.borderWidth = 2
        ring.isHidden = true
        picture.cornerRadius = Theme.Radius.row - Self.pad
        picture.masksToBounds = true
        picture.contentsGravity = .resizeAspectFill
        layer?.addSublayer(ring)
        layer?.addSublayer(picture)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds.insetBy(dx: 2, dy: 2)
        picture.frame = bounds.insetBy(dx: 2 + Self.pad, dy: 2 + Self.pad)
        CATransaction.commit()
    }

    override func updateLayer() {
        super.updateLayer()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ring.backgroundColor = Theme.selectionFill.cgColor
            ring.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            picture.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
    }

    override var wantsUpdateLayer: Bool { true }

    func set(still: CGImage?, frame: CGImage?) {
        self.still = still
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.contents = frame ?? still
        CATransaction.commit()
    }

    func showFrame(_ frame: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.contents = frame ?? still
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        item?.clicked(count: event.clickCount)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
}

/// Plays one animated picture (GIF, WebP, APNG: what ImageIO reads), each
/// frame decoded at the tile's size when it is due: one tile at a time,
/// no frame kept but the one shown.
@MainActor
private final class GIFPlayer {
    private var task: Task<Void, Never>?

    init(url: URL, pixels: Int, show: @escaping @MainActor (CGImage) -> Void) {
        task = Task {
            // A selection flying over the tiles loads nothing.
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let data = await GIFLibrary.data(url, limit: 15_000_000),
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return }
            let count = CGImageSourceGetCount(source)
            guard count > 1 else { return }
            let delays = (0..<count).map { Self.delay(source, $0) }
            let frames = FrameSource(source)
            var index = 0
            while !Task.isCancelled {
                let frameIndex = index
                let frame = await Task.detached(priority: .userInitiated) {
                    CGImageSourceCreateThumbnailAtIndex(frames.source, frameIndex, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
                        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true
                    ] as CFDictionary)
                }.value
                guard !Task.isCancelled else { return }
                if let frame { show(frame) }
                try? await Task.sleep(for: .milliseconds(Int(delays[index] * 1000)))
                index = (index + 1) % count
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// ImageIO's source, read by one frame's decoding at a time.
    private final class FrameSource: @unchecked Sendable {
        let source: CGImageSource

        init(_ source: CGImageSource) {
            self.source = source
        }
    }

    /// The frame's delay as its format says it; browsers' 0.1 s for the
    /// too-short ones (0.01–0.02 s often means "as fast as you can").
    private nonisolated static func delay(_ source: CGImageSource, _ index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let dictionaries: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime)
        ]
        for (name, unclamped, clamped) in dictionaries {
            guard let entry = properties[name] as? [CFString: Any] else { continue }
            let value = (entry[unclamped] as? Double) ?? (entry[clamped] as? Double) ?? 0
            return value < 0.02 ? 0.1 : value
        }
        return 0.1
    }
}
