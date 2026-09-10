import SwiftUI

enum CatLayout {
    static let settleDuration = 2.0
    static let drawingSize = CGSize(width: 144, height: 103.2)
    static let panelSize = CGSize(width: 184, height: 148)
    static let actionLift: CGFloat = 32
    static let scale = min(drawingSize.width / 144, drawingSize.height / 108)

    /// Derive contact from the actual reaching contour, so resizing cannot
    /// separate the paw from the tab's close control.
    static func pawContact(facingRight: Bool) -> CGPoint {
        let values = GIFCatInk.frame(84).values
        let tip = (0..<160).max { values[$0*2] < values[$1*2] }!
        let sourceX = values[tip*2]
        let sourceY = values[tip*2+1]
        let inset = (drawingSize.width - 144*scale)/2
        let x = inset + sourceX*scale
        return CGPoint(x: (panelSize.width-drawingSize.width)/2 + (facingRight ? x : drawingSize.width-x),
                       y: drawingSize.height - sourceY*scale + actionLift)
    }
}

struct FocusCatView: View {
    @ObservedObject var controller: FocusCatController

    var body: some View {
        ZStack(alignment: .bottom) {
            WhiteFocusCat(
                pose: controller.pose,
                facingRight: controller.facingRight,
                phase: controller.animationPhase,
                isSprinting: controller.isSprinting
            )
            .frame(width: CatLayout.drawingSize.width, height: CatLayout.drawingSize.height)
        }
        .frame(width: CatLayout.panelSize.width, height: CatLayout.panelSize.height, alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus Cat")
        .accessibilityValue(controller.statusText.isEmpty ? "Sleeping in the corner" : controller.statusText)
    }
}

/// One calibration shared by panel movement and the GIF player. Distances
/// are macOS logical pixels (points), so Retina backing scale changes neither.
struct CatGait {
    let firstFrame: Int
    let frameCount: Int
    let stepsPerLoop: Double

    static let walk = Self(firstFrame: 20, frameCount: 20, stepsPerLoop: 2)
    static let run = Self(firstFrame: 55, frameCount: 16, stepsPerLoop: 8)
    static let phaseUnitsPerSecond = 9.0
    static let updateInterval = 1.0 / 60.0

    // A planted foot sweeps about 18 source pixels between support changes.
    // Use the exact same scale as the desktop drawing below.
    static let drawingScale = CatLayout.scale
    var stepLength: Double { 18 * Self.drawingScale }
    var loopDuration: Double {
        GIFCatFrames.durations[(firstFrame - 20)..<(firstFrame - 20 + frameCount)].reduce(0,+) / 1000
    }
    var stepDuration: Double { loopDuration / stepsPerLoop }
    var speed: Double { stepLength / stepDuration }
    var distancePerLoop: Double { stepLength * stepsPerLoop }

    func phaseAdvance(distance: Double) -> Double {
        max(0, distance) / speed * Self.phaseUnitsPerSecond
    }
    func artwork(phase: Double) -> GIFCatInk {
        .loop(firstFrame, count: frameCount, seconds: phase / Self.phaseUnitsPerSecond)
    }
}

/// Uses only the existing controller's pose, phase and facing direction.
struct WhiteFocusCat: View {
    let pose: FocusCatPose
    let facingRight: Bool
    let phase: Double
    var isSprinting = false

    private var contact: Double {
        switch pose {
        case .reaching: return min(1, max(0, phase / 0.62))
        case .celebrating: return 1 - min(1, max(0, (phase - 0.62) / 2.8))
        default: return 0
        }
    }

    private var artwork: GIFCatInk {
        switch pose {
        case .sleeping:
            return .tucked(phase: phase)
        case .settling, .waking:
            return .settling(progress: 1 - awakeAmount)
        case .running:
            return (isSprinting ? CatGait.run : CatGait.walk).artwork(phase: phase)
        case .reaching:
            return .frame(74 + contact * 10)
        case .celebrating:
            return .frame(84 + (1 - contact) * 10)
        }
    }

    private var awakeAmount: Double {
        switch pose {
        case .sleeping: return 0
        case .settling: return 1 - min(1, max(0, phase / CatLayout.settleDuration))
        case .waking: return min(1, max(0, phase / CatLayout.settleDuration))
        default: return 1
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(.black.opacity(0.14))
                .frame(width: pose == .sleeping ? 76 : 82, height: 7)
                .blur(radius: 2)
                .padding(.bottom, 2)
                .offset(x: 5)
            ZStack {
                GIFCatDrawing(ink: artwork)
                TuckedSleepingCat(phase: pose == .sleeping ? phase : 0)
                    .opacity(GIFCatInk.ease((1 - awakeAmount - 0.5) / 0.5))
            }
            // Place the GIF's outstretched paw at the existing overlay contact
            // height. This is a drawing offset, not a window movement change.
            .offset(y: -CatLayout.actionLift * contact)
            .shadow(color: .black.opacity(0.13), radius: 1.5, x: 0, y: 1.5)
            .animation(.linear(duration: CatGait.updateInterval), value: phase)
            .animation(.easeInOut(duration: 0.12), value: pose)
        }
        .scaleEffect(x: facingRight ? 1 : -1, y: 1)
    }
}


/// Vector contours traced from the user-supplied workcat_animation.gif.
/// Frames retain the source's body and facial shapes; the app supplies timing.
struct GIFCatInk: VectorArithmetic {
    var values: [Double]
    static func ease(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t*t*t*(t*(t*6-15)+10)
    }

    /// Articulated settle: planted feet, bent legs, tucked paws, then tail.
    /// Head, ears and mouth retain their geometry; the lids close at rest.
    static func settling(progress: Double) -> Self {
        let source = frame(24).values
        var v = source
        let lower = ease(progress / 0.7)
        let tuck = ease((progress - 0.25) / 0.6)
        let curl = ease((progress - 0.5) / 0.5)
        let drop = 18 * lower
        for i in 0..<80 {
            let x = source[i*2], y = source[i*2+1]
            let bentY = y + drop * max(0, min(1, (103-y)/33))
            let t = Double(i)/80
            let tuckedY = 88 + 14 * pow(sin(t * .pi), 0.65)
            v[i*2] = x
            v[i*2+1] = bentY + (tuckedY-bentY)*tuck
        }
        for i in 80..<160 { v[i*2+1] += drop }
        // A continuous rounded haunch replaces the old tail-to-back junction.
        // Its endpoint meets the unchanged head contour as the head rests down.
        let rest = ease((progress - 0.35) / 0.65)
        for i in 120..<220 {
            v[i*2] -= 4 * rest
            if i >= 160 { v[i*2+1] += drop }
            v[i*2+1] += 6 * rest
        }
        for i in 0..<80 {
            let t = Double(i)/80
            v[i*2] -= 4 * rest * (1-t)
            v[i*2+1] += 6 * rest * (1-t)
        }
        for i in 80..<125 {
            let t = Double(i-80)/45, u = 1-t
            let endX = source[250] - 4*rest
            let endY = source[251] + drop + 6*rest
            let x = u*u*u*source[160] + 3*u*u*t*4 + 3*u*t*t*(endX-14) + t*t*t*endX
            let y = u*u*u*(70+drop) + 3*u*u*t*32 + 3*u*t*t*(endY+4) + t*t*t*endY
            v[i*2] += (x-v[i*2])*curl
            v[i*2+1] += (y-v[i*2+1])*curl
        }
        // Close the lids only after the head rests; keep eye width and mouth.
        let lids = ease((progress - 0.65) / 0.35)
        for start in [160, 200] {
            var cx = 0.0, cy = 0.0
            for i in start..<(start+20) { cx += v[i*2]; cy += v[i*2+1] }
            cx /= 20; cy /= 20
            let radius = (start..<(start+20)).map { abs(v[$0*2]-cx) }.max() ?? 1
            for i in start..<(start+20) {
                let x = (v[i*2]-cx) / max(radius, 0.1)
                let closedY = cy + (v[i*2+1]-cy)*0.18 + 0.65*(1-x*x)
                v[i*2+1] += (closedY-v[i*2+1])*lids
            }
        }
        return Self(values: v)
    }

    static func tucked(phase: Double) -> Self {
        var result = settling(progress: 1)
        let breath = sin(phase * .pi) * 0.18
        // Smooth breathing across the back, with the head and face moving together.
        for i in 80..<220 {
            let weight = i < 120 ? ease(Double(i-80)/40) : 1
            result.values[i*2+1] -= breath * weight
        }
        return result
    }
    static var zero: Self { Self(values: []) }
    static func + (a: Self, b: Self) -> Self {
        if a.values.isEmpty { return b }; if b.values.isEmpty { return a }
        return Self(values: zip(a.values, b.values).map(+))
    }
    static func - (a: Self, b: Self) -> Self {
        if b.values.isEmpty { return a }
        if a.values.isEmpty { return Self(values: b.values.map { -$0 }) }
        return Self(values: zip(a.values, b.values).map(-))
    }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
    static func blend(_ a: Self, _ b: Self, amount: Double) -> Self {
        Self(values: zip(a.values,b.values).map { $0 + ($1-$0)*amount })
    }
    static func frame(_ sourceIndex: Double) -> Self {
        let index = min(74, max(0, sourceIndex - 20))
        let lower = Int(index), upper = min(74, lower + 1)
        let t = index - Double(lower)
        return Self(values: zip(GIFCatFrames.values[lower], GIFCatFrames.values[upper]).map { $0 + ($1 - $0) * t })
    }
    static func loop(_ start: Int, count: Int, seconds: Double) -> Self {
        let durations = Array(GIFCatFrames.durations[(start - 20)..<(start - 20 + count)])
        var elapsed = max(0, seconds * 1000).truncatingRemainder(dividingBy: durations.reduce(0,+))
        var lower = 0
        while lower < count - 1 && elapsed >= durations[lower] {
            elapsed -= durations[lower]
            lower += 1
        }
        let t = elapsed / durations[lower]
        let a = GIFCatFrames.values[start - 20 + lower]
        let b = GIFCatFrames.values[start - 20 + (lower + 1) % count]
        let previousIndex = (lower + count - 1) % count
        let nextIndex = (lower + 1) % count
        let previous = GIFCatFrames.values[start - 20 + previousIndex]
        let next = GIFCatFrames.values[start - 20 + (lower + 2) % count]
        let t2 = t*t, t3 = t2*t
        // Time-aware Hermite interpolation carries velocity across GIF frames.
        // Clamp to the adjacent poses so toes cannot overshoot their outlines.
        return Self(values: a.indices.map { i in
            let m0 = (b[i] - previous[i]) * durations[lower] / (durations[previousIndex] + durations[lower])
            let m1 = (next[i] - a[i]) * durations[lower] / (durations[lower] + durations[nextIndex])
            let value = (2*t3 - 3*t2 + 1)*a[i] + (t3 - 2*t2 + t)*m0
                + (-2*t3 + 3*t2)*b[i] + (t3-t2)*m1
            return min(max(a[i],b[i]), max(min(a[i],b[i]), value))
        })
    }
}

struct GIFCatDrawing: View, Animatable {
    var ink: GIFCatInk
    var silhouetteOnly = false
    var animatableData: GIFCatInk {
        get { ink }
        set { ink = newValue }
    }
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 144, size.height / 108)
            context.translateBy(x: (size.width - 144 * scale) / 2, y: size.height - 108 * scale)
            context.scaleBy(x: scale, y: scale)
            func contour(start: Int, count: Int) -> Path {
                let faceScale = start == 0 ? 1.0 : 1.5
                let centerX = (start..<(start+count)).reduce(0.0) { $0+ink.values[$1*2] }/Double(count)
                let centerY = (start..<(start+count)).reduce(0.0) { $0+ink.values[$1*2+1] }/Double(count)
                func point(_ index: Int) -> CGPoint {
                    let i = start + (index + count) % count
                    return CGPoint(x: centerX+(ink.values[i*2]-centerX)*faceScale,
                                   y: centerY+(ink.values[i*2+1]-centerY)*faceScale)
                }
                var path = Path()
                path.move(to: point(0))
                for i in 0..<count {
                    let p0 = point(i-1), p1 = point(i), p2 = point(i+1), p3 = point(i+2)
                    path.addCurve(to: p2,
                                  control1: CGPoint(x: p1.x + (p2.x-p0.x)/6, y: p1.y + (p2.y-p0.y)/6),
                                  control2: CGPoint(x: p2.x - (p3.x-p1.x)/6, y: p2.y - (p3.y-p1.y)/6))
                }
                path.closeSubpath()
                return path
            }
            context.fill(contour(start:0,count:160), with:.color(silhouetteOnly ? .black : Color(red:227/255.0,green:224/255.0,blue:211/255.0)))
            if !silhouetteOnly {
                for start in [160,180,200] {
                    context.fill(contour(start:start,count:20), with:.color(Color(red:0.085,green:0.087,blue:0.08)))
                }
            }
        }
    }
}


/// Option one: an upright sleeping loaf with tucked paws and a wrapped tail.
/// A single smooth silhouette keeps the head and torso seamlessly connected.
private struct TuckedSleepingCat: View, Animatable {
    var phase: Double
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 144, size.height / 108)
            context.translateBy(x: (size.width + 144*scale)/2,
                                y: size.height - 108*scale)
            context.scaleBy(x: -scale, y: scale)
            let cream = Color(red: 227/255.0, green: 224/255.0, blue: 211/255.0)
            let seam = Color(red: 210/255.0, green: 207/255.0, blue: 194/255.0)
            // The tail is at rest over the front paws, with a rounded tip.
            var tail = Path()
            tail.move(to: CGPoint(x: 118, y: 88))
            tail.addCurve(to: CGPoint(x: 91, y: 91), control1: CGPoint(x: 116, y: 95), control2: CGPoint(x: 104, y: 94))
            tail.addCurve(to: CGPoint(x: 62, y: 81), control1: CGPoint(x: 78, y: 90), control2: CGPoint(x: 72, y: 81))
            tail.addCurve(to: CGPoint(x: 54, y: 95), control1: CGPoint(x: 52, y: 81), control2: CGPoint(x: 47, y: 89))
            tail.addCurve(to: CGPoint(x: 84, y: 103), control1: CGPoint(x: 61, y: 103), control2: CGPoint(x: 71, y: 103))
            tail.addCurve(to: CGPoint(x: 118, y: 88), control1: CGPoint(x: 115, y: 103), control2: CGPoint(x: 121, y: 96))
            tail.closeSubpath()
            context.fill(tail, with: .color(cream))
            var curl = Path()
            curl.move(to: CGPoint(x: 89, y: 91))
            curl.addCurve(to: CGPoint(x: 62, y: 81), control1: CGPoint(x: 77, y: 90), control2: CGPoint(x: 72, y: 81))
            curl.addCurve(to: CGPoint(x: 54, y: 95), control1: CGPoint(x: 52, y: 81), control2: CGPoint(x: 47, y: 89))
            context.stroke(curl, with: .color(seam.opacity(0.8)), style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))


        }
    }
}
