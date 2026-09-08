import SwiftUI

struct FocusCatView: View {
    @ObservedObject var controller: FocusCatController

    var body: some View {
        ZStack(alignment: .bottom) {
            WhiteFocusCat(
                pose: controller.pose,
                facingRight: controller.facingRight,
                phase: controller.animationPhase
            )
            .frame(width: 120, height: 86)
        }
        .frame(width: 154, height: 122, alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus Cat")
        .accessibilityValue(controller.statusText.isEmpty ? "Sleeping in the corner" : controller.statusText)
    }
}

/// A deliberately simple cream silhouette: rounded body, stubby legs, upright
/// ears, and only a few face marks. Filled, overlapping pieces keep the cat soft.
struct WhiteFocusCat: View {
    let pose: FocusCatPose
    let facingRight: Bool
    let phase: Double

    var body: some View {
        Group {
            if pose == .sleeping {
                SleepingFocusCat(phase: phase)
            } else {
                AwakeFocusCat(pose: pose, phase: phase)
            }
        }
        .scaleEffect(x: facingRight ? 1 : -1, y: 1)
        .shadow(color: .black.opacity(0.14), radius: 1.2, y: 1)
    }
}

private struct AwakeFocusCat: View {
    let pose: FocusCatPose
    let phase: Double

    private var stride: CGFloat {
        pose == .running ? CGFloat(sin(phase * .pi * 2)) : 0
    }

    private var reach: CGFloat {
        guard pose == .reaching else { return 0 }
        return CGFloat(sin(min(1, max(0, phase)) * .pi))
    }

    private var lift: CGFloat {
        switch pose {
        case .running: abs(stride) * 2.4
        case .waking: CGFloat(sin(min(1, phase) * .pi)) * 2
        case .reaching: reach * 2
        case .celebrating: abs(CGFloat(sin(phase * .pi))) * 5
        case .sleeping: 0
        }
    }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.10))
                .frame(width: 82, height: 7)
                .offset(x: -2, y: 34)

            catSilhouette
                .offset(y: -lift)
                .scaleEffect(
                    x: pose == .waking ? 1.03 : 1,
                    y: pose == .waking ? 0.95 : 1,
                    anchor: .bottom
                )
        }
    }

    private var catSilhouette: some View {
        ZStack {
            SimpleTailShape(sway: stride)
                .stroke(catFill, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                .frame(width: 39, height: 50)
                .offset(x: -43, y: -1)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(catFill)
                .frame(width: 72, height: 39)
                .offset(x: -4, y: 8)

            leg(stride * 7)
                .offset(x: -27, y: 27 + max(0, stride) * 2)
            leg(-stride * 7)
                .offset(x: -10, y: 27 + max(0, -stride) * 2)
            leg(-stride * 7)
                .offset(x: 10, y: 27 + max(0, stride) * 2)

            raisedPaw
                .offset(x: 27, y: 26 - reach * 21)

            SimpleCatHead(reach: reach)
                .frame(width: 48, height: 46)
                .offset(x: 29, y: -8 - reach * 7)

            if pose == .celebrating {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.88, green: 0.64, blue: 0.28))
                    .offset(x: 49, y: -38)
            }
        }
    }

    private func leg(_ angle: CGFloat) -> some View {
        Capsule()
            .fill(catFill)
            .frame(width: 15, height: 27)
            .rotationEffect(.degrees(Double(angle)), anchor: .top)
    }

    private var raisedPaw: some View {
        Capsule()
            .fill(catFill)
            .frame(width: 15, height: 27 + reach * 35)
            .rotationEffect(.degrees(Double(-reach * 12)), anchor: .bottom)
    }

    private var catFill: Color { Color(red: 0.93, green: 0.92, blue: 0.86) }
}

private struct SleepingFocusCat: View {
    let phase: Double

    private var breathing: CGFloat {
        CGFloat(sin(phase * .pi * 2))
    }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.09))
                .frame(width: 85, height: 7)
                .offset(y: 31)

            SimpleSleepingTailShape()
                .stroke(catFill, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .frame(width: 70, height: 42)
                .offset(x: -10, y: 8)

            Ellipse()
                .fill(catFill)
                .frame(width: 76 + breathing, height: 46 + breathing * 0.5)
                .offset(x: -5, y: 9)

            Capsule()
                .fill(catFill)
                .frame(width: 31, height: 14)
                .rotationEffect(.degrees(-8))
                .offset(x: 22, y: 27)

            ZStack {
                Triangle()
                    .fill(catFill)
                    .frame(width: 15, height: 17)
                    .rotationEffect(.degrees(-13))
                    .offset(x: -10, y: -15)
                Triangle()
                    .fill(catFill)
                    .frame(width: 15, height: 17)
                    .rotationEffect(.degrees(13))
                    .offset(x: 10, y: -15)
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(catFill)
                    .frame(width: 39, height: 34)
                HStack(spacing: 8) {
                    Capsule().fill(faceColor).frame(width: 7, height: 1.5)
                    Capsule().fill(faceColor).frame(width: 7, height: 1.5)
                }
                .offset(y: -2)
                Circle().fill(faceColor).frame(width: 3.5, height: 3.5).offset(y: 5)
            }
            .offset(x: 28, y: 7)

            Text("z")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(faceColor.opacity(0.72))
                .offset(x: 46, y: -27 - breathing)
        }
    }

    private var catFill: Color { Color(red: 0.93, green: 0.92, blue: 0.86) }
    private var faceColor: Color { Color(red: 0.13, green: 0.14, blue: 0.14) }
}

private struct SimpleCatHead: View {
    let reach: CGFloat

    var body: some View {
        ZStack {
            Triangle()
                .fill(catFill)
                .frame(width: 18, height: 20)
                .rotationEffect(.degrees(-10))
                .offset(x: -12, y: -17)
            Triangle()
                .fill(catFill)
                .frame(width: 18, height: 20)
                .rotationEffect(.degrees(10))
                .offset(x: 12, y: -17)

            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(catFill)
                .frame(width: 44, height: 38)

            HStack(spacing: 12) {
                Circle().fill(faceColor).frame(width: 4.5, height: 4.5)
                Circle().fill(faceColor).frame(width: 4.5, height: 4.5)
            }
            .offset(y: -3)

            Circle()
                .fill(faceColor)
                .frame(width: 3.5, height: 3.5)
                .offset(y: 5)

            HStack(spacing: 1) {
                Text("⌣")
                Text("⌣")
            }
            .font(.system(size: 6, weight: .bold))
            .foregroundStyle(faceColor)
            .offset(y: 8)

            if reach > 0.55 {
                Text("×")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.67, green: 0.24, blue: 0.20))
                    .offset(x: 29, y: -29)
            }
        }
    }

    private var catFill: Color { Color(red: 0.93, green: 0.92, blue: 0.86) }
    private var faceColor: Color { Color(red: 0.13, green: 0.14, blue: 0.14) }
}

private struct SimpleTailShape: Shape {
    let sway: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.76))
        path.addCurve(
            to: CGPoint(x: rect.minX + 8, y: rect.minY + 7 + sway),
            control1: CGPoint(x: rect.midX, y: rect.maxY + sway * 2),
            control2: CGPoint(x: rect.minX - 2, y: rect.midY + sway * 2)
        )
        return path
    }
}

private struct SimpleSleepingTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 5, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 4, y: rect.maxY - 5),
            control1: CGPoint(x: rect.minX - 1, y: rect.maxY + 2),
            control2: CGPoint(x: rect.midX, y: rect.maxY + 6)
        )
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
