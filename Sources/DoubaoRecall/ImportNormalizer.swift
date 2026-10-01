import Foundation

enum ImportError: LocalizedError {
    case unsupportedFormat
    case noConversations

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "无法识别这个 JSON 文件。"
        case .noConversations: "文件中没有找到可导入的对话。"
        }
    }
}

enum ImportNormalizer {
    static func decode(data: Data) throws -> [Conversation] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let conversations = try? decoder.decode([Conversation].self, from: data), !conversations.isEmpty {
            return conversations
        }
        if let envelope = try? decoder.decode(ConversationEnvelope.self, from: data), !envelope.conversations.isEmpty {
            return envelope.conversations
        }

        let object = try JSONSerialization.jsonObject(with: data)
        let rawSessions = findSessionArray(in: object)
        guard let rawSessions else { throw ImportError.unsupportedFormat }

        let conversations = rawSessions.enumerated().compactMap { index, raw in
            normalizeSession(raw, fallbackIndex: index, allowEmpty: false)
        }
        guard !conversations.isEmpty else { throw ImportError.noConversations }
        return conversations
    }

    static func decodeSessionStubs(data: Data) throws -> [Conversation] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let rawSessions = findSessionArray(in: object) else { throw ImportError.unsupportedFormat }
        let conversations = rawSessions.enumerated().compactMap { index, raw in
            normalizeSession(raw, fallbackIndex: index, allowEmpty: true)
        }
        guard !conversations.isEmpty else { throw ImportError.noConversations }
        return conversations
    }

    private static func findSessionArray(in object: Any) -> [[String: Any]]? {
        if let array = object as? [[String: Any]] { return array }
        guard let dictionary = object as? [String: Any] else { return nil }
        if string(dictionary, keys: ["conversationId", "conversation_id", "conversationID", "id"]) != nil,
           messageArray(in: dictionary).isEmpty == false {
            return [dictionary]
        }
        for key in ["conversations", "sessions", "items", "data", "list"] {
            if let array = dictionary[key] as? [[String: Any]] { return array }
            if let nested = dictionary[key], let found = findSessionArray(in: nested) { return found }
        }
        return nil
    }

    private static func normalizeSession(_ raw: [String: Any], fallbackIndex: Int, allowEmpty: Bool) -> Conversation? {
        let id = string(raw, keys: ["conversationId", "conversation_id", "conversationID", "id"])
            ?? "imported-\(fallbackIndex)"
        let title = string(raw, keys: ["title", "name", "conversationTitle"])
            ?? "未命名对话"
        let url = string(raw, keys: ["url", "conversationUrl", "share_url"])
        let updatedAt = date(raw, keys: ["updatedAt", "updated_at", "update_time", "createdAt"])
        let messageObjects = messageArray(in: raw)
        let messages = messageObjects.enumerated().compactMap { index, item in
            normalizeMessage(item, index: index)
        }
        guard allowEmpty || !messages.isEmpty else { return nil }
        return Conversation(id: id, title: title, url: url, updatedAt: updatedAt, messages: messages, recencyRank: fallbackIndex)
    }

    private static func messageArray(in raw: [String: Any]) -> [[String: Any]] {
        for key in ["messages", "messageList", "items", "turns", "history"] {
            if let array = raw[key] as? [[String: Any]] { return array }
            if let nested = raw[key] as? [String: Any] {
                let found = messageArray(in: nested)
                if !found.isEmpty { return found }
            }
        }
        return []
    }

    private static func normalizeMessage(_ raw: [String: Any], index: Int) -> ChatMessage? {
        let text = extractText(raw)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let id = string(raw, keys: ["messageId", "message_id", "id", "localId"]) ?? "message-\(index)"
        let role = string(raw, keys: ["role", "sender", "author", "message_type", "type"]) ?? "unknown"
        let ordinal = integer(raw, keys: ["ordinal", "index", "index_in_conv", "position"]) ?? index + 1
        return ChatMessage(
            id: id,
            role: role,
            text: text,
            createdAt: date(raw, keys: ["createdAt", "created_at", "create_time", "timestamp"]),
            ordinal: ordinal
        )
    }

    private static func extractText(_ raw: [String: Any]) -> String {
        for key in ["text", "content", "message", "body", "output"] {
            if let value = raw[key] as? String { return value }
            if let parts = raw[key] as? [String] { return parts.joined(separator: "\n") }
            if let dictionary = raw[key] as? [String: Any] {
                let nested = extractText(dictionary)
                if !nested.isEmpty { return nested }
            }
            if let array = raw[key] as? [[String: Any]] {
                let combined = array.map(extractText).filter { !$0.isEmpty }.joined(separator: "\n")
                if !combined.isEmpty { return combined }
            }
        }
        return ""
    }

    private static func string(_ raw: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = raw[key] as? String, !value.isEmpty { return value }
            if let value = raw[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    private static func integer(_ raw: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = raw[key] as? Int { return value }
            if let value = raw[key] as? NSNumber { return value.intValue }
            if let value = raw[key] as? String, let parsed = Int(value) { return parsed }
        }
        return nil
    }

    private static func date(_ raw: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let value = raw[key] as? TimeInterval {
                return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
            }
            if let value = raw[key] as? String {
                if let numeric = TimeInterval(value) {
                    return Date(timeIntervalSince1970: numeric > 10_000_000_000 ? numeric / 1000 : numeric)
                }
                if let parsed = ISO8601DateFormatter().date(from: value) { return parsed }
            }
        }
        return nil
    }
}
