import Foundation

/// The crossword board model shared by the generator, the engine and the UI.
enum CellKind: Equatable { case clue, letter, blank }

struct BoardCell: Equatable {
    var kind: CellKind
    var letter: Character? = nil      // solution letter (kind == .letter)
    var clueAcross: String? = nil     // clue text when a clue square fronts an across word
    var clueDown: String? = nil       // clue text when a clue square fronts a down word
    var isBonus: Bool = false         // blue bonus square (3 per board)
}

struct PlacedWord: Equatable {
    let answer: String
    let row: Int
    let col: Int
    let across: Bool
    let clue: String
    /// Flat cell indices this word occupies, in answer order.
    var cellIndices: [Int] {
        (0..<answer.count).map { i in
            (row + (across ? 0 : i)) * PuzzleGenerator.cols + (col + (across ? i : 0))
        }
    }
}

struct Puzzle: Equatable {
    let title: String
    let cells: [BoardCell]            // cols * rows entries
    let words: [PlacedWord]
}

/// Faithful Swift port of Michael's crossword generator from the shipped
/// ARCADE web build (itself a port of the original PuzzleGenerator.swift):
/// greedy crossing fill, an iterated local search that removes and refills
/// neighborhoods, and hard quality gates before a board may ship.
enum PuzzleGenerator {
    static let cols = 8
    static let rows = 12
    static var cellCount: Int { cols * rows }

    private static let gateMinWords = 13
    private static let gateMinLetterCells = 50
    private static let gateMinAvgCrossings = 1.8
    private static let gateMaxShortShare = 0.28

    // MARK: - Grid primitives (grid cells: nil = empty, "#" = clue square, else a letter)

    private static func canPlace(_ grid: [String?], _ word: String, _ r: Int, _ c: Int, _ across: Bool) -> Int {
        let dr = across ? 0 : 1, dc = across ? 1 : 0
        if across && c == 0 { return -1 }
        if !across && r == 0 { return -1 }
        let letters = Array(word)
        var cells: [Int] = []
        var crossings = 0
        for i in 0..<letters.count {
            let rr = r + dr * i, cc = c + dc * i
            if rr < 0 || rr >= rows || cc < 0 || cc >= cols { return -1 }
            let g = grid[rr * cols + cc]
            if g == "#" { return -1 }
            if let g, g != String(letters[i]) { return -1 }
            if g == String(letters[i]) { crossings += 1 }
            cells.append(rr * cols + cc)
        }
        let qr = across ? r : r - 1, qc = across ? c - 1 : c
        let q = grid[qr * cols + qc]
        if let q, q != "#" { return -1 }
        for idx in cells where grid[idx] == nil {
            let rr = idx / cols, cc = idx % cols
            if across {
                for nr in [rr - 1, rr + 1] where nr >= 0 && nr < rows {
                    let n = grid[nr * cols + cc]
                    if let n, n != "#" { return -1 }
                }
            } else {
                for nc in [cc - 1, cc + 1] where nc >= 0 && nc < cols {
                    let n = grid[rr * cols + nc]
                    if let n, n != "#" { return -1 }
                }
            }
        }
        let br = r - dr, bc = c - dc
        if br >= 0 && br < rows && bc >= 0 && bc < cols {
            let b = grid[br * cols + bc]
            if let b, b != "#" { return -1 }
        }
        let er = r + dr * letters.count, ec = c + dc * letters.count
        if er >= 0 && er < rows && ec >= 0 && ec < cols {
            let e = grid[er * cols + ec]
            if let e, e != "#" { return -1 }
        }
        return crossings
    }

    private static func doPlace(_ grid: inout [String?], _ word: String, _ r: Int, _ c: Int, _ across: Bool) {
        for (i, ch) in word.enumerated() {
            grid[(r + (across ? 0 : i)) * cols + (c + (across ? i : 0))] = String(ch)
        }
        grid[(across ? r : r - 1) * cols + (across ? c - 1 : c)] = "#"
    }

    // MARK: - Fill sweeps

    private static func fillBoard(_ grid: inout [String?], _ placed: inout [PlacedWord],
                                  _ starts: inout Set<String>, _ pool: [WordEntry], _ maxPasses: Int) {
        var pool = pool
        for _ in 0..<maxPasses {
            var progress = false
            for cand in pool {
                var best: (s: Double, r: Int, c: Int, across: Bool)? = nil
                for across in [true, false] {
                    for p in placed where p.across != across {
                        let pLetters = Array(p.answer)
                        for j in 0..<pLetters.count {
                            let jr = p.across ? p.row : p.row + j
                            let jc = p.across ? p.col + j : p.col
                            let candLetters = Array(cand.w)
                            for i in 0..<candLetters.count where candLetters[i] == pLetters[j] {
                                let rr = jr - (across ? 0 : i)
                                let cc = jc - (across ? i : 0)
                                if starts.contains("\(rr),\(cc),\(across ? "a" : "d")") { continue }
                                let x = canPlace(grid, cand.w, rr, cc, across)
                                if x < 1 { continue }
                                let s = (x == 2 ? 100.0 : x == 1 ? 90.0 : x == 3 ? 80.0 : 70.0)
                                    + Double(cand.w.count - x) - Double(rr + cc) / 100.0
                                if best == nil || s > best!.s { best = (s, rr, cc, across) }
                            }
                        }
                    }
                }
                if let b = best {
                    starts.insert("\(b.r),\(b.c),\(b.across ? "a" : "d")")
                    doPlace(&grid, cand.w, b.r, b.c, b.across)
                    placed.append(PlacedWord(answer: cand.w, row: b.r, col: b.c, across: b.across, clue: cand.c))
                    pool.removeAll { $0.w == cand.w }
                    progress = true
                }
            }
            if !progress { break }
        }
    }

    // MARK: - Quality + fitness

    private struct Quality {
        var avgCrossings = 0.0
        var shortShare = 0.0
        var shortWords = 0
        var letterCells = 0
        var zeroCross = 0
        var crossPer: [Int] = []
        var cellWords: [Int: [Int]] = [:]
        var hasDup = false
        var hasShadow = false
    }

    private static func boardQuality(_ placed: [PlacedWord]) -> Quality {
        var q = Quality()
        placed.enumerated().forEach { wi, p in
            for idx in p.cellIndices {
                q.cellWords[idx, default: []].append(wi)
            }
        }
        var crossTotal = 0
        var seen = Set<String>()
        var seenStarts = Set<String>()
        placed.forEach { p in
            if seen.contains(p.answer) { q.hasDup = true }
            seen.insert(p.answer)
            let sk = "\(p.row),\(p.col),\(p.across ? "a" : "d")"
            if seenStarts.contains(sk) { q.hasShadow = true }
            seenStarts.insert(sk)
            if p.answer.count == 3 { q.shortWords += 1 }
            var n = 0
            for idx in p.cellIndices where (q.cellWords[idx]?.count ?? 0) > 1 { n += 1 }
            q.crossPer.append(n)
            crossTotal += n
            if n == 0 && placed.count > 1 { q.zeroCross += 1 }
        }
        let n = max(placed.count, 1)
        q.avgCrossings = Double(crossTotal) / Double(n)
        q.shortShare = Double(q.shortWords) / Double(n)
        q.letterCells = q.cellWords.count
        return q
    }

    private static func boardFitness(_ q: Quality, _ placed: [PlacedWord]) -> Double {
        let n = placed.count
        let excessShort = max(0, q.shortWords - Int(Double(n) * gateMaxShortShare))
        return Double(q.letterCells) * 10 + Double(n) * 3
            - Double(excessShort) * 30
            - max(0, 1.9 - q.avgCrossings) * 100
            - Double(q.zeroCross) * 100000
            - ((q.hasDup || q.hasShadow) ? 100000 : 0)
    }

    private static func passesGates(_ placed: [PlacedWord]) -> Bool {
        if placed.count < gateMinWords { return false }
        let q = boardQuality(placed)
        return !q.hasDup && !q.hasShadow && q.zeroCross == 0
            && q.letterCells >= gateMinLetterCells
            && q.avgCrossings >= gateMinAvgCrossings
            && q.shortShare <= gateMaxShortShare
    }

    // MARK: - Improvement search

    private static func rebuildGrid(_ placed: [PlacedWord]) -> [String?] {
        var grid = [String?](repeating: nil, count: cellCount)
        for p in placed { doPlace(&grid, p.answer, p.row, p.col, p.across) }
        return grid
    }

    private static func startsOf(_ placed: [PlacedWord]) -> Set<String> {
        Set(placed.map { "\($0.row),\($0.col),\($0.across ? "a" : "d")" })
    }

    /// The bank interleaved round-robin across length groups (5, 6, 7, 4, 8, 3).
    private static func mixedPool(_ list: [WordEntry], _ used: Set<String>, _ cap: Int) -> [WordEntry] {
        let order = [5, 6, 7, 4, 8, 3]
        var groups = order.map { len in list.filter { $0.w.count == len && !used.contains($0.w) }.shuffled() }
        groups.append(list.filter { !used.contains($0.w) && !order.contains($0.w.count) }.shuffled())
        var out: [WordEntry] = []
        var added = true
        while out.count < cap && added {
            added = false
            for gi in groups.indices where !groups[gi].isEmpty && out.count < cap {
                out.append(groups[gi].removeFirst())
                added = true
            }
        }
        return out
    }

    private static func improveBoard(_ wordList: [WordEntry], _ placed: [PlacedWord]) -> [PlacedWord] {
        var best = placed
        var bestQ = boardQuality(best)
        var bestFit = boardFitness(bestQ, best)
        var cur = placed
        var curFit = bestFit
        var sinceImprove = 0
        var iter = 0
        while iter < 26 && sinceImprove < 7 {
            defer { iter += 1 }
            if bestQ.letterCells >= 55 && best.count >= 14 && bestQ.shortShare <= 0.25 { break }
            let q = boardQuality(cur)
            var remove: [Int]
            if iter % 2 == 0 && cur.count > 4 {
                let wi = 1 + Int.random(in: 0..<max(cur.count - 1, 1))
                var neigh: Set<Int> = [wi]
                if wi < cur.count {
                    for idx in cur[wi].cellIndices {
                        for other in q.cellWords[idx] ?? [] { neigh.insert(other) }
                    }
                }
                neigh.remove(0)
                remove = Array(neigh).sorted().prefix(6).map { $0 }
            } else {
                let idxs = cur.indices.filter { $0 != 0 }
                remove = Array(idxs.sorted { q.crossPer[$0] < q.crossPer[$1] }.prefix(3))
            }
            if remove.isEmpty { sinceImprove += 1; continue }
            var trial = cur.enumerated().filter { !remove.contains($0.offset) }.map { $0.element }
            var trialGrid = rebuildGrid(trial)
            var trialStarts = startsOf(trial)
            let used = Set(trial.map { $0.answer })
            let refill = mixedPool(wordList, used, 260)
            fillBoard(&trialGrid, &trial, &trialStarts, refill.filter { $0.w.count > 3 }, 3)
            fillBoard(&trialGrid, &trial, &trialStarts, refill, 2)
            let tq = boardQuality(trial)
            let tFit = boardFitness(tq, trial)
            if tq.zeroCross == 0 && tFit > curFit {
                cur = trial
                curFit = tFit
                if tFit > bestFit {
                    best = trial
                    bestQ = tq
                    bestFit = tFit
                    sinceImprove = 0
                } else { sinceImprove += 1 }
            } else { sinceImprove += 1 }
        }
        return best
    }

    // MARK: - Build

    private static func buildOnce(_ wordList: [WordEntry]) -> [PlacedWord] {
        var grid = [String?](repeating: nil, count: cellCount)
        var placed: [PlacedWord] = []
        var starts = Set<String>()
        var pool = wordList.shuffled()

        // Seed: a random long word across near the top of the board.
        let candidates = pool.filter { $0.w.count <= cols - 1 && $0.w.count >= 5 }
        let seedPool = candidates.isEmpty ? pool : candidates
        if let seed = seedPool.randomElement() {
            pool.removeAll { $0.w == seed.w }
            let r0 = 3
            let c0 = max(1, (cols - seed.w.count) / 2)
            if canPlace(grid, seed.w, r0, c0, true) != -1 {
                doPlace(&grid, seed.w, r0, c0, true)
                placed.append(PlacedWord(answer: seed.w, row: r0, col: c0, across: true, clue: seed.c))
                starts.insert("\(r0),\(c0),a")
            }
        }
        fillBoard(&grid, &placed, &starts, pool.filter { $0.w.count > 3 }.shuffled(), 8)
        fillBoard(&grid, &placed, &starts, pool.shuffled(), 3)
        return improveBoard(wordList, placed)
    }

    /// Generate a gated puzzle: several builds, keep the ones that pass,
    /// pick randomly among them; fall back to the fittest miss so
    /// generation never hangs and never returns an empty board.
    static func generate(wordList: [WordEntry] = WordBank.entries) -> Puzzle {
        var good: [[PlacedWord]] = []
        var bestEffort: [PlacedWord]? = nil
        var bestFit = -Double.infinity
        var bestCells = 0
        var builds = 0
        while good.count < 2 && (builds < 6 || (good.isEmpty && builds < 10 && bestCells < 48)) {
            builds += 1
            let placed = buildOnce(wordList)
            if passesGates(placed) { good.append(placed); continue }
            let q = boardQuality(placed)
            let f = boardFitness(q, placed)
            if f > bestFit { bestFit = f; bestEffort = placed; bestCells = q.letterCells }
        }
        let chosen = good.randomElement() ?? bestEffort ?? buildOnce(wordList)
        return finalize(chosen)
    }

    private static func finalize(_ placed: [PlacedWord]) -> Puzzle {
        let grid = rebuildGrid(placed)
        var clueA: [Int: String] = [:]
        var clueD: [Int: String] = [:]
        for p in placed {
            let qi = p.across ? p.row * cols + (p.col - 1) : (p.row - 1) * cols + p.col
            if p.across { clueA[qi] = p.clue } else { clueD[qi] = p.clue }
        }
        var cells: [BoardCell] = []
        var letterIdx: [Int] = []
        for i in 0..<cellCount {
            let g = grid[i]
            if g == "#" {
                cells.append(BoardCell(kind: .clue, clueAcross: clueA[i], clueDown: clueD[i]))
            } else if let g {
                cells.append(BoardCell(kind: .letter, letter: g.first))
                letterIdx.append(i)
            } else {
                cells.append(BoardCell(kind: .blank))
            }
        }
        // 3 blue bonus squares on random letter cells.
        for i in letterIdx.shuffled().prefix(3) { cells[i].isBonus = true }
        return Puzzle(title: WordBank.titles.randomElement() ?? "Warm-Up", cells: cells, words: placed)
    }
}
