import Foundation

enum FuzzyMatcher {
    /// Devuelve una puntuación si el patrón aparece como subsecuencia (insensible a mayúsculas),
    /// o nil si no encaja. Prefiere coincidencias contiguas y al principio.
    static func score(pattern: String, in candidate: String) -> Int? {
        if pattern.isEmpty { return 0 }
        let p = Array(pattern.lowercased())
        let c = Array(candidate.lowercased())
        var pi = 0
        var score = 0
        var lastMatch = -2
        for (i, ch) in c.enumerated() {
            guard pi < p.count else { break }
            if ch == p[pi] {
                score += (i == lastMatch + 1) ? 5 : 1   // bonus contiguo
                if i == 0 { score += 8 }                // bonus al principio
                lastMatch = i
                pi += 1
            }
        }
        guard pi == p.count else { return nil }
        score -= max(0, c.count - p.count) / 8 // ligera penalización por candidatos largos
        return score
    }
}
