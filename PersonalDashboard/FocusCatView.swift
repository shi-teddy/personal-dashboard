import SwiftUI

enum CatLayout {
    static let artwork = ApprovedCatArtwork.shared
    static let settleDuration = artwork.clips["settle"]!.duration
    static let reachDuration = artwork.clips["reach"]!.duration
    static let recoverDuration = artwork.clips["recover"]!.duration
    static let closeTime = artwork.manifest.closeTime
    static let drawingSize = CGSize(width: artwork.manifest.canvasWidth, height: artwork.manifest.canvasHeight)
    static let panelSize = CGSize(width: drawingSize.width + 30, height: drawingSize.height + 20)

    static func pawContact(facingRight: Bool) -> CGPoint {
        let data = artwork.manifest
        let x = facingRight ? data.pawX : 144 - data.pawX
        return CGPoint(x: (panelSize.width - drawingSize.width)/2 + data.paddingX + x,
                       y: drawingSize.height - data.paddingY - data.pawY)
    }

    /// Clamp the visible artwork, including its raised paw and unwrapping tail,
    /// rather than the transparent window padding.
    static var visibleBounds: CGRect {
        let data = artwork.manifest, bounds = artwork.bounds
        let left = min(bounds.minX, 144 - bounds.maxX)
        let right = max(bounds.maxX, 144 - bounds.minX)
        return CGRect(x: 15 + data.paddingX + left,
                      y: drawingSize.height - data.paddingY - bounds.maxY,
                      width: right - left, height: bounds.height)
    }
}

struct CatGait {
    static let walk = Self()
    // The approved GIF uses the same gait in both directions.
    static let run = Self()
    static let updateInterval = 1.0 / 60.0
    static let phaseUnitsPerSecond = 1.0
    var loopDuration: Double { CatLayout.artwork.clips["walk"]!.duration }
    var distancePerLoop: Double { CatLayout.artwork.manifest.distancePerLoop }
    var speed: Double { distancePerLoop / loopDuration }
    var stepLength: Double { distancePerLoop / 2 }
    var stepDuration: Double { loopDuration / 2 }
    func phaseAdvance(distance: Double) -> Double { max(0, distance) / speed }
}

struct FocusCatView: View {
    @ObservedObject var controller: FocusCatController
    @ObservedObject private var animation: CatAnimationState

    init(controller: FocusCatController) {
        self.controller = controller
        self.animation = controller.animation
    }
    var body: some View {
        WhiteFocusCat(pose: controller.pose, facingRight: controller.facingRight,
                      phase: animation.phase, isSprinting: controller.isSprinting,
                      isDeparting: controller.isDeparting)
            .frame(width: CatLayout.drawingSize.width, height: CatLayout.drawingSize.height)
            .frame(width: CatLayout.panelSize.width, height: CatLayout.panelSize.height, alignment: .bottom)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Focus Cat")
            .accessibilityValue(controller.statusText.isEmpty ? "Sleeping in the corner" : controller.statusText)
    }
}

struct WhiteFocusCat: View {
    let pose: FocusCatPose
    let facingRight: Bool
    let phase: Double
    var isSprinting = false
    var isDeparting = false

    static func clip(for pose: FocusCatPose, phase: Double, isDeparting: Bool = false) -> String {
        switch pose {
        case .sleeping: return "sleep"
        case .waking: return "wake"
        case .settling: return "settle"
        case .running: return isDeparting && phase < 0.18 ? "depart" : "walk"
        case .reaching: return "reach"
        case .celebrating: return "recover"
        }
    }

    static func attention(for pose: FocusCatPose, phase: Double) -> Double {
        guard pose == .waking else { return 0 }
        return min(1, max(0, (phase - 0.2) / 0.15)) * min(1, max(0, (1.3 - phase) / 0.2))
    }

    var body: some View {
        Canvas { context, size in
            let artwork = CatLayout.artwork
            let frame = artwork.frame(Self.clip(for: pose, phase: phase, isDeparting: isDeparting), seconds: phase)
            context.withCGContext { artwork.draw(frame, in: $0, size: size, facingRight: facingRight,
                                                   attention: Self.attention(for: pose, phase: phase)) }
        }
        // Every in-between frame is already authored. SwiftUI must not add
        // crossfades or interpolate between two different cat silhouettes.
        .transaction { $0.animation = nil }
    }
}
