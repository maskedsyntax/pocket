import Foundation

/// Ranks app names against a query. Higher is better, nil means no match.
///
/// Tiers, best first: exact, prefix, word prefix ("code" → "Visual Studio Code"),
/// initials ("vsc"), substring, and finally a fuzzy in-order subsequence.
enum Matcher {
    static func score(query: String, name: String) -> Int? {
        let q = query.lowercased()
        let t = name.lowercased()
        if q.isEmpty { return 0 }

        if t == q { return 10_000 }
        if t.hasPrefix(q) { return 8_000 - t.count }

        let words = splitWords(name)
        if words.contains(where: { $0.hasPrefix(q) }) { return 6_000 - t.count }

        let initials = String(words.compactMap(\.first))
        if initials.hasPrefix(q), q.count > 1 { return 5_000 - initials.count }

        if let range = t.range(of: q) {
            return 4_000 - t.distance(from: t.startIndex, to: range.lowerBound)
        }

        return fuzzy(Array(q), Array(t), words: words)
    }

    /// Character offsets in `name` to highlight for `query`, following the same
    /// tiers as `score` so the highlight shows why an app matched.
    static func highlights(query: String, name: String) -> Set<Int> {
        let q = Array(query.lowercased())
        let chars = Array(name)
        let lower = chars.map { ch -> Character in
            let s = ch.lowercased()
            return s.count == 1 ? Character(s) : ch
        }
        guard !q.isEmpty, q.count <= lower.count else { return [] }

        func run(from start: Int) -> Set<Int> { Set(start..<(start + q.count)) }
        func matches(at start: Int) -> Bool {
            start + q.count <= lower.count && Array(lower[start..<(start + q.count)]) == q
        }

        if matches(at: 0) { return run(from: 0) }  // exact, prefix

        let starts = wordStarts(chars)
        if let start = starts.first(where: matches) { return run(from: start) }  // word prefix

        if q.count > 1, starts.count >= q.count,
            zip(starts, q).allSatisfy({ lower[$0] == $1 })
        {
            return Set(starts.prefix(q.count))  // initials
        }

        if let start = (0...(lower.count - q.count)).first(where: matches) {
            return run(from: start)  // substring
        }

        // Fuzzy: the same greedy in-order walk as `fuzzy`.
        var hits = Set<Int>()
        var ti = 0
        for ch in q {
            while ti < lower.count, lower[ti] != ch { ti += 1 }
            guard ti < lower.count else { return [] }
            hits.insert(ti)
            ti += 1
        }
        return hits
    }

    /// Offsets where each word of `splitWords` begins.
    private static func wordStarts(_ chars: [Character]) -> [Int] {
        var starts: [Int] = []
        for (i, ch) in chars.enumerated() where ch.isLetter || ch.isNumber {
            let previous = i > 0 ? chars[i - 1] : nil
            let afterSeparator = previous.map { !$0.isLetter && !$0.isNumber } ?? true
            let camelHump = ch.isUppercase && (previous?.isLowercase ?? false)
            if afterSeparator || camelHump { starts.append(i) }
        }
        return starts
    }

    /// Splits on separators and camelCase humps: "OBS-Studio" → ["obs", "studio"],
    /// "FaceTime" → ["face", "time"].
    private static func splitWords(_ name: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for ch in name {
            if !ch.isLetter && !ch.isNumber {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else {
                if ch.isUppercase, let previous, previous.isLowercase, !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                current.append(ch)
            }
            previous = ch
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.lowercased() }
    }

    private static func fuzzy(_ q: [Character], _ t: [Character], words: [String]) -> Int? {
        var score = 1_000
        var ti = 0
        var lastMatch = -2
        for ch in q {
            var found = false
            while ti < t.count {
                defer { ti += 1 }
                if t[ti] == ch {
                    let atBoundary = ti == 0 || !(t[ti - 1].isLetter || t[ti - 1].isNumber)
                    if atBoundary { score += 30 }
                    if ti == lastMatch + 1 { score += 20 } else { score -= min(ti - lastMatch, 10) }
                    lastMatch = ti
                    found = true
                    break
                }
            }
            if !found { return nil }
        }
        return score - t.count
    }
}
