import SwiftUI

/// The crossword board: dark grid, glossy set tiles, bonus squares, the
/// drag target highlight and the live-word glow.
///
/// Sizing has exactly one source: GameScreen's GameLayout computes the
/// cell size from the real screen size and hands it in. This view never
/// measures itself (build 7 wrapped the grid in a GeometryReader inside
/// an aspect-ratio frame inside another aspect-ratio slot — three
/// competing answers for "how big is the board", and the rendered board
/// came out thumbnail-sized with its gold frame offset from its grid).
/// The grid is the web app's: 8×12 cells, 3pt gaps, no inner padding,
/// so the drawn board, its frame and the view model's boardRect are
/// always the same rectangle. Camera transforms are applied by the
/// parent — this view is pure board.
struct BoardView: View {
    @EnvironmentObject var vm: GameViewModel
    /// Edge length of one cell in points, computed by GameLayout.
    let cell: CGFloat

    /// The web board's grid gap (`#board { gap: 3px }`).
    static let gap: CGFloat = 3

    static func boardSize(cell: CGFloat) -> CGSize {
        CGSize(width: cell * CGFloat(PuzzleGenerator.cols) + gap * CGFloat(PuzzleGenerator.cols - 1),
               height: cell * CGFloat(PuzzleGenerator.rows) + gap * CGFloat(PuzzleGenerator.rows - 1))
    }

    var body: some View {
        let size = Self.boardSize(cell: cell)
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.05, green: 0.07, blue: 0.16))
            VStack(spacing: Self.gap) {
                ForEach(0..<PuzzleGenerator.rows, id: \.self) { r in
                    HStack(spacing: Self.gap) {
                        ForEach(0..<PuzzleGenerator.cols, id: \.self) { c in
                            cellView(idx: r * PuzzleGenerator.cols + c, size: cell)
                        }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
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
        let radius = max(3, size * 0.11)
        ZStack {
            switch cell.kind {
            case .blank:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.11, blue: 0.24))
            case .clue:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(red: 0.02, green: 0.03, blue: 0.07))
                Circle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: size * 0.14, height: size * 0.14)
            case .letter:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.14, blue: 0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
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
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2.5)
                    .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.white.opacity(0.18)))
            } else if inLiveWord && filledCell == nil {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(TilePalette.bolt.opacity(0.85), lineWidth: 1.8)
            }
            if isPickup {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
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
                    else if vm.dragOriginCell == idx { vm.updateDrag(at: value.location) }
                }
            }
            // Only the cell the drag was picked up from may end it —
            // any other cell's finger lifting used to drop the tile
            // early (Claude audit, 2026-11-19).
            .onEnded { _ in if vm.dragOriginCell == idx { vm.endDrag() } }
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
