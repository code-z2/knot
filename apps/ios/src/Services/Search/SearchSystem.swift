import Foundation

struct SearchDocument<ID: Hashable> {
    let id: ID
    let title: String
    let keywords: [String]
}

struct SearchResult<ID: Hashable> {
    let id: ID
    let score: Int
}

enum SearchSystem {
    static func filter<T, ID: Hashable>(
        query: String,
        items: [T],
        toDocument: (T) -> SearchDocument<ID>,
        itemID: (T) -> ID,
    ) -> [T] {
        let docs = items.map(toDocument)
        let results = search(query: query, in: docs)
        let rank = Dictionary(uniqueKeysWithValues: results.enumerated().map { ($0.element.id, $0.offset) })
        return items
            .filter { rank[itemID($0)] != nil }
            .sorted { (rank[itemID($0)] ?? .max) < (rank[itemID($1)] ?? .max) }
    }

    static func search<ID: Hashable>(
        query: String,
        in documents: [SearchDocument<ID>],
    ) -> [SearchResult<ID>] {
        let q = normalize(query)
        guard !q.isEmpty else { return documents.map { SearchResult(id: $0.id, score: 0) } }

        return documents
            .compactMap { doc in
                let title = normalize(doc.title)
                let keys = doc.keywords.map(normalize)

                var score = 0
                if title == q { score += 120 }
                if title.hasPrefix(q) { score += 80 }
                if title.contains(q) { score += 40 }

                for key in keys {
                    if key == q { score += 60 }
                    if key.hasPrefix(q) { score += 30 }
                    if key.contains(q) { score += 20 }
                }

                if score == 0 { return nil }
                return SearchResult(id: doc.id, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return String(describing: lhs.id) < String(describing: rhs.id) }
                return lhs.score > rhs.score
            }
    }

    private nonisolated static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
