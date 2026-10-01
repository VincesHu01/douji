import Foundation

enum SearchEngine {
    private struct Turn {
        let question: ChatMessage?
        let answers: [ChatMessage]

        var answerText: String? {
            let text = answers.map(\.text).joined(separator: "\n")
            return text.isEmpty ? nil : text
        }

        var ordinal: Int { question?.ordinal ?? answers.first?.ordinal ?? 1 }
        var messageID: String { question?.id ?? answers.first?.id ?? "unknown" }
    }

    static func search(
        _ query: String,
        in conversations: [Conversation],
        scope: SearchScope = .all,
        matchMode: SearchMatchMode = .fuzzy,
        sort: ResultSort = .relevance,
        grouping: ResultGrouping = .bestPerConversation,
        limit: Int = 30
    ) -> [SearchHit] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var hits: [SearchHit] = []
        for conversation in conversations {
            var titleOnlyAdded = false
            let conversationTurns = turns(from: conversation.messages)
            for turn in conversationTurns {
                let occurredAt = turn.question?.createdAt ?? turn.answers.last?.createdAt ?? conversation.updatedAt
                let question = turn.question?.text
                let answer = turn.answerText
                let combined = [question, answer].compactMap { $0 }.joined(separator: "\n")

                let questionScore = score(normalizedQuery, against: normalize(question ?? ""), mode: matchMode)
                let answerScore = score(normalizedQuery, against: normalize(answer ?? ""), mode: matchMode)
                let combinedScore = score(normalizedQuery, against: normalize(combined), mode: matchMode)
                let rawTitleScore = score(normalizedQuery, against: normalize(conversation.title), mode: matchMode)
                let titleScore = rawTitleScore * 0.8
                let contentScore = max(combinedScore, max(questionScore, answerScore) + min(questionScore, answerScore) * 0.25)
                let total: Double
                switch scope {
                case .all: total = max(contentScore, titleScore)
                case .questions: total = questionScore
                case .answers: total = answerScore
                case .titles: total = rawTitleScore
                }
                guard total > 0 else { continue }

                let isTitleOnly = scope == .titles || (scope == .all && contentScore == 0 && titleScore > 0)
                if isTitleOnly, titleOnlyAdded { continue }
                if isTitleOnly { titleOnlyAdded = true }

                let matchedText: String
                let reason: String
                switch scope {
                case .questions:
                    matchedText = question ?? combined
                    reason = normalize(question ?? "").contains(normalizedQuery) ? "问题原文命中" : "问题模糊匹配"
                case .answers:
                    matchedText = answer ?? combined
                    reason = normalize(answer ?? "").contains(normalizedQuery) ? "回答原文命中" : "回答模糊匹配"
                case .titles:
                    matchedText = conversation.title
                    reason = "标题匹配"
                case .all:
                    matchedText = answerScore > questionScore ? (answer ?? combined) : (question ?? combined)
                    if titleScore > contentScore {
                        reason = "标题匹配"
                    } else if questionScore >= answerScore, questionScore > 0 {
                        reason = normalize(question ?? "").contains(normalizedQuery) ? "问题原文命中" : "问题模糊匹配"
                    } else if answerScore > 0 {
                        reason = normalize(answer ?? "").contains(normalizedQuery) ? "回答原文命中" : "回答模糊匹配"
                    } else {
                        reason = "问答上下文匹配"
                    }
                }
                let fragments = matchingFragments(
                    query: normalizedQuery,
                    text: normalize([conversation.title, question, answer].compactMap { $0 }.joined(separator: " "))
                )
                hits.append(SearchHit(
                    id: "\(conversation.id):\(turn.messageID)",
                    conversationID: conversation.id,
                    messageID: turn.messageID,
                    title: conversation.title,
                    matchedText: matchedText,
                    question: question,
                    answer: answer,
                    ordinal: turn.ordinal,
                    score: total,
                    matchReason: reason,
                    matchFragments: fragments,
                    url: conversation.url,
                    updatedAt: occurredAt,
                    recencyRank: conversation.recencyRank
                ))
            }
        }

        return finalize(hits, sort: sort, grouping: grouping, limit: limit)
    }

    static func advancedSearch(
        _ rules: [AdvancedSearchRule],
        in conversations: [Conversation],
        sort: ResultSort = .relevance,
        grouping: ResultGrouping = .bestPerConversation,
        limit: Int = 30
    ) -> [SearchHit] {
        let usable = rules.filter { !$0.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = usable.first else { return [] }

        func matches(for rule: AdvancedSearchRule) -> [String: SearchHit] {
            Dictionary(uniqueKeysWithValues: search(
                rule.query,
                in: conversations,
                scope: rule.scope,
                matchMode: rule.matchMode,
                sort: .relevance,
                grouping: .allTurns,
                limit: 10_000
            ).map { ($0.id, $0) })
        }

        var selected = matches(for: first)
        var matchedConditionCount = Dictionary(uniqueKeysWithValues: selected.keys.map { ($0, 1) })
        var fragments = Dictionary(uniqueKeysWithValues: selected.map { ($0.key, Set($0.value.matchFragments)) })

        for rule in usable.dropFirst() {
            let current = matches(for: rule)
            switch rule.relation {
            case .and:
                selected = selected.filter { current[$0.key] != nil }
                matchedConditionCount = matchedConditionCount.filter { selected[$0.key] != nil }
                fragments = fragments.filter { selected[$0.key] != nil }
                for key in selected.keys {
                    matchedConditionCount[key, default: 1] += 1
                    fragments[key, default: []].formUnion(current[key]?.matchFragments ?? [])
                }
            case .or:
                for (key, hit) in current {
                    if let existing = selected[key], hit.score > existing.score { selected[key] = hit }
                    else if selected[key] == nil { selected[key] = hit }
                    matchedConditionCount[key, default: 0] += 1
                    fragments[key, default: []].formUnion(hit.matchFragments)
                }
            case .not:
                for key in current.keys {
                    selected.removeValue(forKey: key)
                    matchedConditionCount.removeValue(forKey: key)
                    fragments.removeValue(forKey: key)
                }
            }
        }

        let positiveCount = usable.filter { $0.relation != .not }.count
        let combined = selected.map { key, hit in
            let count = matchedConditionCount[key] ?? 1
            let reason = positiveCount > 1
                ? (count == positiveCount ? "同时命中 \(count) 个条件" : "命中 \(count) 个检索条件")
                : hit.matchReason
            return SearchHit(
                id: hit.id,
                conversationID: hit.conversationID,
                messageID: hit.messageID,
                title: hit.title,
                matchedText: hit.matchedText,
                question: hit.question,
                answer: hit.answer,
                ordinal: hit.ordinal,
                score: hit.score + Double(max(0, count - 1)) * 6,
                matchReason: reason,
                matchFragments: Array(fragments[key] ?? []).sorted { $0.count > $1.count },
                url: hit.url,
                updatedAt: hit.updatedAt,
                recencyRank: hit.recencyRank
            )
        }
        return finalize(combined, sort: sort, grouping: grouping, limit: limit)
    }

    private static func finalize(
        _ hits: [SearchHit],
        sort: ResultSort,
        grouping: ResultGrouping,
        limit: Int
    ) -> [SearchHit] {
        let sorted = hits.sorted {
            if sort == .recent, ($0.recencyRank ?? .max) != ($1.recencyRank ?? .max) {
                return ($0.recencyRank ?? .max) < ($1.recencyRank ?? .max)
            }
            if sort == .recent, ($0.updatedAt ?? .distantPast) != ($1.updatedAt ?? .distantPast) {
                return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
            if abs($0.score - $1.score) > 0.001 { return $0.score > $1.score }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
        if grouping == .allTurns { return Array(sorted.prefix(limit)) }

        var seen = Set<String>()
        return sorted.filter { seen.insert($0.conversationID).inserted }.prefix(limit).map { $0 }
    }

    static func browse(in conversations: [Conversation], limit: Int = 500) -> [SearchHit] {
        conversations.flatMap { conversation in
            turns(from: conversation.messages).map { turn in
                let question = turn.question?.text
                let answer = turn.answerText
                return SearchHit(
                    id: "\(conversation.id):\(turn.messageID)",
                    conversationID: conversation.id,
                    messageID: turn.messageID,
                    title: conversation.title,
                    matchedText: question ?? answer ?? "",
                    question: question,
                    answer: answer,
                    ordinal: turn.ordinal,
                    score: 0,
                    matchReason: "已收藏",
                    matchFragments: [],
                    url: conversation.url,
                    updatedAt: turn.question?.createdAt ?? turn.answers.last?.createdAt ?? conversation.updatedAt,
                    recencyRank: conversation.recencyRank
                )
            }
        }
        .sorted {
            if ($0.recencyRank ?? .max) != ($1.recencyRank ?? .max) {
                return ($0.recencyRank ?? .max) < ($1.recencyRank ?? .max)
            }
            if ($0.updatedAt ?? .distantPast) != ($1.updatedAt ?? .distantPast) {
                return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.ordinal < $1.ordinal
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func matchingFragments(query: String, text: String) -> [String] {
        if text.contains(query) { return [query] }
        return features(query, removingQuestionFillers: true)
            .intersection(features(text, removingQuestionFillers: false))
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs < rhs
            }
            .prefix(6)
            .map { $0 }
    }

    static func score(
        _ query: String,
        against text: String,
        mode: SearchMatchMode = .fuzzy
    ) -> Double {
        guard !query.isEmpty, !text.isEmpty else { return 0 }

        if mode == .exact {
            if text == query { return 20 }
            return text.contains(query) ? 10 : 0
        }

        var value = 0.0
        if text == query { value += 20 }
        if text.contains(query) { value += 10 }

        let queryFeatures = features(query, removingQuestionFillers: true)
        let textFeatures = features(text, removingQuestionFillers: false)
        guard !queryFeatures.isEmpty else { return value }

        let overlap = queryFeatures.intersection(textFeatures).count
        let requiredOverlap: Int
        if queryFeatures.count == 1 {
            requiredOverlap = 1
        } else {
            requiredOverlap = max(2, Int(ceil(Double(queryFeatures.count) * 0.35)))
        }

        // Phrase containment may pass directly. Fuzzy matches must cover a
        // meaningful portion of the query, which prevents generic fragments
        // such as “什么” from pulling unrelated conversations into the list.
        guard text.contains(query) || overlap >= requiredOverlap else { return 0 }

        let coverage = Double(overlap) / Double(queryFeatures.count)
        value += coverage * 8
        value += diceCoefficient(queryFeatures, textFeatures) * 4
        return value
    }

    private static func turns(from messages: [ChatMessage]) -> [Turn] {
        var result: [Turn] = []
        var question: ChatMessage?
        var answers: [ChatMessage] = []

        func appendCurrent() {
            guard question != nil || !answers.isEmpty else { return }
            result.append(Turn(question: question, answers: answers))
        }

        for message in messages {
            if message.isUser {
                appendCurrent()
                question = message
                answers = []
            } else if question == nil {
                result.append(Turn(question: nil, answers: [message]))
            } else {
                answers.append(message)
            }
        }
        appendCurrent()
        return result
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[\p{P}\p{S}\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func features(_ value: String, removingQuestionFillers: Bool) -> Set<String> {
        var prepared = value
        if removingQuestionFillers {
            for filler in ["有什么", "是什么", "为什么", "怎么样", "怎么办", "怎么", "如何", "是否", "哪些", "一下", "这个", "那个"] {
                prepared = prepared.replacingOccurrences(of: filler, with: " ")
            }
        }

        var result = Set<String>()
        for segment in prepared.split(separator: " ").map(String.init) where !segment.isEmpty {
            let characters = Array(segment)
            if characters.count <= 2 {
                result.insert(segment)
            } else {
                for index in 0..<(characters.count - 1) {
                    result.insert(String(characters[index...index + 1]))
                }
            }
        }
        return result
    }

    private static func diceCoefficient(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let overlap = lhs.intersection(rhs).count
        return (2 * Double(overlap)) / Double(lhs.count + rhs.count)
    }
}
