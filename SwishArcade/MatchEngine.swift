import Foundation

enum Side: Equatable { case you, cpu }

enum MatchEvent {
    case start(endsAt: Double)
    case place(side: Side, idx: Int, letter: Character, points: Int, mult: Int)
    case wrong(side: Side, idx: Int, letter: Character)
    case word(side: Side, wordIndex: Int, answer: String, idxs: [Int], bonus: Int, mult: Int, doubled: Bool)
    case comboUp(side: Side, mult: Int, tier: String)
    case comboExpire(side: Side)
    case comboBreak(side: Side)
    case hint(idx: Int, hintsLeft: Int)
    case bomb(center: Int, idxs: [Int], bombsLeft: Int)
    case shuffle(shufflesLeft: Int)
    case pickup(idx: Int, letter: Character)
    case cpuAct(acted: Bool, idx: Int?)
    case end(winner: Side?, reason: String, you: Int, cpu: Int)
}

/// The Rush match engine — a faithful Swift port of the shipped ARCADE web
/// engine. Pure logic, no UI: the view model subscribes to events. Time is
/// always passed in (milliseconds); a match is a real-time 3-minute race
/// against the CPU on one shared board.
///
/// Native additions, per the "ad made real" spec: SHUFFLE (redeal your
/// rack) and pick-back-up — your most recent set tile can be lifted off
/// again inside a short grace window, reversing its points and combo step.
final class MatchEngine {
    // Tuning constants — identical to the web engine.
    static let matchSeconds = 180.0
    static let comboWindowMs = 5000.0
    static let comboMax = 5
    static let rackSize = 5
    static let hintsPerMatch = 3
    static let bombsPerMatch = 2
    static let shufflesPerMatch = 3
    static let letterPoints = 10
    static let wordBonusPerLetter = 5
    static let comboTiers = ["COMBO STARTER", "HEATING UP", "ON A TEAR", "BLAZING", "COMBO MASTER"]
    static let pickupGraceMs = 2500.0

    struct Difficulty { let paceMin: Double; let paceMax: Double; let accuracy: Double }
    static let difficulties: [String: Difficulty] = [
        "easy": Difficulty(paceMin: 3000, paceMax: 4600, accuracy: 0.55),
        "normal": Difficulty(paceMin: 2300, paceMax: 3800, accuracy: 0.72),
        "hard": Difficulty(paceMin: 1600, paceMax: 2800, accuracy: 0.88),
    ]

    struct ComboState { var mult = 1; var lastAt: Double? = nil }
    struct FilledCell: Equatable { let by: Side; let letter: Character }

    /// One reversible placement (player only) for pick-back-up.
    private struct Placement {
        let idx: Int
        let slot: Int
        let letter: Character
        let points: Int
        let wordBonuses: [(wordIndex: Int, bonus: Int)]
        let comboBefore: ComboState
        let atMs: Double
        let seq: Int
    }

    let puzzle: Puzzle
    let difficultyKey: String
    private let diff: Difficulty
    private let cellWords: [Int: [Int]]
    let totalLetters: Int

    private(set) var over = false
    private(set) var winner: Side? = nil
    private(set) var endReason: String? = nil
    private(set) var filled: [FilledCell?]
    private(set) var filledCount = 0
    private(set) var scores: [Side: Int] = [.you: 0, .cpu: 0]
    private(set) var combo: [Side: ComboState] = [.you: ComboState(), .cpu: ComboState()]
    private(set) var racks: [Side: [Character?]] = [.you: [], .cpu: []]
    private(set) var hintsLeft = hintsPerMatch
    private(set) var bombsLeft = bombsPerMatch
    private(set) var shufflesLeft = shufflesPerMatch
    private(set) var startedAt: Double? = nil
    private(set) var endsAt: Double? = nil
    private(set) var nextCpuAt: Double? = nil

    private var placements: [Placement] = []
    private var placementSeq = 0

    var onEvent: ((MatchEvent) -> Void)?
    private func emit(_ e: MatchEvent) { onEvent?(e) }

    init(puzzle: Puzzle, difficultyKey: String) {
        self.puzzle = puzzle
        self.difficultyKey = difficultyKey
        self.diff = MatchEngine.difficulties[difficultyKey] ?? MatchEngine.difficulties["normal"]!
        var map: [Int: [Int]] = [:]
        for (wi, w) in puzzle.words.enumerated() {
            for idx in w.cellIndices { map[idx, default: []].append(wi) }
        }
        self.cellWords = map
        self.totalLetters = puzzle.cells.filter { $0.kind == .letter }.count
        self.filled = [FilledCell?](repeating: nil, count: PuzzleGenerator.cellCount)
    }

    // MARK: - Needs / draws (dead-rack guarantee included)

    private func needs() -> (list: [Character], distinct: Set<Character>, open: Int) {
        var list: [Character] = []
        var distinct = Set<Character>()
        var open = 0
        for i in 0..<PuzzleGenerator.cellCount {
            let c = puzzle.cells[i]
            if c.kind == .letter && filled[i] == nil, let s = c.letter {
                open += 1
                list.append(s)
                distinct.insert(s)
            }
        }
        return (list, distinct, open)
    }

    private func drawLetter() -> Character {
        let n = needs()
        if n.open > 0 && Double.random(in: 0..<1) < 0.55, let pick = n.list.randomElement() { return pick }
        return WordBank.letterBag.randomElement() ?? "E"
    }

    /// Hard guarantee: while the board still needs letters, a rack always
    /// holds at least one of them.
    private func ensurePlayable(_ side: Side) {
        let n = needs()
        if n.open == 0 { return }
        guard var rack = racks[side], !rack.isEmpty else { return }
        if !rack.contains(where: { $0 != nil && n.distinct.contains($0!) }) {
            if let needed = n.list.randomElement() {
                rack[Int.random(in: 0..<rack.count)] = needed
                racks[side] = rack
            }
        }
    }

    private func refillSlot(_ side: Side, _ slot: Int) {
        racks[side]?[slot] = drawLetter()
        ensurePlayable(side)
    }

    private func dealRack(_ side: Side) {
        racks[side] = (0..<MatchEngine.rackSize).map { _ in drawLetter() }
        ensurePlayable(side)
    }

    // MARK: - Scoring core

    @discardableResult
    private func lockCell(_ side: Side, _ idx: Int, _ now: Double,
                          mult overrideMult: Int?, advance: Bool) -> (points: Int, wordBonuses: [(Int, Int)]) {
        let mult = overrideMult ?? combo[side]!.mult
        let letter = puzzle.cells[idx].letter!
        filled[idx] = FilledCell(by: side, letter: letter)
        filledCount += 1
        placementSeq += 1
        let pts = MatchEngine.letterPoints * mult
        scores[side]! += pts
        emit(.place(side: side, idx: idx, letter: letter, points: pts, mult: mult))
        var wordBonuses: [(Int, Int)] = []
        for wi in cellWords[idx] ?? [] {
            let w = puzzle.words[wi]
            if w.cellIndices.allSatisfy({ filled[$0] != nil }) {
                // A word covering a blue bonus square doubles its word bonus:
                // the DOUBLE WORD SCORE moment.
                let doubled = w.cellIndices.contains { puzzle.cells[$0].isBonus }
                var bonus = MatchEngine.wordBonusPerLetter * w.answer.count * mult
                if doubled { bonus *= 2 }
                scores[side]! += bonus
                wordBonuses.append((wi, bonus))
                emit(.word(side: side, wordIndex: wi, answer: w.answer, idxs: w.cellIndices,
                           bonus: bonus, mult: mult, doubled: doubled))
            }
        }
        if advance {
            var c = combo[side]!
            c.mult = min(MatchEngine.comboMax, c.mult + 1)
            c.lastAt = now
            combo[side] = c
            if c.mult >= 3 {
                emit(.comboUp(side: side, mult: c.mult, tier: MatchEngine.comboTiers[c.mult - 1]))
            }
        }
        return (pts, wordBonuses)
    }

    private func breakCombo(_ side: Side, _ now: Double) {
        var c = combo[side]!
        if c.mult > 1 || c.lastAt != nil { emit(.comboBreak(side: side)) }
        c.mult = 1
        c.lastAt = nil
        combo[side] = c
    }

    // MARK: - Player actions

    @discardableResult
    func attemptPlace(side: Side, rackSlot: Int, idx: Int, now: Double) -> Bool {
        if over || startedAt == nil { return false }
        let cell = puzzle.cells[idx]
        if cell.kind != .letter || filled[idx] != nil { return false }
        guard let letter = racks[side]?[rackSlot] else { return false }
        if letter != cell.letter {
            if side == .you { breakCombo(.you, now) }
            emit(.wrong(side: side, idx: idx, letter: letter))
            return false
        }
        let comboBefore = combo[side]!
        let result = lockCell(side, idx, now, mult: nil, advance: true)
        if side == .you {
            placements.append(Placement(idx: idx, slot: rackSlot, letter: letter,
                                        points: result.points, wordBonuses: result.wordBonuses,
                                        comboBefore: comboBefore, atMs: now, seq: placementSeq))
        }
        refillSlot(side, rackSlot)
        if filledCount >= totalLetters { finish("board", now) }
        return true
    }

    /// Pick back up: lift your latest set tile off the board again. Only
    /// while it is still the newest placement on the board and inside the
    /// grace window. Returns the letter, or nil if pickup isn't available.
    func pickupLastPlacement(now: Double) -> (idx: Int, slot: Int, letter: Character)? {
        guard let last = placements.last,
              last.seq == placementSeq,
              now - last.atMs <= MatchEngine.pickupGraceMs,
              filled[last.idx]?.by == .you else { return nil }
        placements.removeLast()
        filled[last.idx] = nil
        filledCount -= 1
        scores[.you]! -= last.points + last.wordBonuses.reduce(0) { $0 + $1.1 }
        combo[.you] = last.comboBefore
        racks[.you]?[last.slot] = last.letter
        emit(.pickup(idx: last.idx, letter: last.letter))
        return (last.idx, last.slot, last.letter)
    }

    /// Index of the tile that can currently be picked back up, if any.
    func pickupCandidate(now: Double) -> Int? {
        guard let last = placements.last, last.seq == placementSeq,
              now - last.atMs <= MatchEngine.pickupGraceMs,
              filled[last.idx]?.by == .you else { return nil }
        return last.idx
    }

    @discardableResult
    func useHint(now: Double) -> Int? {
        if over || startedAt == nil || hintsLeft <= 0 { return nil }
        // Prefer the open cell in the most-complete word.
        var best = -1
        var bestRatio = -1.0
        for i in 0..<PuzzleGenerator.cellCount {
            let c = puzzle.cells[i]
            if c.kind != .letter || filled[i] != nil { continue }
            var ratio = 0.0
            for wi in cellWords[i] ?? [] {
                let w = puzzle.words[wi]
                let done = w.cellIndices.filter { filled[$0] != nil }.count
                ratio = max(ratio, Double(done) / Double(w.answer.count))
            }
            let jitter = Double.random(in: 0..<0.001)
            if ratio + jitter > bestRatio { bestRatio = ratio + jitter; best = i }
        }
        if best < 0 { return nil }
        hintsLeft -= 1
        lockCell(.you, best, now, mult: nil, advance: true)
        emit(.hint(idx: best, hintsLeft: hintsLeft))
        if filledCount >= totalLetters { finish("board", now) }
        return best
    }

    @discardableResult
    func useBomb(centerIdx: Int, now: Double) -> [Int]? {
        if over || startedAt == nil || bombsLeft <= 0 { return nil }
        let cols = PuzzleGenerator.cols, rows = PuzzleGenerator.rows
        let r0 = centerIdx / cols, c0 = centerIdx % cols
        var targets: [Int] = []
        for dr in -1...1 { for dc in -1...1 {
            let r = r0 + dr, c = c0 + dc
            if r < 0 || r >= rows || c < 0 || c >= cols { continue }
            let idx = r * cols + c
            if puzzle.cells[idx].kind == .letter && filled[idx] == nil { targets.append(idx) }
        } }
        if targets.isEmpty { return nil }
        bombsLeft -= 1
        let mult = combo[.you]!.mult
        for (k, idx) in targets.enumerated() {
            lockCell(.you, idx, now, mult: mult, advance: k == 0)
        }
        emit(.bomb(center: centerIdx, idxs: targets, bombsLeft: bombsLeft))
        if filledCount >= totalLetters { finish("board", now) }
        return targets
    }

    /// SHUFFLE: throw your rack back and draw a fresh one (still guaranteed
    /// playable). Native addition — the ad's third power-up button.
    @discardableResult
    func useShuffle(now: Double) -> Bool {
        if over || startedAt == nil || shufflesLeft <= 0 { return false }
        shufflesLeft -= 1
        dealRack(.you)
        emit(.shuffle(shufflesLeft: shufflesLeft))
        return true
    }

    // MARK: - CPU (paced — the "CPU is thinking" beat is this schedule)

    private func scheduleCpu(_ now: Double) {
        nextCpuAt = now + diff.paceMin + Double.random(in: 0..<(diff.paceMax - diff.paceMin))
    }

    private func cpuAct(_ now: Double) {
        if over { return }
        var playable: [Int] = []
        for i in 0..<PuzzleGenerator.cellCount {
            let c = puzzle.cells[i]
            if c.kind == .letter && filled[i] == nil, let s = c.letter,
               racks[.cpu]?.contains(s) == true { playable.append(i) }
        }
        var acted = false
        var actedIdx: Int? = nil
        if !playable.isEmpty {
            if Double.random(in: 0..<1) <= diff.accuracy {
                let idx = playable.randomElement()!
                let slot = racks[.cpu]!.firstIndex(of: puzzle.cells[idx].letter!)!
                acted = attemptPlace(side: .cpu, rackSlot: slot, idx: idx, now: now)
                actedIdx = idx
            } else {
                if Double.random(in: 0..<1) < 0.25 { breakCombo(.cpu, now) }
            }
        }
        emit(.cpuAct(acted: acted, idx: actedIdx))
        scheduleCpu(now)
    }

    /// True while the CPU's next move is being "thought about".
    var cpuIsThinking: Bool {
        startedAt != nil && !over && nextCpuAt != nil
    }

    // MARK: - Lifecycle

    func start(now: Double) {
        startedAt = now
        endsAt = now + MatchEngine.matchSeconds * 1000
        dealRack(.you)
        dealRack(.cpu)
        nextCpuAt = now + 1400 // small grace beat before the CPU's first move
        emit(.start(endsAt: endsAt!))
    }

    func tick(now: Double) {
        if over || startedAt == nil { return }
        for side in [Side.you, Side.cpu] {
            var c = combo[side]!
            if let last = c.lastAt, now - last > MatchEngine.comboWindowMs {
                c.mult = 1
                c.lastAt = nil
                combo[side] = c
                emit(.comboExpire(side: side))
            }
        }
        if let next = nextCpuAt, now >= next { cpuAct(now) }
        if let ends = endsAt, now >= ends { finish("clock", now) }
    }

    private func finish(_ reason: String, _ now: Double) {
        if over { return }
        over = true
        endReason = reason
        let y = scores[.you]!, c = scores[.cpu]!
        winner = y > c ? .you : c > y ? .cpu : nil
        emit(.end(winner: winner, reason: reason, you: y, cpu: c))
    }

    func timeLeft(now: Double) -> Double {
        guard let ends = endsAt else { return MatchEngine.matchSeconds * 1000 }
        return max(0, ends - now)
    }

    /// Word indices passing through a cell (for the live word readout).
    func wordIndices(at idx: Int) -> [Int] { cellWords[idx] ?? [] }
}
