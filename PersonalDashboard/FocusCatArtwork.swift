import CoreGraphics
import Foundation

/// The approved workcat-v3 GIF, baked into transparent drawing frames.
/// No legacy artwork, substitute sleep illustration, or runtime shape morphing.
final class ApprovedCatArtwork {
    struct FrameData: Decodable {
        let points: [Double]
        let tail: [Double]
        let tailWidth: Double
        let tailSeam: Double
        let offsetY: Double
    }
    struct ClipData: Decodable {
        let duration: Double
        let loop: Bool
        let frames: [FrameData]
    }
    struct Manifest: Decodable {
        let version: Int
        let source: String
        let sourceSHA256: String
        let fps: Double
        let canvasWidth: Double
        let canvasHeight: Double
        let paddingX: Double
        let paddingY: Double
        let pawX: Double
        let pawY: Double
        let distancePerLoop: Double
        let closeTime: Double
        var clips: [String: ClipData]
    }
    struct Frame {
        let body: CGPath
        let face: [CGPath]
        let tail: CGPath?
        let tailSeamPath: CGPath?
        let tailWidth: CGFloat
        let tailSeam: CGFloat
        let offsetY: CGFloat
        let bounds: CGRect
    }
    struct Clip {
        let duration: Double
        let loop: Bool
        let frames: [Frame]
    }
    enum InvalidArtwork: Error { case invalidManifest, invalidFrame }

    static let shared: ApprovedCatArtwork = {
        guard let url = Bundle.main.url(forResource: "ApprovedCatAnimation", withExtension: "json") else {
            preconditionFailure("ApprovedCatAnimation.json is missing from the application bundle")
        }
        do { return try ApprovedCatArtwork(url: url) }
        catch { preconditionFailure("Cannot load approved cat animation: \(error)") }
    }()

    let manifest: Manifest
    let clips: [String: Clip]
    let bounds: CGRect

    init(url: URL) throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        let required = Set(["sleep", "wake", "walk", "depart", "reach", "recover", "settle"])
        guard manifest.version == 3, manifest.fps == 60,
              manifest.canvasWidth > 0, manifest.canvasHeight > 0,
              manifest.distancePerLoop > 0, required.isSubset(of: Set(manifest.clips.keys)) else {
            throw InvalidArtwork.invalidManifest
        }
        var clips: [String: Clip] = [:]
        var bounds = CGRect.null
        for (name, data) in manifest.clips {
            guard data.duration.isFinite, data.duration > 0, !data.frames.isEmpty else {
                throw InvalidArtwork.invalidManifest
            }
            let frames = try data.frames.map { value -> Frame in
                guard value.points.count == 440, value.tail.count.isMultiple(of: 2),
                      (value.points + value.tail + [value.offsetY, value.tailWidth, value.tailSeam]).allSatisfy(\.isFinite) else {
                    throw InvalidArtwork.invalidFrame
                }
                let points = stride(from: 0, to: value.points.count, by: 2).map {
                    CGPoint(x: value.points[$0], y: value.points[$0 + 1])
                }
                let tailPoints = stride(from: 0, to: value.tail.count, by: 2).map {
                    CGPoint(x: value.tail[$0], y: value.tail[$0 + 1])
                }
                let body = Self.contour(Array(points[0..<160]))
                let face = [160, 180, 200].map { Self.contour(Array(points[$0..<($0 + 20)])) }
                let tail = tailPoints.isEmpty ? nil : Self.line(tailPoints)
                let seam = tailPoints.count > 8 ? Self.line(Array(tailPoints.dropFirst(8))) : nil
                var frameBounds = body.boundingBoxOfPath
                if let tail {
                    frameBounds = frameBounds.union(tail.boundingBoxOfPath.insetBy(dx: -(value.tailWidth + 1.5)/2,
                                                                                 dy: -(value.tailWidth + 1.5)/2))
                }
                frameBounds = frameBounds.offsetBy(dx: 0, dy: value.offsetY)
                bounds = bounds.union(frameBounds)
                return Frame(body: body, face: face, tail: tail, tailSeamPath: seam,
                             tailWidth: value.tailWidth, tailSeam: value.tailSeam,
                             offsetY: value.offsetY, bounds: frameBounds)
            }
            clips[name] = Clip(duration: data.duration, loop: data.loop, frames: frames)
        }
        // Drawing paths own the compiled geometry. Release the decoded coordinate
        // arrays rather than retaining a second copy for the app's lifetime.
        var metadata = manifest
        metadata.clips = [:]
        self.manifest = metadata
        self.clips = clips
        self.bounds = bounds.union(CGRect(x: 116, y: -22, width: 9, height: 21))
    }

    func frame(_ name: String, seconds: Double) -> Frame {
        guard let clip = clips[name] else { preconditionFailure("Unknown cat clip: \(name)") }
        let seconds = seconds.isFinite ? max(0, seconds) : 0
        if !clip.loop, seconds >= clip.duration { return clip.frames[clip.frames.count - 1] }
        let time = clip.loop ? seconds.truncatingRemainder(dividingBy: clip.duration) : seconds
        return clip.frames[min(clip.frames.count - 1, Int((time * manifest.fps + 1e-7).rounded(.down)))]
    }

    private static func contour(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.move(to: points[0])
        for i in points.indices {
            let a = points[(i + points.count - 1) % points.count], b = points[i]
            let c = points[(i + 1) % points.count], d = points[(i + 2) % points.count]
            path.addCurve(to: c,
                          control1: CGPoint(x: b.x + (c.x - a.x)/6, y: b.y + (c.y - a.y)/6),
                          control2: CGPoint(x: c.x - (d.x - b.x)/6, y: c.y - (d.y - b.y)/6))
        }
        path.closeSubpath()
        return path
    }

    private static func line(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        return path
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                components: [red/255, green/255, blue/255, 1])!
    }

    private static let cream = color(227, 224, 211)
    private static let ink = color(22, 22, 20)
    private static let attentionRed = color(231, 65, 67)

    /// Draw in top-left coordinates, exactly as in the approved animation.
    func draw(_ frame: Frame, in context: CGContext, size: CGSize, facingRight: Bool, attention: Double = 0) {
        let scale = min(size.width / manifest.canvasWidth, size.height / manifest.canvasHeight)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: (size.width - manifest.canvasWidth * scale)/2,
                            y: size.height - manifest.canvasHeight * scale)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: manifest.paddingX, y: manifest.paddingY + frame.offsetY)
        if !facingRight {
            context.translateBy(x: 144, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        let cream = Self.cream
        context.setFillColor(cream)
        context.addPath(frame.body)
        context.fillPath()
        if let tail = frame.tail {
            context.setLineCap(.round)
            context.setLineJoin(.round)
            if frame.tailSeam > 0, let seam = frame.tailSeamPath {
                let shade = frame.tailSeam
                context.setStrokeColor(Self.color(227 - 28*shade, 224 - 28*shade, 211 - 28*shade))
                context.setLineWidth(frame.tailWidth + 1.5*shade)
                context.addPath(seam)
                context.strokePath()
            }
            context.setStrokeColor(cream)
            context.setLineWidth(frame.tailWidth)
            context.addPath(tail)
            context.strokePath()
        }
        context.setFillColor(Self.ink)
        for path in frame.face { context.addPath(path); context.fillPath() }
        if attention > 0 {
            context.setAlpha(attention)
            let red = Self.attentionRed
            let headTop = frame.body.boundingBoxOfPath.minY
            let markX = frame.face[1].boundingBoxOfPath.midX - 2
            context.setStrokeColor(red)
            context.setLineWidth(2.7)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: markX, y: headTop - 17))
            context.addLine(to: CGPoint(x: markX, y: headTop - 10))
            context.strokePath()
            context.setFillColor(red)
            context.fillEllipse(in: CGRect(x: markX - 1.4, y: headTop - 6, width: 2.8, height: 2.8))
        }
    }
}
