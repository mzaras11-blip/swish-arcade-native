import SwiftUI

/// The tile color system: six glossy colors, assigned per letter so a
/// letter always wears the same color on the rack and on the board.
enum TilePalette {
    struct Swatch { let base: Color; let light: Color; let dark: Color }
    static let swatches: [Swatch] = [
        Swatch(base: Color(red: 0.12, green: 0.61, blue: 1.00),   // brand blue #1E9BFF family
               light: Color(red: 0.49, green: 0.79, blue: 1.00),
               dark: Color(red: 0.04, green: 0.44, blue: 0.84)),
        Swatch(base: Color(red: 1.00, green: 0.36, blue: 0.54),   // pink
               light: Color(red: 1.00, green: 0.62, blue: 0.75),
               dark: Color(red: 0.84, green: 0.20, blue: 0.42)),
        Swatch(base: Color(red: 1.00, green: 0.62, blue: 0.18),   // orange
               light: Color(red: 1.00, green: 0.77, blue: 0.42),
               dark: Color(red: 0.88, green: 0.48, blue: 0.00)),
        Swatch(base: Color(red: 0.24, green: 0.84, blue: 0.60),   // green
               light: Color(red: 0.55, green: 0.94, blue: 0.76),
               dark: Color(red: 0.07, green: 0.66, blue: 0.40)),
        Swatch(base: Color(red: 0.61, green: 0.36, blue: 1.00),   // purple
               light: Color(red: 0.78, green: 0.61, blue: 1.00),
               dark: Color(red: 0.43, green: 0.16, blue: 0.85)),
        Swatch(base: Color(red: 1.00, green: 0.79, blue: 0.24),   // gold
               light: Color(red: 1.00, green: 0.88, blue: 0.54),
               dark: Color(red: 0.88, green: 0.63, blue: 0.00)),
    ]
    static func index(for letter: Character) -> Int {
        let v = letter.unicodeScalars.first?.value ?? 65
        return Int(v - 65) % swatches.count
    }
    static let cpuSwatch = Swatch(base: Color(red: 0.56, green: 0.16, blue: 0.24),
                                  light: Color(red: 0.72, green: 0.30, blue: 0.38),
                                  dark: Color(red: 0.37, green: 0.09, blue: 0.15))
    static let bolt = Color(red: 247.0 / 255, green: 195.0 / 255, blue: 22.0 / 255)
    static let brandBlue = Color(red: 0.12, green: 0.61, blue: 1.00)
}

/// A glossy, chunky 3D-style letter tile — the ad's signature object.
/// Layered gradients + a top gloss stripe + a shaded bottom edge fake
/// the molded-plastic depth; all drawn in code, no image assets.
struct TileView: View {
    let letter: Character
    var size: CGFloat
    var owner: Side? = .you     // nil = neutral rack tile (bright, by letter)
    var ghost: Bool = false

    private var swatch: TilePalette.Swatch {
        owner == .cpu ? TilePalette.cpuSwatch
                      : TilePalette.swatches[TilePalette.index(for: letter)]
    }

    var body: some View {
        let sw = swatch
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [sw.light, sw.base, sw.dark],
                                     startPoint: .top, endPoint: .bottom))
            // bottom edge shade (the chunk)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(sw.dark.opacity(0.9), lineWidth: max(1, size * 0.045))
            // top gloss
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.05)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: size * 0.42)
                .offset(y: -size * 0.22)
                .padding(.horizontal, size * 0.1)
            Text(String(letter))
                .font(.system(size: size * 0.52, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: size * 0.035)
        }
        .frame(width: size, height: size)
        .opacity(ghost ? 0.35 : 1)
        .shadow(color: .black.opacity(0.35), radius: size * 0.06, x: 0, y: size * 0.05)
    }
}

/// The yellow S-bolt, drawn as a polygon — brand mark, never an emoji.
struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 0.58 * w, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + 0.16 * w, y: rect.minY + 0.56 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.42 * w, y: rect.minY + 0.56 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.34 * w, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + 0.86 * w, y: rect.minY + 0.40 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.58 * w, y: rect.minY + 0.40 * h))
        p.closeSubpath()
        return p
    }
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.45
        for i in 0..<10 {
            let angle = Double(i) * Double.pi / 5 - Double.pi / 2
            let r = i % 2 == 0 ? outer : inner
            let pt = CGPoint(x: cx + CGFloat(cos(angle)) * r, y: cy + CGFloat(sin(angle)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct CrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 0.25 * h))
        p.addLine(to: CGPoint(x: rect.minX + 0.28 * w, y: rect.minY + 0.55 * h))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + 0.72 * w, y: rect.minY + 0.55 * h))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 0.25 * h))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
