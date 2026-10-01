import Foundation

enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case questions
    case answers
    case titles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "全部"
        case .questions: "我的问题"
        case .answers: "豆包回答"
        case .titles: "对话标题"
        }
    }
}

enum ResultSort: String, CaseIterable, Identifiable, Codable, Sendable {
    case relevance
    case recent

    var id: String { rawValue }
    var label: String { self == .relevance ? "相关度优先" : "最近聊过" }
}

enum ResultGrouping: String, CaseIterable, Identifiable, Codable, Sendable {
    case bestPerConversation
    case allTurns

    var id: String { rawValue }
    var label: String { self == .bestPerConversation ? "每个对话 1 条" : "全部命中问答" }
}

enum SearchRelation: String, CaseIterable, Identifiable, Sendable {
    case and
    case or
    case not

    var id: String { rawValue }
    var label: String {
        switch self {
        case .and: "且"
        case .or: "或"
        case .not: "不含"
        }
    }
}

enum SearchMatchMode: String, CaseIterable, Identifiable, Sendable {
    case fuzzy
    case exact

    var id: String { rawValue }
    var label: String { self == .fuzzy ? "模糊" : "精确" }
}

struct AdvancedSearchRule: Identifiable, Hashable, Sendable {
    let id: UUID
    var relation: SearchRelation
    var scope: SearchScope
    var matchMode: SearchMatchMode
    var query: String

    init(
        id: UUID = UUID(),
        relation: SearchRelation = .and,
        scope: SearchScope = .all,
        matchMode: SearchMatchMode = .fuzzy,
        query: String = ""
    ) {
        self.id = id
        self.relation = relation
        self.scope = scope
        self.matchMode = matchMode
        self.query = query
    }
}

struct RecentSearch: Codable, Identifiable, Hashable, Sendable {
    let query: String
    let scopeRawValue: String
    let sort: ResultSort
    let grouping: ResultGrouping

    var id: String { "\(query)|\(scopeRawValue)|\(sort.rawValue)|\(grouping.rawValue)" }
    var scope: SearchScope { SearchScope(rawValue: scopeRawValue) ?? .all }
}

struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let role: String
    let text: String
    let createdAt: Date?
    let ordinal: Int

    var isUser: Bool {
        let value = role.lowercased()
        return value == "user" || value == "human" || value.contains("用户")
    }
}

struct Conversation: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var url: String?
    var updatedAt: Date?
    var messages: [ChatMessage]
    var recencyRank: Int? = nil
}

struct SearchHit: Identifiable, Hashable, Sendable {
    let id: String
    let conversationID: String
    let messageID: String
    let title: String
    let matchedText: String
    let question: String?
    let answer: String?
    let ordinal: Int
    let score: Double
    let matchReason: String
    let matchFragments: [String]
    let url: String?
    let updatedAt: Date?
    let recencyRank: Int?
}

struct SyncBatch: Sendable {
    let conversations: [Conversation]
    let listedCount: Int
    let attemptedCount: Int
    let failureCount: Int
}

struct ConversationEnvelope: Codable {
    let conversations: [Conversation]
}
