import Foundation
import Testing
@testable import DoubaoRecall

@Test func fuzzyChineseSearchFindsRelatedTurn() {
    let conversation = Conversation(
        id: "c1",
        title: "本地知识库",
        url: "https://www.doubao.com/chat/c1",
        updatedAt: Date(),
        messages: [
            ChatMessage(id: "m1", role: "user", text: "如果不上传服务器，语义检索应该怎样实现？", createdAt: nil, ordinal: 1),
            ChatMessage(id: "m2", role: "assistant", text: "可以在本地运行小型向量模型并保存索引。", createdAt: nil, ordinal: 2)
        ]
    )

    let hits = SearchEngine.search("本地语义搜索", in: [conversation])
    #expect(!hits.isEmpty)
    #expect(hits.first?.conversationID == "c1")
    #expect(hits.first?.question?.contains("语义检索") == true)
}

@Test func oneQuestionAnswerTurnProducesOnlyOneResult() {
    let conversation = Conversation(
        id: "c1",
        title: "增发讨论",
        url: nil,
        updatedAt: nil,
        messages: [
            ChatMessage(id: "q1", role: "user", text: "定向增发有什么好处？", createdAt: nil, ordinal: 1),
            ChatMessage(id: "a1", role: "assistant", text: "可以补充资本并引入战略投资者。", createdAt: nil, ordinal: 2)
        ]
    )

    let hits = SearchEngine.search("增发有什么好处", in: [conversation])
    #expect(hits.count == 1)
    #expect(hits.first?.question?.contains("定向增发") == true)
    #expect(hits.first?.answer?.contains("补充资本") == true)
}

@Test func genericQuestionWordsDoNotReturnUnrelatedConversations() {
    let relevant = Conversation(
        id: "relevant",
        title: "增发讨论",
        url: nil,
        updatedAt: nil,
        messages: [
            ChatMessage(id: "q1", role: "user", text: "存量转让与定向增发有什么好处？", createdAt: nil, ordinal: 1),
            ChatMessage(id: "a1", role: "assistant", text: "定向增发可以补充公司资本。", createdAt: nil, ordinal: 2)
        ]
    )
    let unrelated = Conversation(
        id: "unrelated",
        title: "数值问题",
        url: nil,
        updatedAt: nil,
        messages: [
            ChatMessage(id: "q2", role: "user", text: "这个结果为什么是负数？", createdAt: nil, ordinal: 1),
            ChatMessage(id: "a2", role: "assistant", text: "需要检查计算过程和数据范围。", createdAt: nil, ordinal: 2)
        ]
    )

    let hits = SearchEngine.search("增发有什么好处", in: [relevant, unrelated])
    #expect(hits.map(\.conversationID) == ["relevant"])
}

@Test func searchScopeSeparatesQuestionsAndAnswers() {
    let conversation = Conversation(
        id: "scope",
        title: "融资讨论",
        url: nil,
        updatedAt: nil,
        messages: [
            ChatMessage(id: "q", role: "user", text: "公司怎样融资？", createdAt: nil, ordinal: 1),
            ChatMessage(id: "a", role: "assistant", text: "可以考虑定向增发补充资本。", createdAt: nil, ordinal: 2)
        ]
    )

    #expect(SearchEngine.search("定向增发", in: [conversation], scope: .questions).isEmpty)
    #expect(SearchEngine.search("定向增发", in: [conversation], scope: .answers).count == 1)
}

@Test func titleScopeReturnsOneResultPerConversation() {
    let conversation = Conversation(
        id: "title",
        title: "旅游经济研究",
        url: nil,
        updatedAt: nil,
        messages: [
            ChatMessage(id: "q1", role: "user", text: "第一个问题", createdAt: nil, ordinal: 1),
            ChatMessage(id: "a1", role: "assistant", text: "第一个回答", createdAt: nil, ordinal: 2),
            ChatMessage(id: "q2", role: "user", text: "第二个问题", createdAt: nil, ordinal: 3),
            ChatMessage(id: "a2", role: "assistant", text: "第二个回答", createdAt: nil, ordinal: 4)
        ]
    )

    let hits = SearchEngine.search("旅游经济", in: [conversation], scope: .titles)
    #expect(hits.count == 1)
    #expect(hits.first?.matchReason == "标题匹配")
}

@Test func bestPerConversationRemovesRepeatedConversationCards() {
    let conversation = Conversation(
        id: "grouped",
        title: "增发讨论",
        url: nil,
        updatedAt: nil,
        messages: [
            ChatMessage(id: "q1", role: "user", text: "增发有什么好处", createdAt: nil, ordinal: 1),
            ChatMessage(id: "a1", role: "assistant", text: "补充资本", createdAt: nil, ordinal: 2),
            ChatMessage(id: "q2", role: "user", text: "增发还有什么好处", createdAt: nil, ordinal: 3),
            ChatMessage(id: "a2", role: "assistant", text: "引入投资者", createdAt: nil, ordinal: 4)
        ]
    )

    #expect(SearchEngine.search("增发有什么好处", in: [conversation]).count == 1)
    #expect(SearchEngine.search("增发有什么好处", in: [conversation], grouping: .allTurns).count == 2)
}

@Test func recentSortUsesTurnDateBeforeScore() {
    let older = Date(timeIntervalSince1970: 1_000)
    let newer = Date(timeIntervalSince1970: 2_000)
    let olderConversation = Conversation(
        id: "older",
        title: "较早对话",
        url: nil,
        updatedAt: older,
        messages: [
            ChatMessage(id: "exact", role: "user", text: "本地语义搜索", createdAt: older, ordinal: 1),
            ChatMessage(id: "a1", role: "assistant", text: "回答", createdAt: older, ordinal: 2)
        ],
        recencyRank: 10
    )
    let newerConversation = Conversation(
        id: "newer",
        title: "最近对话",
        url: nil,
        updatedAt: newer,
        messages: [
            ChatMessage(id: "newer", role: "user", text: "怎样做本地语义检索", createdAt: newer, ordinal: 3),
            ChatMessage(id: "a2", role: "assistant", text: "回答", createdAt: newer, ordinal: 4)
        ],
        recencyRank: 0
    )

    let hits = SearchEngine.search("本地语义搜索", in: [olderConversation, newerConversation], sort: .recent)
    #expect(hits.first?.conversationID == "newer")
}

@Test func advancedAndRequiresSameQuestionAnswerTurn() {
    let conversation = Conversation(
        id: "advanced-and",
        title: "融资讨论",
        url: nil,
        updatedAt: nil,
        messages: [
            ChatMessage(id: "q1", role: "user", text: "定向增发有什么好处", createdAt: nil, ordinal: 1),
            ChatMessage(id: "a1", role: "assistant", text: "可以引入战略投资者", createdAt: nil, ordinal: 2),
            ChatMessage(id: "q2", role: "user", text: "存量转让是什么", createdAt: nil, ordinal: 3),
            ChatMessage(id: "a2", role: "assistant", text: "股份来自老股东", createdAt: nil, ordinal: 4)
        ]
    )
    let rules = [
        AdvancedSearchRule(scope: .questions, query: "定向增发"),
        AdvancedSearchRule(relation: .and, scope: .answers, query: "战略投资者")
    ]

    let hits = SearchEngine.advancedSearch(rules, in: [conversation])
    #expect(hits.count == 1)
    #expect(hits.first?.messageID == "q1")
    #expect(hits.first?.matchReason == "同时命中 2 个条件")
}

@Test func advancedOrAndNotCombineResults() {
    let conversations = [
        Conversation(id: "a", title: "融资", url: nil, updatedAt: nil, messages: [
            ChatMessage(id: "qa", role: "user", text: "定向增发", createdAt: nil, ordinal: 1),
            ChatMessage(id: "aa", role: "assistant", text: "补充资本", createdAt: nil, ordinal: 2)
        ]),
        Conversation(id: "b", title: "股权", url: nil, updatedAt: nil, messages: [
            ChatMessage(id: "qb", role: "user", text: "存量转让", createdAt: nil, ordinal: 1),
            ChatMessage(id: "ab", role: "assistant", text: "老股交易，不涉及旅游", createdAt: nil, ordinal: 2)
        ])
    ]
    let rules = [
        AdvancedSearchRule(query: "定向增发"),
        AdvancedSearchRule(relation: .or, query: "存量转让"),
        AdvancedSearchRule(relation: .not, query: "旅游")
    ]

    let hits = SearchEngine.advancedSearch(rules, in: conversations, grouping: .allTurns)
    #expect(hits.map(\.conversationID) == ["a"])
}

@Test func exactModeDoesNotUseFuzzyFragments() {
    let conversation = Conversation(
        id: "exact",
        title: "检索",
        url: nil,
        updatedAt: nil,
        messages: [
            ChatMessage(id: "q", role: "user", text: "如何进行本地语义检索", createdAt: nil, ordinal: 1),
            ChatMessage(id: "a", role: "assistant", text: "回答", createdAt: nil, ordinal: 2)
        ]
    )

    #expect(SearchEngine.search("本地检索", in: [conversation], matchMode: .fuzzy).count == 1)
    #expect(SearchEngine.search("本地检索", in: [conversation], matchMode: .exact).isEmpty)
}

@Test func guidedRejectionRecognizesNaturalFreeText() {
    #expect(IndexStore.isGuidedRejection("好像都不是，再换一批吧"))
    #expect(IndexStore.isGuidedRejection("这几个都不对"))
    #expect(!IndexStore.isGuidedRejection("第三个比较接近"))
    #expect(!IndexStore.isGuidedRejection("我不确定"))
}

@Test func messageLocatorPrefersMatchedAnswerText() {
    let hit = SearchHit(
        id: "c:q", conversationID: "c", messageID: "message-0", title: "测试",
        matchedText: "回答中的命中内容", question: "用户提出的问题内容", answer: "回答中的命中内容",
        ordinal: 1, score: 10, matchReason: "回答原文命中", matchFragments: ["命中"],
        url: nil, updatedAt: nil, recencyRank: nil
    )
    let anchors = DoubaoAdapter.anchorCandidates(for: hit)
    #expect(anchors.first == "回答中的命中内容")
    #expect(anchors.contains("用户提出的问题内容"))
    #expect(DoubaoAdapter.focusCandidates(for: hit).first == "命中")
}

@Test func messageLocatorEncodesMessageIDInsideTopLevelObject() throws {
    let json = try DoubaoAdapter.locatorPayloadJSON(
        anchors: ["问题"], focusTerms: ["回答"], messageID: "message-0"
    )
    let data = try #require(json.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["messageID"] as? String == "message-0")
    #expect(object["anchors"] as? [String] == ["问题"])
}

@Test func importsCommonConversationJSON() throws {
    let json = """
    {"conversations":[{"conversation_id":"42","title":"测试对话","messages":[{"message_id":"1","role":"user","content":"原问题"},{"message_id":"2","role":"assistant","content":"原回答"}]}]}
    """
    let conversations = try ImportNormalizer.decode(data: Data(json.utf8))
    #expect(conversations.count == 1)
    #expect(conversations[0].messages.count == 2)
    #expect(conversations[0].id == "42")
}

@Test func importsSessionListBeforeHydration() throws {
    let json = """
    {"sessions":[{"conversationId":"42","title":"只有标题"}]}
    """
    let conversations = try ImportNormalizer.decodeSessionStubs(data: Data(json.utf8))
    #expect(conversations.count == 1)
    #expect(conversations[0].id == "42")
    #expect(conversations[0].messages.isEmpty)
}
