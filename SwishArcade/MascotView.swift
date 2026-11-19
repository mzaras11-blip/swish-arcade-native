import SwiftUI

/// The SWISH mascot, drawn entirely in code: blue #1E9BFF body, red
/// backwards cap with a white S, yellow bolt on the chest, big grin.
/// Mood-driven — he lives on the game screen and reacts to the match:
/// idle bob, celebrate (word scored), big-play (double word / combo ×5),
/// ouch (CPU scores or a wrong tile), thinking (eyes on the CPU).
struct MascotView: View {
    let mood: MascotMood
    var size: CGFloat = 96
    @State private var bob = false

    private var blue: Color { Color(red: 0.12, green: 0.61, blue: 1.00) }
    private var blueDark: Color { Color(red: 0.05, green: 0.42, blue: 0.80) }
    private var capRed: Color { Color(red: 0.92, green: 0.16, blue: 0.20) }
    private var capDark: Color { Color(red: 0.72, green: 0.08, blue: 0.12) }

    var body: some View {
        let w = size, h = size * 1.12
        ZStack {
            // shoes
            HStack(spacing: w * 0.16) {
                shoe; shoe
            }
            .offset(y: h * 0.46)
            // arms (gloves)
            Circle().fill(Color.white)
                .frame(width: w * 0.2, height: w * 0.2)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                .offset(x: -w * 0.52, y: armY(left: true))
            Circle().fill(Color.white)
                .frame(width: w * 0.2, height: w * 0.2)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                .offset(x: w * 0.52, y: armY(left: false))
            // body
            RoundedRectangle(cornerRadius: w * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.72, blue: 1.0), blue, blueDark],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.92, height: h * 0.78)
                .overlay(RoundedRectangle(cornerRadius: w * 0.26, style: .continuous)
                    .strokeBorder(blueDark, lineWidth: max(1.5, w * 0.02)))
                .offset(y: -h * 0.04)
            // bolt on the chest
            BoltShape()
                .fill(TilePalette.bolt)
                .overlay(BoltShape().stroke(Color(red: 0.80, green: 0.58, blue: 0.0), lineWidth: 1))
                .frame(width: w * 0.2, height: w * 0.28)
                .offset(y: h * 0.16)
            // face
            face
                .offset(y: -h * 0.16)
            // backwards cap: dome + brim pointing back (left), white S
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: -w * 0.34, y: 0))
                    p.addQuadCurve(to: CGPoint(x: w * 0.34, y: 0),
                                   control: CGPoint(x: 0, y: -h * 0.30))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [capRed, capDark], startPoint: .top, endPoint: .bottom))
                // brim at the back
                RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                    .fill(capDark)
                    .frame(width: w * 0.34, height: h * 0.055)
                    .offset(x: -w * 0.44, y: h * 0.015)
                Text("S")
                    .font(.system(size: w * 0.17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(y: -h * 0.075)
            }
            .offset(y: -h * 0.335)
            .rotationEffect(.degrees(-6))
        }
        .frame(width: w, height: h)
        .offset(y: bobOffset)
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: mood)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true }
        }
    }

    private var shoe: some View {
        RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
            .fill(LinearGradient(colors: [blue, blueDark], startPoint: .top, endPoint: .bottom))
            .frame(width: size * 0.26, height: size * 0.13)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2).fill(Color.white)
                    .frame(height: size * 0.035)
            }
    }

    private func armY(left: Bool) -> CGFloat {
        switch mood {
        case .celebrate, .bigPlay: return -size * 0.34   // arms up
        case .ouch: return size * 0.30                    // arms slumped
        default: return size * 0.08
        }
    }

    private var bobOffset: CGFloat {
        switch mood {
        case .celebrate, .bigPlay: return bob ? -size * 0.13 : 0
        case .ouch: return size * 0.03
        default: return bob ? -size * 0.03 : size * 0.01
        }
    }

    @ViewBuilder
    private var face: some View {
        let w = size
        ZStack {
            // cheeks
            HStack(spacing: w * 0.34) {
                Circle().fill(Color(red: 1, green: 0.55, blue: 0.65).opacity(0.55))
                Circle().fill(Color(red: 1, green: 0.55, blue: 0.65).opacity(0.55))
            }
            .frame(width: w * 0.52, height: w * 0.11)
            .offset(y: w * 0.055)
            // eyes
            HStack(spacing: w * 0.13) {
                eye; eye
            }
            .offset(y: -w * 0.05)
            // mouth
            mouth.offset(y: w * 0.10)
        }
    }

    @ViewBuilder
    private var eye: some View {
        let w = size
        if mood == .bigPlay {
            StarShape().fill(TilePalette.bolt)
                .frame(width: w * 0.17, height: w * 0.17)
        } else if mood == .ouch {
            ZStack {
                Capsule().fill(Color(red: 0.05, green: 0.1, blue: 0.25))
                    .frame(width: w * 0.15, height: w * 0.028)
                    .rotationEffect(.degrees(38))
                Capsule().fill(Color(red: 0.05, green: 0.1, blue: 0.25))
                    .frame(width: w * 0.15, height: w * 0.028)
                    .rotationEffect(.degrees(-38))
            }
            .frame(width: w * 0.16, height: w * 0.16)
        } else {
            ZStack {
                Ellipse().fill(Color.white)
                    .frame(width: w * 0.155, height: w * 0.19)
                Circle().fill(Color(red: 0.05, green: 0.08, blue: 0.2))
                    .frame(width: w * 0.085, height: w * 0.085)
                    .offset(x: mood == .thinking ? w * 0.028 : 0, y: w * 0.012)
                Circle().fill(Color.white)
                    .frame(width: w * 0.032, height: w * 0.032)
                    .offset(x: (mood == .thinking ? w * 0.028 : 0) - w * 0.018, y: -w * 0.012)
            }
        }
    }

    @ViewBuilder
    private var mouth: some View {
        let w = size
        switch mood {
        case .celebrate, .bigPlay:
            // open grin with tongue
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: -w * 0.13, y: 0))
                    p.addQuadCurve(to: CGPoint(x: w * 0.13, y: 0),
                                   control: CGPoint(x: 0, y: w * 0.20))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.16, green: 0.05, blue: 0.10))
                Ellipse().fill(Color(red: 1, green: 0.45, blue: 0.55))
                    .frame(width: w * 0.13, height: w * 0.055)
                    .offset(y: w * 0.052)
            }
        case .ouch:
            Circle().fill(Color(red: 0.16, green: 0.05, blue: 0.10))
                .frame(width: w * 0.07, height: w * 0.07)
        case .thinking:
            Capsule().fill(Color(red: 0.05, green: 0.1, blue: 0.25))
                .frame(width: w * 0.13, height: w * 0.026)
        case .idle:
            Path { p in
                p.move(to: CGPoint(x: -w * 0.11, y: 0))
                p.addQuadCurve(to: CGPoint(x: w * 0.11, y: 0),
                               control: CGPoint(x: 0, y: w * 0.11))
            }
            .stroke(Color(red: 0.05, green: 0.1, blue: 0.25),
                    style: StrokeStyle(lineWidth: w * 0.028, lineCap: .round))
        }
    }
}

/// Original shape-drawn versus avatars (no emoji, no stock): Player 1
/// with glasses like the ad; the CPU with pink hair and headphones.
struct AvatarView: View {
    let isCPU: Bool
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            if isCPU {
                // pink hair mass behind the face
                Circle().fill(Color(red: 1.0, green: 0.55, blue: 0.75))
                    .frame(width: size, height: size)
            }
            Circle()
                .fill(Color(red: 0.98, green: 0.80, blue: 0.64))
                .frame(width: size * (isCPU ? 0.78 : 0.88), height: size * (isCPU ? 0.78 : 0.88))
                .offset(y: isCPU ? size * 0.06 : 0)
            if isCPU {
                // hair fringe
                Path { p in
                    let r = size * 0.39
                    p.move(to: CGPoint(x: -r, y: -r * 0.25))
                    p.addQuadCurve(to: CGPoint(x: r, y: -r * 0.25),
                                   control: CGPoint(x: 0, y: -r * 1.15))
                    p.addQuadCurve(to: CGPoint(x: -r, y: -r * 0.25),
                                   control: CGPoint(x: 0, y: r * 0.28))
                    p.closeSubpath()
                }
                .fill(Color(red: 1.0, green: 0.45, blue: 0.68))
                .offset(y: size * 0.02)
                // headphones
                HStack(spacing: size * 0.62) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.15, green: 0.15, blue: 0.3))
                        .frame(width: size * 0.16, height: size * 0.3)
                    RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.15, green: 0.15, blue: 0.3))
                        .frame(width: size * 0.16, height: size * 0.3)
                }
            } else {
                // brown hair sweep
                Path { p in
                    let r = size * 0.44
                    p.move(to: CGPoint(x: -r, y: -r * 0.1))
                    p.addQuadCurve(to: CGPoint(x: r, y: -r * 0.1),
                                   control: CGPoint(x: 0, y: -r * 1.2))
                    p.addQuadCurve(to: CGPoint(x: -r, y: -r * 0.1),
                                   control: CGPoint(x: 0, y: r * 0.42))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.36, green: 0.22, blue: 0.12))
                // glasses
                HStack(spacing: size * 0.05) {
                    RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.1, green: 0.1, blue: 0.18), lineWidth: 1.6)
                        .frame(width: size * 0.26, height: size * 0.22)
                    RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.1, green: 0.1, blue: 0.18), lineWidth: 1.6)
                        .frame(width: size * 0.26, height: size * 0.22)
                }
                .offset(y: size * 0.02)
            }
            // eyes + smile
            VStack(spacing: size * 0.10) {
                HStack(spacing: size * 0.20) {
                    Circle().fill(Color(red: 0.08, green: 0.06, blue: 0.1))
                        .frame(width: size * 0.07, height: size * 0.07)
                    Circle().fill(Color(red: 0.08, green: 0.06, blue: 0.1))
                        .frame(width: size * 0.07, height: size * 0.07)
                }
                Path { p in
                    p.move(to: CGPoint(x: -size * 0.09, y: 0))
                    p.addQuadCurve(to: CGPoint(x: size * 0.09, y: 0),
                                   control: CGPoint(x: 0, y: size * 0.09))
                }
                .stroke(Color(red: 0.3, green: 0.15, blue: 0.1),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            .offset(y: size * 0.10)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2))
    }
}
