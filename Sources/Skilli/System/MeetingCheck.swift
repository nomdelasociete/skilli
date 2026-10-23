import AppKit
import AVFoundation
import SkilliCore

/// The meeting card's Check Camera & Mic: the camera and the microphone a
/// call will use (macOS's preferred camera, the default microphone), shown
/// live through AVFoundation, nothing recorded. The camera is asked for
/// here the first time, the microphone too if Ask by Voice never asked.
/// Stopped as the card goes, before a call is joined.
final class MeetingCheck: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Device: Equatable {
        case on(String)
        case none
        case denied
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "skilli.meeting-check")
    private let audioOutput = AVCaptureAudioDataOutput()
    @MainActor private(set) var camera: Device = .none
    @MainActor private(set) var microphone: Device = .none
    @MainActor private(set) var isRunning = false

    /// The microphone's level now, 0…1, read from its channel's power.
    @MainActor var level: Double {
        guard isRunning, let channel = audioOutput.connections.first?.audioChannels.first else { return 0 }
        let decibels = Double(channel.averagePowerLevel)
        return min(max((decibels + 50) / 50, 0), 1)
    }

    /// The devices, asked for when macOS never asked; then the session
    /// runs. `asking` comes before macOS's own question shows (the card
    /// steps down so the question is not under it) and `answered` after.
    @MainActor
    func start(asking: @MainActor () -> Void, answered: @MainActor () -> Void) async {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let cameraDevice = AVCaptureDevice.systemPreferredCamera ?? AVCaptureDevice.default(for: .video)
        let microphoneDevice = AVCaptureDevice.default(for: .audio)
        if (videoStatus == .notDetermined && cameraDevice != nil) || (audioStatus == .notDetermined && microphoneDevice != nil) {
            asking()
            if videoStatus == .notDetermined, cameraDevice != nil { _ = await AVCaptureDevice.requestAccess(for: .video) }
            if audioStatus == .notDetermined, microphoneDevice != nil { _ = await AVCaptureDevice.requestAccess(for: .audio) }
            answered()
        }
        session.beginConfiguration()
        camera = add(cameraDevice, for: .video)
        microphone = add(microphoneDevice, for: .audio)
        if case .on = microphone, session.canAddOutput(audioOutput) {
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(audioOutput)
        }
        session.commitConfiguration()
        // Nothing to show live: the line says why.
        guard [camera, microphone].contains(where: { if case .on = $0 { true } else { false } }) else { return }
        isRunning = true
        queue.async { [self] in session.startRunning() }
        Log.trace("Meeting check: camera \(camera), microphone \(microphone)")
    }

    @MainActor
    private func add(_ device: AVCaptureDevice?, for media: AVMediaType) -> Device {
        guard let device else { return .none }
        guard AVCaptureDevice.authorizationStatus(for: media) == .authorized else { return .denied }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return .none }
        session.addInput(input)
        return .on(device.localizedName)
    }

    /// The camera's light goes off: nothing keeps running.
    @MainActor
    func stop() {
        guard isRunning else { return }
        isRunning = false
        queue.async { [self] in session.stopRunning() }
    }

    /// The samples themselves are not kept: the channel's power is read.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {}
}

/// What the check shows in the card, under who is in the meeting: the
/// camera live (mirrored, as the call will show you), then one line, the
/// camera's name on the left, the microphone's name and its level on the
/// right. Without a camera, the line alone.
final class MeetingCheckView: NSView {
    static let videoRatio: CGFloat = 9.0 / 16.0
    private static let lineHeight: CGFloat = 20

    private let video = NSView()
    private let cameraIcon = NSImageView()
    private let cameraLabel = NSTextField(labelWithString: "")
    private let micIcon = NSImageView()
    private let micLabel = NSTextField(labelWithString: "")
    private let meter = LevelMeter()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var ticker: Timer?
    private weak var check: MeetingCheck?
    /// A click on a device not allowed: Settings → Privacy.
    var onOpenPrivacy: (() -> Void)?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        video.wantsLayer = true
        video.layer?.cornerRadius = Theme.Radius.row
        video.layer?.cornerCurve = .continuous
        video.layer?.masksToBounds = true
        video.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        for label in [cameraLabel, micLabel] {
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
        }
        micLabel.alignment = .right
        for icon in [cameraIcon, micIcon] { icon.contentTintColor = .secondaryLabelColor }
        for subview in [video, cameraIcon, cameraLabel, micIcon, micLabel, meter] as [NSView] { addSubview(subview) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Shows `check` live: the camera in the box, the level moving.
    @MainActor
    func show(_ check: MeetingCheck) {
        self.check = check
        previewLayer?.removeFromSuperlayer()
        if case .on = check.camera {
            let layer = AVCaptureVideoPreviewLayer(session: check.session)
            layer.videoGravity = .resizeAspectFill
            if let connection = layer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            video.layer?.addSublayer(layer)
            previewLayer = layer
        } else {
            previewLayer = nil
        }
        let camera = Self.words(check.camera, device: "camera")
        cameraLabel.stringValue = camera.text
        cameraIcon.image = Theme.symbol(camera.on ? "video.fill" : "video.slash", pointSize: 12, weight: .medium)
        let mic = Self.words(check.microphone, device: "microphone")
        micLabel.stringValue = mic.text
        micIcon.image = Theme.symbol(mic.on ? "mic.fill" : "mic.slash", pointSize: 12, weight: .medium)
        meter.isHidden = !mic.on
        ticker?.invalidate()
        let ticker = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.meter.level = self?.check?.level ?? 0 }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        needsLayout = true
    }

    /// The box is gone and the level stops.
    func stopShowing() {
        ticker?.invalidate()
        ticker = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        sample = false
        video.layer?.contents = nil
    }

    /// Self-test (the Mac mini has no camera): the same box and line with
    /// a still image in place of the camera, to look at the layout.
    func showSample(camera: String, microphone: String, image: NSImage, level: Double) {
        stopShowing()
        sample = true
        video.layer?.contents = image
        video.layer?.contentsGravity = .resizeAspectFill
        cameraLabel.stringValue = camera
        cameraIcon.image = Theme.symbol("video.fill", pointSize: 12, weight: .medium)
        micLabel.stringValue = microphone
        micIcon.image = Theme.symbol("mic.fill", pointSize: 12, weight: .medium)
        meter.isHidden = false
        meter.level = level
        needsLayout = true
    }

    private var sample = false

    /// "FaceTime HD Camera", "No camera", "Camera not allowed".
    static func words(_ device: MeetingCheck.Device, device kind: String) -> (text: String, on: Bool) {
        switch device {
        case .on(let name): (name, true)
        case .none: ("No \(kind)", false)
        case .denied: ("\(kind.prefix(1).uppercased())\(kind.dropFirst()) not allowed", false)
        }
    }

    var hasVideo: Bool { previewLayer != nil || sample }

    /// Its height at `width`: the box (16:9) when there is a camera, and
    /// the line.
    func height(for width: CGFloat) -> CGFloat {
        (hasVideo ? (width * Self.videoRatio).rounded() + 10 : 0) + Self.lineHeight
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        var y: CGFloat = 0
        if hasVideo {
            let height = (width * Self.videoRatio).rounded()
            video.isHidden = false
            video.frame = NSRect(x: 0, y: 0, width: width, height: height)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer?.frame = video.bounds
            CATransaction.commit()
            y = height + 10
        } else {
            video.isHidden = true
        }
        cameraIcon.frame = NSRect(x: 0, y: y + 1, width: 18, height: 18)
        let meterWidth: CGFloat = meter.isHidden ? 0 : 44
        meter.frame = NSRect(x: width - meterWidth, y: y + 7, width: meterWidth, height: 6)
        micLabel.sizeToFit()
        let micWidth = min(micLabel.frame.width, width / 2 - 40)
        let micRight = width - (meter.isHidden ? 0 : meterWidth + 8)
        micLabel.frame = NSRect(x: micRight - micWidth, y: y + 1, width: micWidth, height: 18)
        micIcon.frame = NSRect(x: micLabel.frame.minX - 22, y: y + 1, width: 18, height: 18)
        cameraLabel.frame = NSRect(x: 24, y: y + 1, width: max(0, micIcon.frame.minX - 24 - 12), height: 18)
    }

    override func mouseDown(with event: NSEvent) {
        guard let check else { return }
        let point = convert(event.locationInWindow, from: nil)
        let denied = [check.camera, check.microphone].contains(.denied)
        if denied, point.y >= (hasVideo ? video.frame.maxY : 0) { onOpenPrivacy?() }
    }
}

/// The microphone's level: a short capsule filled in the accent color as
/// sound comes in.
final class LevelMeter: NSView {
    var level: Double = 0 {
        didSet {
            // Eased, so speech reads as a level, not a flicker.
            shown = level > shown ? level : shown * 0.82 + level * 0.18
            needsDisplay = true
        }
    }
    private var shown: Double = 0

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        track.fill()
        guard shown > 0.01 else { return }
        let width = max(bounds.height, bounds.width * shown)
        let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.controlAccentColor.setFill()
        fill.fill()
    }
}
