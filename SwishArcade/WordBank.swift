import Foundation

/// One word-bank entry: the answer and its clue. Michael's own bank,
/// ported from the shipped ARCADE web build (846 pairs, bundled as
/// Resources/words.json — same data, native container).
struct WordEntry: Codable, Hashable {
    let w: String
    let c: String
}

/// Loads and serves the bundled word bank plus the letter bag and the
/// puzzle titles, mirroring the web engine's constants exactly.
enum WordBank {
    static let titles = ["Warm-Up", "First Serve", "Rally Time", "Smash Hit",
                         "Net Play", "Top Spin", "Match Point", "Grand Slam",
                         "Fast Break", "Full Court", "Overtime", "Championship"]

    /// Scrabble-style letter frequencies, identical weights to the web bag.
    static let letterBag: [Character] = {
        let weights: [(Character, Int)] = [("E", 12), ("A", 9), ("I", 9), ("O", 8),
                                           ("N", 6), ("R", 6), ("T", 6), ("L", 4),
                                           ("S", 4), ("U", 4), ("D", 4), ("G", 3),
                                           ("B", 2), ("C", 2), ("M", 2), ("P", 2),
                                           ("F", 2), ("H", 2), ("V", 2), ("W", 2),
                                           ("Y", 2), ("K", 1), ("J", 1), ("X", 1),
                                           ("Q", 1), ("Z", 1)]
        var bag: [Character] = []
        for (letter, n) in weights { bag += Array(repeating: letter, count: n) }
        return bag
    }()

    static let entries: [WordEntry] = {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([WordEntry].self, from: data),
              !decoded.isEmpty else {
            // Should never happen (the checker verifies the bundle), but a
            // tiny in-code fallback keeps the game bootable regardless.
            return [WordEntry(w: "SWISH", c: "Nothing but net"),
                    WordEntry(w: "ARCADE", c: "Coin-op hall"),
                    WordEntry(w: "PUZZLE", c: "Brain teaser")]
        }
        return decoded
    }()
}
