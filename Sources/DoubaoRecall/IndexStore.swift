import AppKit
import Foundation

@MainActor
final class IndexStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var query = ""
    @Published var isAdvancedSearch = false
    @Published var isGuidedRecall = false
    @Published var advancedRules: [AdvancedSearchRule] = [
        AdvancedSearchRule(),
        AdvancedSearchRule(relation: .and)
    ]
    @Published var searchScope: SearchScope = .all
    @Published var resultSort: ResultSort = .relevance
    @Published var resultGrouping: ResultGrouping = .bestPerConversation
    @Published var showFavoritesOnly = false
    @Published var status = "尚未建立索引"
    @Published var isWorking = false
    @Published var lastSyncAt: Date?
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var recentSearches: [RecentSearch] = []
    @Published var guidedInput = ""
    @Published private(set) var guidedMessages: [GuidedMessage] = []
    @Published private(set) var guidedCandidates: [SearchHit] = []
    @Published private(set) var guidedOptions: [String] = []
    @Published private(set) var guidedIsWorking = false
    private var guidedExcludedIDs: Set<String> = []
    private var guidedRejectedTitles: [String] = []

    private let adapter = DoubaoAdapter()
    private let lastSyncKey = "DoubaoRecall.lastSyncAt"
    private let favoritesKey = "DoubaoRecall.favoriteTurnIDs"
    private let recentSearchesKey = "DoubaoRecall.recentSearches"
    private let guidedService = GuidedRecallService()

    var hits: [SearchHit] {
        if isAdvancedSearch {
            return SearchEngine.advancedSearch(
                advancedRules,
                in: conversations,
                sort: resultSort,
                grouping: resultGrouping
            )
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = trimmed.isEmpty
            ? (showFavoritesOnly ? SearchEngine.browse(in: conversations) : [])
            : SearchEngine.search(
                trimmed,
                in: conversations,
                scope: searchScope,
                sort: resultSort,
                grouping: resultGrouping
            )
        return showFavoritesOnly ? candidates.filter { favoriteIDs.contains($0.id) } : candidates
    }

    var messageCount: Int {
        conversations.reduce(0) { $0 + $1.messages.count }
    }

    var hasSearchInput: Bool {
        if isAdvancedSearch {
            return advancedRules.contains { !$0.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        loadSavedIndex()
        let timestamp = UserDefaults.standard.double(forKey: lastSyncKey)
        if timestamp > 0 { lastSyncAt = Date(timeIntervalSince1970: timestamp) }
        favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        if let data = UserDefaults.standard.data(forKey: recentSearchesKey),
           let saved = try? JSONDecoder().decode([RecentSearch].self, from: data) {
            recentSearches = saved
        }
    }

    func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        do {
            var imported: [Conversation] = []
            for url in panel.urls {
                imported.append(contentsOf: try ImportNormalizer.decode(data: Data(contentsOf: url)))
            }
            merge(imported)
            try saveIndex()
            status = "已导入 \(imported.count) 个对话"
        } catch {
            status = error.localizedDescription
        }
    }

    func syncFromDoubao(full: Bool = false) {
        guard !isWorking else { return }
        isWorking = true
        status = full ? "正在完整同步全部会话…" : "正在快速同步新增和最近活跃会话…"
        let existingIDs = Set(conversations.map(\.id))
        Task {
            do {
                let stream = AsyncThrowingStream<SyncEvent, Error> { continuation in
                    Task.detached(priority: .userInitiated) {
                        do {
                            let batch = try DoubaoAdapter().sync(existingIDs: existingIDs, full: full) { current, total in
                                continuation.yield(.progress(current, total))
                            }
                            continuation.yield(.finished(batch))
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }

                for try await event in stream {
                    switch event {
                    case .progress(let current, let total):
                        status = total == 0 ? "没有需要更新的会话" : "正在同步 \(current)/\(total)…"
                    case .finished(let batch):
                        let before = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
                        let added = batch.conversations.filter { before[$0.id] == nil }.count
                        let updated = batch.conversations.filter { before[$0.id] != nil && before[$0.id] != $0 }.count
                        merge(batch.conversations)
                        try saveIndex()
                        lastSyncAt = Date()
                        UserDefaults.standard.set(lastSyncAt?.timeIntervalSince1970, forKey: lastSyncKey)
                        status = "同步完成：新增 \(added)，更新 \(updated)，失败 \(batch.failureCount)；共 \(conversations.count) 个对话"
                    }
                }
            } catch {
                status = error.localizedDescription
            }
            isWorking = false
        }
    }

    func open(_ hit: SearchHit) {
        recordCurrentSearch()
        status = "正在打开《\(hit.title)》并定位命中问答…"
        Task {
            let located = await adapter.openAndLocate(hit)
            status = located
                ? "已在豆包中定位并高亮第 \(hit.ordinal) 条命中问答"
                : "已打开原对话，但没有自动找到文本；可能需要先重新同步这段对话"
        }
    }

    func isFavorite(_ hit: SearchHit) -> Bool {
        favoriteIDs.contains(hit.id)
    }

    func toggleFavorite(_ hit: SearchHit) {
        recordCurrentSearch()
        if favoriteIDs.contains(hit.id) {
            favoriteIDs.remove(hit.id)
            status = "已取消收藏"
        } else {
            favoriteIDs.insert(hit.id)
            status = "已收藏这轮问答"
        }
        UserDefaults.standard.set(Array(favoriteIDs).sorted(), forKey: favoritesKey)
    }

    func copyQuestionAnswer(_ hit: SearchHit) {
        recordCurrentSearch()
        var sections = ["# \(hit.title)"]
        if let question = hit.question { sections.append("## 我的问题\n\(question)") }
        if let answer = hit.answer { sections.append("## 豆包回答\n\(answer)") }
        sections.append("对话位置：第 \(hit.ordinal) 条")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sections.joined(separator: "\n\n"), forType: .string)
        status = "已复制这轮问答"
    }

    func recordCurrentSearch() {
        guard !isAdvancedSearch, !isGuidedRecall else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = RecentSearch(
            query: trimmed,
            scopeRawValue: searchScope.rawValue,
            sort: resultSort,
            grouping: resultGrouping
        )
        recentSearches.removeAll { $0.id == item.id }
        recentSearches.insert(item, at: 0)
        recentSearches = Array(recentSearches.prefix(8))
        if let data = try? JSONEncoder().encode(recentSearches) {
            UserDefaults.standard.set(data, forKey: recentSearchesKey)
        }
    }

    func useRecentSearch(_ item: RecentSearch) {
        query = item.query
        searchScope = item.scope
        resultSort = item.sort
        resultGrouping = item.grouping
        showFavoritesOnly = false
        status = "已恢复上次检索条件"
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
        status = "已清空最近搜索"
    }

    func addAdvancedRule() {
        guard advancedRules.count < 6 else {
            status = "高级搜索最多支持 6 个条件"
            return
        }
        advancedRules.append(AdvancedSearchRule(relation: .and))
    }

    func removeAdvancedRule(id: UUID) {
        guard advancedRules.count > 1 else {
            advancedRules[0].query = ""
            return
        }
        advancedRules.removeAll { $0.id == id }
        if !advancedRules.isEmpty { advancedRules[0].relation = .and }
    }

    func clearAdvancedRules() {
        advancedRules = [AdvancedSearchRule(), AdvancedSearchRule(relation: .and)]
        status = "已清空高级搜索条件"
    }

    func enterGuidedRecall() {
        isGuidedRecall = true
        isAdvancedSearch = false
        showFavoritesOnly = false
        if guidedMessages.isEmpty {
            guidedMessages = [GuidedMessage(
                role: .assistant,
                text: "告诉我你还记得的大概方向。可以很模糊，例如：‘好像聊过论文创新，但不记得在哪个对话’。"
            )]
        }
        status = "引导找回只调用本机 qwen3:8b，候选内容不会上传"
    }

    func leaveGuidedRecall() {
        isGuidedRecall = false
    }

    func resetGuidedRecall() {
        guidedInput = ""
        guidedCandidates = []
        guidedOptions = []
        guidedExcludedIDs = []
        guidedRejectedTitles = []
        guidedMessages = [GuidedMessage(
            role: .assistant,
            text: "我们重新开始。你对目标对话还记得什么？一个主题、场景或零碎词语都可以。"
        )]
        status = "已重新开始引导找回"
    }

    func submitGuided(_ suggestedAnswer: String? = nil) {
        guard !guidedIsWorking else { return }
        let answer = (suggestedAnswer ?? guidedInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        guidedInput = ""
        guidedOptions = []
        guidedMessages.append(GuidedMessage(role: .user, text: answer))
        guidedIsWorking = true
        let rejectedAll = Self.isGuidedRejection(answer)
        if rejectedAll, !guidedCandidates.isEmpty {
            guidedExcludedIDs.formUnion(guidedCandidates.map(\.id))
            guidedRejectedTitles.append(contentsOf: guidedCandidates.map(\.title))
            guidedRejectedTitles = Array(Set(guidedRejectedTitles)).sorted()
            guidedCandidates = []
            guidedMessages.append(GuidedMessage(
                role: .assistant,
                text: "明白，这一批都排除。我会回到上一层，换一组候选和提问方向。"
            ))
            status = "正在排除当前候选并扩大搜索范围…"
        } else {
            status = "本地 qwen3:8b 正在分析候选…"
        }

        Task {
            do {
                if guidedCandidates.isEmpty {
                    guidedCandidates = try await initialGuidedCandidates()
                }
                guard !guidedCandidates.isEmpty else {
                    guidedMessages.append(GuidedMessage(
                        role: .assistant,
                        text: "目前还没有召回候选。再告诉我一个更具体的名词、人物、用途，或你记得它出现在问题还是回答里。"
                    ))
                    status = "线索过于宽泛，请再补充一点"
                    guidedIsWorking = false
                    return
                }

                if guidedCandidates.count == 1 {
                    guidedMessages.append(GuidedMessage(role: .assistant, text: "已经聚焦到一轮最可能的问答，你可以直接打开原对话。"))
                    status = "已定位到 1 个候选"
                    guidedIsWorking = false
                    return
                }

                let decision = try await guidedService.refine(
                    candidates: guidedCandidates,
                    messages: guidedMessages
                )
                let allowed = Set(decision.remaining.compactMap { code -> Int? in
                    guard code.first == "C" else { return nil }
                    return Int(code.dropFirst())
                })
                if !allowed.isEmpty {
                    guidedCandidates = guidedCandidates.enumerated().compactMap { index, hit in
                        allowed.contains(index) ? hit : nil
                    }
                }
                var options = decision.ready ? [] : Array(decision.options.prefix(4))
                if !decision.ready,
                   !options.contains(where: Self.isGuidedRejection) {
                    options.append("都不是这些")
                }
                guidedOptions = options
                guidedMessages.append(GuidedMessage(role: .assistant, text: decision.question))
                status = decision.ready
                    ? "已聚焦到 \(guidedCandidates.count) 个候选"
                    : "还剩 \(guidedCandidates.count) 个候选，继续回答即可缩小范围"
            } catch {
                guidedMessages.append(GuidedMessage(
                    role: .assistant,
                    text: "本地模型暂时没有完成分析，但候选结果已经保留。你可以继续补充线索，或直接查看候选。"
                ))
                status = error.localizedDescription
            }
            guidedIsWorking = false
        }
    }

    private func initialGuidedCandidates() async throws -> [SearchHit] {
        let cue = guidedMessages
            .filter { $0.role == .user && !Self.isGuidedRejection($0.text) }
            .map(\.text)
            .joined(separator: " ")
        var ordered = SearchEngine.search(
            cue,
            in: conversations,
            grouping: .allTurns,
            limit: 40
        ).filter { !guidedExcludedIDs.contains($0.id) }
        ordered = Array(ordered.prefix(12))
        var seen = Set(ordered.map(\.id))

        if ordered.count < 4 {
            let terms = try await guidedService.expandTerms(
                cue: cue,
                titles: conversations.map(\.title),
                rejectedTitles: guidedRejectedTitles
            )
            for term in terms {
                for hit in SearchEngine.search(term, in: conversations, grouping: .allTurns, limit: 40) {
                    guard !guidedExcludedIDs.contains(hit.id) else { continue }
                    if seen.insert(hit.id).inserted { ordered.append(hit) }
                    if ordered.count >= 12 { break }
                }
                if ordered.count >= 12 { break }
            }
        }
        if ordered.count < 4 {
            for hit in SearchEngine.browse(in: conversations) {
                guard !guidedExcludedIDs.contains(hit.id) else { continue }
                if seen.insert(hit.id).inserted { ordered.append(hit) }
                if ordered.count >= 12 { break }
            }
        }
        return Array(ordered.prefix(12))
    }

    nonisolated static func isGuidedRejection(_ value: String) -> Bool {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: #"[\p{P}\p{S}\s]+"#, with: "", options: .regularExpression)
        let phrases = [
            "都不是", "全都不是", "没有一个", "不是这些", "换一批", "其他的", "都不对",
            "noneofthem", "neither", "none"
        ]
        return phrases.contains { normalized.contains($0) }
    }

    private func merge(_ incoming: [Conversation]) {
        var byID = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        for conversation in incoming { byID[conversation.id] = conversation }
        conversations = byID.values.sorted {
            ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }

    private func loadSavedIndex() {
        do {
            let data = try Data(contentsOf: indexURL())
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            conversations = try decoder.decode([Conversation].self, from: data)
            status = "已加载 \(conversations.count) 个对话，\(messageCount) 条消息"
        } catch {
            status = "尚未建立索引"
        }
    }

    private func saveIndex() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = try indexURL(createDirectory: true)
        try encoder.encode(conversations).write(to: url, options: .atomic)
    }

    private func indexURL(createDirectory: Bool = false) throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("DoubaoRecall", isDirectory: true)
        if createDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("index.json")
    }
}

private enum SyncEvent: Sendable {
    case progress(Int, Int)
    case finished(SyncBatch)
}
