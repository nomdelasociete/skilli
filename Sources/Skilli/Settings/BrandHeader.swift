import Observation
import SwiftUI

/// Where the pointer is over Settings → General, for the glass S to turn
/// toward it. Shared with AppKit so the self-test can read it.
@MainActor
@Observable
final class MarkTilt {
    /// General's coordinate space: the pane, as the pointer is tracked in it.
    nonisolated static let space = "general-pane"

    /// The pointer's offset from the mark as a fraction of the pane, −0.5…0.5
    /// each way (y down); zero when the pointer is away.
    private(set) var offset = CGSize.zero
    @ObservationIgnored var center = CGPoint.zero
    @ObservationIgnored var paneSize = CGSize.zero

    func pointer(at location: CGPoint?) {
        guard let location, paneSize.width > 0, paneSize.height > 0 else {
            offset = .zero
            return
        }
        offset = CGSize(
            width: min(max((location.x - center.x) / paneSize.width, -0.5), 0.5),
            height: min(max((location.y - center.y) / paneSize.height, -0.5), 0.5)
        )
    }
}

/// The top of General: skil.li's glass S, its name, and what the pane is for.
struct BrandHeader: View {
    let tilt: MarkTilt

    var body: some View {
        VStack(spacing: 8) {
            GlassMark(tilt: tilt, size: 96)
                .onGeometryChange(for: CGPoint.self) { proxy in
                    let frame = proxy.frame(in: .named(MarkTilt.space))
                    return CGPoint(x: frame.midX, y: frame.midY)
                } action: { tilt.center = $0 }
            Text("skil.li")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text(SettingsPane.general.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .textCase(nil)
    }
}

/// The glass S with the halo in it (`BrandGlassHalo`), turned toward the
/// pointer like the site's hero: up to ±10° across and ±6° up or down, eased.
/// One static image under a 3D transform that Core Animation draws; nothing
/// runs while the pointer is still or away, and Reduce Motion keeps it flat.
struct GlassMark: View {
    let tilt: MarkTilt
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let offset = reduceMotion ? .zero : tilt.offset
        // Positive yaw turns the face right; positive pitch turns it up.
        let yaw = offset.width * 0.35
        let pitch = -offset.height * 0.2
        Image("BrandGlassHalo")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .rotation3DEffect(.radians(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.radians(pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .shadow(color: .black.opacity(0.25), radius: size * 0.08, x: -yaw * size * 0.25, y: size * 0.06)
            .animation(.smooth(duration: 0.6), value: offset)
            .accessibilityHidden(true)
    }
}
