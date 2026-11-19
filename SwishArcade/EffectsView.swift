import SwiftUI

/// Deterministic 0…1 hash so particles are stable across redraws.
private func hash01(_ i: Int, _ seed: Int) -> Double {
    let x = sin(Double(i * 127 + seed * 311) * 12.9898) * 43758.5453
    return x - floor(x)
}

/// The ad's purple lightning-energy backdrop: deep violet gradient,
/// drifting glow blobs and a field of tiny sparks. All cheap shapes.
struct EnergyBackground: View {
    @State private var drift = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.02, blue: 0.22),
                                    Color(red: 0.24, green: 0.05, blue: 0.45),
                                    Color(red: 0.07, green: 0.01, blue: 0.14)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(red: 0.55, green: 0.2, blue: 1.0).opacity(0.35))
                .frame(width: 260, height: 260).blur(radius: 70)
                .offset(x: drift ? -90 : -130, y: -260)
            Circle().fill(Color(red: 0.1, green: 0.5, blue: 1.0).opacity(0.30))
                .frame(width: 220, height: 220).blur(radius: 70)
                .offset(x: drift ? 130 : 90, y: 240)
            GeometryReader { geo in
                ForEach(0..<26, id: \.self) { i in
                    Circle().fill(Color.white.opacity(0.25 + hash01(i, 7) * 0.4))
                        .frame(width: CGFloat(2 + hash01(i, 8) * 2.5), height: CGFloat(2 + hash01(i, 8) * 2.5))
                        .position(x: hash01(i, 9) * geo.size.width,
                                  y: hash01(i, 10) * geo.size.height)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// Full-screen effects overlay (game coordinate space): score floaters
/// that pop at the set cell and fly up to the HUD, particle bursts, the
/// dragged tile, returning tiles, and the win confetti rain.
struct EffectsLayer: View {
    @EnvironmentObject var vm: GameViewModel

    var body: some View {
        ZStack {
            ForEach(vm.bursts) { burst in
                ParticleBurstView(burst: burst)
            }
            ForEach(vm.floaters) { floater in
                ScoreFloaterView(floater: floater, boardTop: vm.boardRect.minY)
            }
            ForEach(vm.returningTiles) { tile in
                ReturningTileView(tile: tile)
            }
            if vm.confettiRain {
                ConfettiRainView()
            }
            if let drag = vm.drag {
                TileView(letter: drag.letter, size: vm.cellSize * 1.9)
                    .scaleEffect(1.12)
                    .shadow(color: .black.opacity(0.5), radius: 14, x: 0, y: 10)
                    .position(drag.location)
                    .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.55),
                               value: drag.location)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ScoreFloaterView: View {
    let floater: ScoreFloater
    let boardTop: CGFloat
    var body: some View {
        TimelineView(.animation) { timeline in
            let p = min(1, timeline.date.timeIntervalSince(floater.born) / 1.05)
            let ease = 1 - pow(1 - p, 3)
            let rise = 120 * ease
            let driftX: Double = (p < 0.55) ? 0 : (p - 0.55) * 60 * (floater.side == .you ? -1.0 : 1.0)
            let scale = floater.big ? (p < 0.18 ? 0.5 + p / 0.18 * 0.9 : 1.4 - 0.35 * p) : 1.0
            let opacity = p > 0.72 ? 1 - (p - 0.72) / 0.28 : 1.0
            Text(floater.text)
                .font(.system(size: floater.big ? 25 : 17, weight: .black, design: .rounded))
                .foregroundStyle(floater.side == .you
                    ? TilePalette.bolt
                    : Color(red: 1.0, green: 0.45, blue: 0.55))
                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 2)
                .scaleEffect(scale)
                .opacity(opacity)
                .position(x: floater.from.x + driftX, y: floater.from.y - rise)
        }
    }
}

private struct ReturningTileView: View {
    let tile: ReturningTile
    var body: some View {
        TimelineView(.animation) { timeline in
            let p = min(1, timeline.date.timeIntervalSince(tile.born) / 0.38)
            let ease = 1 - pow(1 - p, 3)
            let pos = CGPoint(x: tile.from.x + (tile.to.x - tile.from.x) * ease,
                              y: tile.from.y + (tile.to.y - tile.from.y) * ease - sin(p * .pi) * 26)
            TileView(letter: tile.letter, size: 40)
                .position(pos)
                .opacity(p > 0.9 ? 0 : 1)
        }
    }
}

private struct ParticleBurstView: View {
    let burst: ParticleBurst
    var body: some View {
        TimelineView(.animation) { timeline in
            let p = min(1, timeline.date.timeIntervalSince(burst.born) / 0.8)
            let seed = burst.id.hashValue
            ZStack {
                ForEach(0..<particleCount, id: \.self) { i in
                    particle(i: i, seed: seed, p: p)
                }
            }
        }
    }

    private var particleCount: Int {
        switch burst.kind { case .spark: return 12; case .wordBurst: return 22; case .coins: return 14 }
    }

    @ViewBuilder
    private func particle(i: Int, seed: Int, p: Double) -> some View {
        let angle = hash01(i, seed) * Double.pi * 2
        let speed = 40 + hash01(i, seed + 1) * (burst.kind == .coins ? 130 : 95)
        let dx = cos(angle) * speed * p
        let dy = sin(angle) * speed * p + 130 * p * p   // gravity
        let size = 4 + hash01(i, seed + 2) * 6
        let pos = CGPoint(x: burst.center.x + dx, y: burst.center.y + dy)
        let opacity = 1 - p
        Group {
            if burst.kind == .coins {
                Circle().fill(TilePalette.bolt)
                    .overlay(Circle().strokeBorder(Color(red: 0.8, green: 0.58, blue: 0), lineWidth: 1.2))
                    .frame(width: size * 1.5, height: size * 1.5)
            } else if i % 3 == 0 {
                StarShape().fill(TilePalette.bolt)
                    .frame(width: size * 1.6, height: size * 1.6)
            } else {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(TilePalette.swatches[i % TilePalette.swatches.count].base)
                    .frame(width: size, height: size * 0.62)
                    .rotationEffect(.degrees(hash01(i, seed + 3) * 360 + p * 260))
            }
        }
        .position(pos)
        .opacity(opacity)
    }
}

/// The win moment: confetti, stars and coins falling over the board.
private struct ConfettiRainView: View {
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<44, id: \.self) { i in
                        let speed = 60 + hash01(i, 21) * 90
                        let cycle = geo.size.height + 60
                        let y = (hash01(i, 22) * cycle + t * speed).truncatingRemainder(dividingBy: cycle) - 30
                        let x = hash01(i, 23) * geo.size.width + sin(t * 1.6 + Double(i)) * 16
                        piece(i: i)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func piece(i: Int) -> some View {
        if i % 5 == 0 {
            Circle().fill(TilePalette.bolt)
                .overlay(Circle().strokeBorder(Color(red: 0.8, green: 0.58, blue: 0), lineWidth: 1))
                .frame(width: 13, height: 13)
        } else if i % 4 == 0 {
            StarShape().fill(TilePalette.bolt).frame(width: 13, height: 13)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(TilePalette.swatches[i % TilePalette.swatches.count].base)
                .frame(width: 9, height: 6)
                .rotationEffect(.degrees(hash01(i, 24) * 360))
        }
    }
}
