import SwiftUI

/// The crossword board: dark grid, glossy set tiles, bonus squares, the
/// drag target highlight and the live-word glow. Fills the width it is
/// given; height follows the 8×12 grid. Camera transforms are applied
/// by the parent — this view is pure board.
struct BoardView: View {
    @EnvironmentObject var vm: GameViewModel

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CGFloat(PuzzleGenerator.cols)
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.07, blue: 0.16))
                VStack(spacing: 2) {
                    ForEach(0..<PuzzleGenerator.rows, id: \.self) { r in
                        HStack(spacing: 2) {
                            ForEach(0..<PuzzleGenerator.cols, id: \.self) { c in
                                cellView(idx: r * PuzzleGenerator.cols + c, size: cell - 2)
                            }
                        }
                    }
                }
                .padding(5)
            }
        }
        .aspectRatio(CGFloat(PuzzleGenerator.cols) / CGFloat(PuzzleGenerator.rows), contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LinearGradient(colors: [TilePalette.bolt, Color(red: 0.85, green: 0.55, blue: 0.05)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 3.5)
        )
        .modifier(ShakeEffect(animatableData: CGFloat(vm.shakeTick)))
        .animation(.easeInOut(duration: 0.32), value: vm.shakeTick)
    }

    @ViewBuilder
    private func cellView(idx: Int, size: CGFloat) -> some View {
        let cell = vm.puzzle.cells[idx]
        let filledCell = idx < vm.filled.count ? vm.filled[idx] : nil
        let isHover = vm.hoverCell == idx && vm.isDroppable(idx)
        let inLiveWord = vm.liveWordCells.contains(idx)
        let isPickup = vm.pickupIdx == idx
        ZStack {
            switch cell.kind {
            case .blank:
                RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.11, blue: 0.24))
            case .clue:
                RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                    .fill(Color(red: 0.02, green: 0.03, blue: 0.07))
                Circle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: size * 0.14, height: size * 0.14)
            case .letter:
                RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.14, blue: 0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                            .strokeBorder(cell.isBonus ? TilePalette.brandBlue : Color.white.opacity(0.14),
                                          lineWidth: cell.isBonus ? 2 : 1)
                    )
                if cell.isBonus && filledCell == nil {
                    BoltShape()
                        .fill(TilePalette.bolt)
                        .frame(width: size * 0.34, height: size * 0.44)
                        .opacity(0.9)
                }
            }
            if let filledCell {
                TileView(letter: filledCell.letter, size: size, owner: filledCell.by)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            if isHover {
                RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2.5)
                    .background(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                        .fill(Color.white.opacity(0.18)))
            } else if inLiveWord && filledCell == nil {
                RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                    .strokeBorder(TilePalette.bolt.opacity(0.85), lineWidth: 1.8)
            }
            if isPickup {
                RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                    .scaleEffect(1.06)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { vm.tapCell(idx) }
        .gesture(pickupGesture(idx: idx, filledCell: filledCell))
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: vm.filled[idx]?.letter)
    }

    /// The just-set tile can be dragged straight back off the board.
    private func pickupGesture(idx: Int, filledCell: MatchEngine.FilledCell?) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("game"))
            .onChanged { value in
                if vm.pickupIdx == idx && filledCell?.by == .you {
                    if vm.drag == nil { vm.beginDrag(source: .board(idx), at: value.location) }
                    else { vm.updateDrag(at: value.location) }
                }
            }
            .onEnded { _ in if vm.drag != nil { vm.endDrag() } }
    }
}

/// Horizontal shake for rejected placements (geometry-effect, no layout cost).
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 5
    var shakes: CGFloat = 3
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * shakes), y: 0))
    }
}
