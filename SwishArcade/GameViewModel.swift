import SwiftUI

enum GamePhase { case menu, playing, over }
enum MascotMood {
    case idle
    case celebrate
    case bigPlay
    case ouch
    case thinking
}

enum DragSource: Equatable { case rack(Int), board(Int) }

struct DragState {
    let letter: Character
    var source: DragSource
    var location: CGPoint
    var startedAt: Date = Date()
}

/// A tile flying back to its rack slot after a rejected or cancelled drag.
struct ReturningTile: Identifiable {
    let id = UUID()
    let letter: Character
    let from: CGPoint
    let to: CGPoint
    let born: Date = Date()
}

/// "+120" style score label that pops at a cell and flies to the HUD.
struct ScoreFloater: Identifiable {
    let id = UUID()
    let text: String
    let from: CGPoint          // game-space point at the set cell
    let side: Side
    let big: Bool
    let born: Date = Date()
}

enum BurstKind { case spark, wordBurst, coins }
struct ParticleBurst: Identifiable {
    let id = UUID()
    let center: CGPoint        // game-space
    let kind: BurstKind
    let born: Date = Date()
}

@MainActor
final class GameViewModel: ObservableObject {
    // Board / match state (mirrored from the engine)
    @Published var puzzle: Puzzle
    @Published var filled: [MatchEngine.FilledCell?] = []
    @Published var rack: [Character?] = []
    @Published var scores: [Side: Int] = [.you: 0, .cpu: 0]
    @Published var displayedScores: [Side: Int] = [.you: 0, .cpu: 0]
    @Published var comboMult = 1
    @Published var comboTier = MatchEngine.comboTiers[0]
    @Published var comboFrac = 0.0        // 1 → 0 drain of the combo window
    @Published var comboSurge = 0         // bump to retrigger the surge animation
    @Published var cpuComboMult = 1
    @Published var hintsLeft = MatchEngine.hintsPerMatch
    @Published var bombsLeft = MatchEngine.bombsPerMatch
    @Published var shufflesLeft = MatchEngine.shufflesPerMatch
    @Published var timeLeftMs = MatchEngine.matchSeconds * 1000
    @Published var cpuThinking = false
    @Published var winner: Side? = nil
    @Published var phase: GamePhase = .menu
    @Published var difficulty = "normal"

    // Interaction state
    @Published var drag: DragState? = nil
    @Published var hoverCell: Int? = nil
    @Published var selectedSlot: Int? = nil
    @Published var bombArmed = false
    @Published var returningTiles: [ReturningTile] = []
    @Published var pickupIdx: Int? = nil

    // Juice state
    @Published var floaters: [ScoreFloater] = []
    @Published var bursts: [ParticleBurst] = []
    @Published var bannerText: String? = nil
    @Published var bannerBolt = false
    @Published var mascotMood: MascotMood = .idle
    @Published var confettiRain = false
    @Published var shakeTick = 0

    // Camera state (transform-only: scale + anchor on the board container)
    @Published var cameraScale = 1.0
    @Published var cameraAnchor = UnitPoint(x: 0.5, y: 0.45)
    private var cameraGeneration = 0

    // Geometry, fed by the views
    var boardRect: CGRect = .zero
    var rackRect: CGRect = .zero

    private var engine: MatchEngine?
    private var suppressPlaceSound = false
    private var moodTask: Task<Void, Never>?
    private var lastPlaceIdx: Int? = nil

    init() {
        puzzle = PuzzleGenerator.generate()
        filled = [MatchEngine.FilledCell?](repeating: nil, count: PuzzleGenerator.cellCount)
    }

    private func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

    // MARK: - Match lifecycle

    func startMatch() {
        puzzle = PuzzleGenerator.generate()
        let match = MatchEngine(puzzle: puzzle, difficultyKey: difficulty)
        engine = match
        match.onEvent = { [weak self] event in self?.handle(event) }
        winner = nil
        bannerText = nil
        confettiRain = false
        bombArmed = false
        selectedSlot = nil
        drag = nil
        floaters = []
        bursts = []
        displayedScores = [.you: 0, .cpu: 0]
        mascotMood = .idle
        cameraRest(animate: false)
        phase = .playing
        Haptics.prepare()
        match.start(now: nowMs())
        syncFromEngine()
    }

    func tick() {
        guard phase == .playing, let engine else { return }
        engine.tick(now: nowMs())
        syncFromEngine()
        // Tween the HUD scores toward the real ones (points "arrive").
        for side in [Side.you, Side.cpu] {
            let target = scores[side] ?? 0
            var shown = displayedScores[side] ?? 0
            if shown < target { shown = min(target, shown + max(1, (target - shown) / 4)) }
            displayedScores[side] = shown
        }
        // Combo drain bar.
        if let last = engine.combo[.you]?.lastAt {
            comboFrac = max(0, 1 - (nowMs() - last) / MatchEngine.comboWindowMs)
        } else { comboFrac = 0 }
        cpuThinking = engine.cpuIsThinking
        pickupIdx = engine.pickupCandidate(now: nowMs())
        // Expire effects.
        let cutoff = Date().addingTimeInterval(-1.15)
        floaters.removeAll { $0.born < cutoff }
        bursts.removeAll { $0.born < Date().addingTimeInterval(-0.9) }
        returningTiles.removeAll { $0.born < Date().addingTimeInterval(-0.4) }
    }

    private func syncFromEngine() {
        guard let engine else { return }
        filled = engine.filled
        rack = engine.racks[.you] ?? []
        scores = engine.scores
        comboMult = engine.combo[.you]?.mult ?? 1
        comboTier = MatchEngine.comboTiers[comboMult - 1]
        cpuComboMult = engine.combo[.cpu]?.mult ?? 1
        hintsLeft = engine.hintsLeft
        bombsLeft = engine.bombsLeft
        shufflesLeft = engine.shufflesLeft
        timeLeftMs = engine.timeLeft(now: nowMs())
        if engine.over { winner = engine.winner }
    }

    // MARK: - Engine events → juice

    private func handle(_ event: MatchEvent) {
        switch event {
        case .place(let side, let idx, _, let points, _):
            lastPlaceIdx = idx
            if !suppressPlaceSound { side == .you ? SoundFX.shared.set() : SoundFX.shared.pop() }
            if side == .you {
                spawnFloater("+\(points)", at: idx, side: .you, big: false)
                cameraWordFocus(idx: idx, punch: false)
            }
            syncFromEngine()
        case .wrong(let side, _, _):
            if side == .you {
                Haptics.reject()
                SoundFX.shared.wrong()
                shakeTick += 1
                flashMood(.ouch)
                cameraRestSoon()
            }
            syncFromEngine()
        case .word(let side, _, let answer, let idxs, let bonus, _, let doubled):
            let center = centroid(of: idxs)
            if side == .you {
                Haptics.word()
                SoundFX.shared.word()
                spawnFloater("WORD +\(bonus)", atPoint: center, side: .you, big: true)
                spawnBurst(at: center, kind: .wordBurst)
                if doubled {
                    showBanner("DOUBLE WORD SCORE", bolt: true)
                    cameraPunch(anchor: anchorOf(center))
                } else {
                    cameraPunch(anchor: anchorOf(center))
                }
                flashMood(bonus >= 60 || doubled ? .bigPlay : .celebrate)
            } else {
                spawnFloater("\(answer) +\(bonus)", atPoint: center, side: .cpu, big: false)
                flashMood(.ouch)
            }
            syncFromEngine()
        case .comboUp(let side, let mult, _):
            if side == .you {
                comboSurge += 1
                Haptics.comboUp()
                SoundFX.shared.combo()
                if let idx = lastPlaceIdx {
                    spawnFloater("COMBO ×\(mult)", at: idx, side: .you, big: mult >= 5)
                }
                if mult >= 5 { showBanner("COMBO MASTER", bolt: false); flashMood(.bigPlay) }
            }
            syncFromEngine()
        case .comboExpire, .comboBreak:
            syncFromEngine()
        case .hint(let idx, _):
            spawnFloater("HINT", at: idx, side: .you, big: false)
            cameraWordFocus(idx: idx, punch: false)
            syncFromEngine()
        case .bomb(let center, _, _):
            SoundFX.shared.bomb()
            Haptics.word()
            spawnBurst(at: cellCenter(center), kind: .wordBurst)
            cameraPunch(anchor: anchorOf(cellCenter(center)))
            syncFromEngine()
        case .shuffle:
            SoundFX.shared.pop()
            syncFromEngine()
        case .pickup:
            SoundFX.shared.pickup()
            syncFromEngine()
        case .cpuAct:
            syncFromEngine()
        case .end(let winnerSide, _, _, _):
            phase = .over
            winner = winnerSide
            drag = nil
            if winnerSide == .you {
                SoundFX.shared.win()
                Haptics.win()
                confettiRain = true
                mascotMood = .celebrate
                showBanner("YOU WIN!", bolt: false)
                cameraWinPose()
                spawnBurst(at: CGPoint(x: boardRect.midX, y: boardRect.midY), kind: .coins)
            } else {
                mascotMood = .ouch
                cameraRest()
            }
            syncFromEngine()
        case .start:
            syncFromEngine()
        }
    }

    // MARK: - Player actions (buttons + tap path)

    func tapRackSlot(_ slot: Int) {
        guard phase == .playing else { return }
        selectedSlot = (selectedSlot == slot) ? nil : slot
        if selectedSlot != nil { Haptics.lift() }
    }

    func tapCell(_ idx: Int) {
        guard phase == .playing, let engine else { return }
        if bombArmed {
            bombArmed = false
            suppressPlaceSound = true
            _ = engine.useBomb(centerIdx: idx, now: nowMs())
            suppressPlaceSound = false
            syncFromEngine()
            return
        }
        if idx == pickupIdx {
            _ = engine.pickupLastPlacement(now: nowMs())
            syncFromEngine()
            return
        }
        if let slot = selectedSlot {
            _ = engine.attemptPlace(side: .you, rackSlot: slot, idx: idx, now: nowMs())
            selectedSlot = nil
            syncFromEngine()
        }
    }

    func useHint() {
        guard let engine, phase == .playing else { return }
        suppressPlaceSound = true
        _ = engine.useHint(now: nowMs())
        suppressPlaceSound = false
        SoundFX.shared.pop()
        syncFromEngine()
    }

    func armBomb() {
        guard bombsLeft > 0, phase == .playing else { return }
        bombArmed.toggle()
    }

    func useShuffle() {
        guard let engine, phase == .playing else { return }
        selectedSlot = nil
        _ = engine.useShuffle(now: nowMs())
        syncFromEngine()
    }

    // MARK: - Drag (the primary interaction)

    func beginDrag(source: DragSource, at location: CGPoint) {
        guard phase == .playing, let engine else { return }
        var source = source
        if case .board(let idx) = source {
            // Pick the just-set tile back up; the drag continues as a rack drag.
            guard let picked = engine.pickupLastPlacement(now: nowMs()) else { return }
            source = .rack(picked.slot)
            syncFromEngine()
        }
        guard case .rack(let slot) = source, let letter = rackValue(slot) else { return }
        drag = DragState(letter: letter, source: source, location: location)
        selectedSlot = nil
        Haptics.lift()
        updateHover(at: location)
    }

    func updateDrag(at location: CGPoint) {
        guard drag != nil else { return }
        drag?.location = location
        updateHover(at: location)
    }

    func endDrag() {
        guard let drag, let engine else { self.drag = nil; return }
        let slot: Int
        if case .rack(let s) = drag.source { slot = s } else { slot = 0 }
        let target = hoverCell
        self.drag = nil
        hoverCell = nil
        if bombArmed, let target {
            bombArmed = false
            suppressPlaceSound = true
            _ = engine.useBomb(centerIdx: target, now: nowMs())
            suppressPlaceSound = false
            syncFromEngine()
            return
        }
        if let target, isDroppable(target) {
            let ok = engine.attemptPlace(side: .you, rackSlot: slot, idx: target, now: nowMs())
            if ok {
                Haptics.tileSet()
                syncFromEngine()
                return
            }
        }
        // Rejected or off-board: the tile springs back to its rack slot.
        returningTiles.append(ReturningTile(letter: drag.letter, from: drag.location,
                                            to: rackSlotCenter(slot)))
        cameraRestSoon()
        syncFromEngine()
    }

    func cancelDrag() {
        if let drag, case .rack(let slot) = drag.source {
            returningTiles.append(ReturningTile(letter: drag.letter, from: drag.location,
                                                to: rackSlotCenter(slot)))
        }
        self.drag = nil
        hoverCell = nil
        cameraRestSoon()
    }

    private func rackValue(_ slot: Int) -> Character? {
        guard slot >= 0 && slot < rack.count else { return nil }
        return rack[slot]
    }

    private func updateHover(at location: CGPoint) {
        let idx = cellIndex(at: location)
        if idx != hoverCell {
            hoverCell = idx
            if let idx, isDroppable(idx) {
                cameraDragFocus(idx: idx)
            }
        }
    }

    func isDroppable(_ idx: Int) -> Bool {
        puzzle.cells[idx].kind == .letter && filled[idx] == nil
    }

    // MARK: - Geometry helpers (game coordinate space)

    var cellSize: CGFloat { boardRect.width > 0 ? boardRect.width / CGFloat(PuzzleGenerator.cols) : 0 }

    func cellCenter(_ idx: Int) -> CGPoint {
        let cs = cellSize
        let r = idx / PuzzleGenerator.cols, c = idx % PuzzleGenerator.cols
        return CGPoint(x: boardRect.minX + (CGFloat(c) + 0.5) * cs,
                       y: boardRect.minY + (CGFloat(r) + 0.5) * cs)
    }

    func cellIndex(at point: CGPoint) -> Int? {
        guard boardRect.width > 0, boardRect.contains(point) else { return nil }
        let c = Int((point.x - boardRect.minX) / cellSize)
        let r = Int((point.y - boardRect.minY) / cellSize)
        guard r >= 0, r < PuzzleGenerator.rows, c >= 0, c < PuzzleGenerator.cols else { return nil }
        return r * PuzzleGenerator.cols + c
    }

    func rackSlotCenter(_ slot: Int) -> CGPoint {
        guard rackRect.width > 0 else { return .zero }
        let w = rackRect.width / CGFloat(MatchEngine.rackSize)
        return CGPoint(x: rackRect.minX + (CGFloat(slot) + 0.5) * w, y: rackRect.midY)
    }

    private func centroid(of idxs: [Int]) -> CGPoint {
        let pts = idxs.map { cellCenter($0) }
        return CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(max(pts.count, 1)),
                       y: pts.map(\.y).reduce(0, +) / CGFloat(max(pts.count, 1)))
    }

    /// Normalized (0…1) anchor inside the board for a game-space point.
    private func anchorOf(_ point: CGPoint) -> UnitPoint {
        guard boardRect.width > 0 else { return UnitPoint(x: 0.5, y: 0.45) }
        return UnitPoint(x: min(0.92, max(0.08, (point.x - boardRect.minX) / boardRect.width)),
                         y: min(0.92, max(0.08, (point.y - boardRect.minY) / boardRect.height)))
    }

    // MARK: - Live word readout

    /// The word the current drag/hover is building, e.g. ("SWI_H", clue).
    var liveWord: (text: String, clue: String)? {
        guard let idx = hoverCell ?? lastPlaceIdx,
              let engine else { return nil }
        let wis = engine.wordIndices(at: idx)
        guard !wis.isEmpty else { return nil }
        // Most-complete word through this cell wins.
        let wi = wis.max { a, b in
            let fa = puzzle.words[a].cellIndices.filter { filled[$0] != nil }.count
            let fb = puzzle.words[b].cellIndices.filter { filled[$0] != nil }.count
            return fa < fb
        }!
        let w = puzzle.words[wi]
        var chars: [String] = []
        for cellIdx in w.cellIndices {
            if let f = filled[cellIdx] { chars.append(String(f.letter)) }
            else if cellIdx == hoverCell, let drag { chars.append(String(drag.letter)) }
            else { chars.append("·") }
        }
        return (chars.joined(separator: " "), w.clue)
    }

    /// Cells of the live word (for board highlighting).
    var liveWordCells: Set<Int> {
        guard let idx = hoverCell, let engine,
              let wi = engine.wordIndices(at: idx).max(by: { a, b in
                  let fa = puzzle.words[a].cellIndices.filter { filled[$0] != nil }.count
                  let fb = puzzle.words[b].cellIndices.filter { filled[$0] != nil }.count
                  return fa < fb
              }) else { return [] }
        return Set(puzzle.words[wi].cellIndices)
    }

    // MARK: - Effects helpers

    private func spawnFloater(_ text: String, at idx: Int, side: Side, big: Bool) {
        spawnFloater(text, atPoint: cellCenter(idx), side: side, big: big)
    }

    private func spawnFloater(_ text: String, atPoint point: CGPoint, side: Side, big: Bool) {
        floaters.append(ScoreFloater(text: text, from: point, side: side, big: big))
    }

    private func spawnBurst(at point: CGPoint, kind: BurstKind) {
        bursts.append(ParticleBurst(center: point, kind: kind))
    }

    private func showBanner(_ text: String, bolt: Bool) {
        bannerText = text
        bannerBolt = bolt
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if self?.bannerText == text { self?.bannerText = nil }
        }
    }

    private func flashMood(_ mood: MascotMood) {
        mascotMood = mood
        moodTask?.cancel()
        moodTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            if !Task.isCancelled, self?.phase != .over { self?.mascotMood = .idle }
        }
    }

    // MARK: - Camera director (springs only; every move interruptible)

    private func setCamera(scale: Double, anchor: UnitPoint, spring: Animation = .spring(response: 0.45, dampingFraction: 0.82)) {
        cameraGeneration += 1
        withAnimation(spring) {
            cameraScale = scale
            cameraAnchor = anchor
        }
    }

    func cameraRest(animate: Bool = true) {
        cameraGeneration += 1
        let apply = { self.cameraScale = 1.0; self.cameraAnchor = UnitPoint(x: 0.5, y: 0.45) }
        if animate { withAnimation(.spring(response: 0.55, dampingFraction: 0.85), apply) } else { apply() }
    }

    private func cameraRestSoon(delay: Double = 0.85) {
        cameraGeneration += 1
        let gen = cameraGeneration
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.cameraGeneration == gen, self.drag == nil else { return }
            self.cameraRest()
        }
    }

    private func cameraDragFocus(idx: Int) {
        setCamera(scale: 1.3, anchor: anchorOf(cellCenter(idx)),
                  spring: .spring(response: 0.35, dampingFraction: 0.8))
    }

    private func cameraWordFocus(idx: Int, punch: Bool) {
        guard let engine else { return }
        let wi = engine.wordIndices(at: idx).first ?? -1
        let anchor = wi >= 0 ? anchorOf(centroid(of: puzzle.words[wi].cellIndices)) : anchorOf(cellCenter(idx))
        setCamera(scale: punch ? 1.6 : 1.45, anchor: anchor,
                  spring: .spring(response: 0.3, dampingFraction: 0.72))
        cameraRestSoon(delay: 0.95)
    }

    private func cameraPunch(anchor: UnitPoint) {
        setCamera(scale: 1.6, anchor: anchor, spring: .spring(response: 0.26, dampingFraction: 0.65))
        cameraRestSoon(delay: 0.8)
    }

    private func cameraWinPose() {
        cameraGeneration += 1
        withAnimation(.spring(response: 0.8, dampingFraction: 0.78)) {
            cameraScale = 1.35
            cameraAnchor = UnitPoint(x: 0.5, y: 0.4)
        }
    }
}
