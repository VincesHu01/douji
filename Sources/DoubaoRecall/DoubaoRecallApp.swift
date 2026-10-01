import AppKit
import SwiftUI

@main
struct DoubaoRecallApp: App {
    @StateObject private var store = IndexStore()

    var body: some Scene {
        WindowGroup("豆迹") {
            RecallView(store: store)
        }
        .defaultSize(width: 520, height: 600)
    }
}

struct RecallView: View {
    @ObservedObject var store: IndexStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("豆迹")
                        .font(.title2.bold())
                    Text("找回你和豆包聊过的内容")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if store.isGuidedRecall {
                        store.leaveGuidedRecall()
                    } else {
                        store.enterGuidedRecall()
                    }
                } label: {
                    Label(store.isGuidedRecall ? "返回搜索" : "引导找回", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                Button {
                    store.syncFromDoubao()
                } label: {
                    if store.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(store.isWorking)
            }

            if store.isGuidedRecall {
                GuidedRecallView(store: store)
            } else {
            HStack(spacing: 8) {
                if !store.isAdvancedSearch {
                    TextField("描述你记得的问题或回答…", text: $store.query)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .onSubmit { store.recordCurrentSearch() }
                } else {
                    Text("高级搜索：组合多个记忆线索")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(store.isAdvancedSearch ? "普通搜索" : "高级搜索") {
                    store.isAdvancedSearch.toggle()
                    store.showFavoritesOnly = false
                }
                .buttonStyle(.bordered)
            }

            if store.isAdvancedSearch {
                AdvancedSearchEditor(store: store)
            }

            HStack(spacing: 8) {
                if store.isAdvancedSearch {
                    Text("每个条件可单独选择检索字段和匹配方式")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    Picker("搜索范围", selection: $store.searchScope) {
                        ForEach(SearchScope.allCases) { scope in
                            Text(scope.label).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Button {
                    store.showFavoritesOnly.toggle()
                } label: {
                    Label("\(store.favoriteIDs.count)", systemImage: store.showFavoritesOnly ? "star.fill" : "star")
                }
                .buttonStyle(.bordered)
                .help(store.showFavoritesOnly ? "显示全部结果" : "只看收藏")
            }

            HStack(spacing: 10) {
                Menu {
                    Picker("结果数量", selection: $store.resultGrouping) {
                        ForEach(ResultGrouping.allCases) { grouping in
                            Text(grouping.label).tag(grouping)
                        }
                    }
                } label: {
                    Label(store.resultGrouping.label, systemImage: "rectangle.stack")
                }

                Menu {
                    Picker("结果排序", selection: $store.resultSort) {
                        ForEach(ResultSort.allCases) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                } label: {
                    Label(store.resultSort.label, systemImage: "arrow.up.arrow.down")
                }

                Menu {
                    ForEach(store.recentSearches) { item in
                        Button {
                            store.useRecentSearch(item)
                        } label: {
                            Text("\(item.query) · \(item.scope.label) · \(item.grouping.label)")
                        }
                    }
                    if !store.recentSearches.isEmpty {
                        Divider()
                        Button("清空最近搜索", role: .destructive) {
                            store.clearRecentSearches()
                        }
                    }
                } label: {
                    Label("最近搜索", systemImage: "clock.arrow.circlepath")
                }
                .disabled(store.recentSearches.isEmpty)

                Spacer()
                if store.hasSearchInput {
                    Text("找到 \(store.hits.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if !store.hasSearchInput && !store.showFavoritesOnly {
                EmptyState(store: store)
            } else if store.hits.isEmpty {
                ContentUnavailableView(
                    store.showFavoritesOnly ? "还没有收藏" : "没有找到",
                    systemImage: store.showFavoritesOnly ? "star" : "magnifyingglass",
                    description: Text(store.showFavoritesOnly ? "在搜索结果中收藏一轮问答，之后可以从这里快速找回。" : "换一种说法、切换搜索范围，或先同步更多历史对话。")
                )
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.hits) { hit in
                            ResultCard(
                                hit: hit,
                                query: store.query,
                                isFavorite: store.isFavorite(hit),
                                toggleFavorite: { store.toggleFavorite(hit) },
                                copy: { store.copyQuestionAnswer(hit) },
                                open: { store.open(hit) }
                            )
                        }
                    }
                }
            }
            }

            Divider()
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let lastSyncAt = store.lastSyncAt {
                        Text("上次同步：\(lastSyncAt, style: .relative)前")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button("完整同步") { store.syncFromDoubao(full: true) }
                    .buttonStyle(.link)
                    .disabled(store.isWorking)
                Button("导入 JSON") { store.importJSON() }
                    .buttonStyle(.link)
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.link)
            }
        }
        .padding(14)
        .frame(width: 520, height: 600)
    }
}

private struct GuidedRecallView: View {
    @ObservedObject var store: IndexStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("逐层梳理")
                        .font(.headline)
                    Text("候选摘要只发送给本机 qwen3:8b，不经过云端")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("重新开始") { store.resetGuidedRecall() }
                    .buttonStyle(.link)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.guidedMessages) { message in
                        GuidedMessageBubble(message: message)
                    }

                    if store.guidedIsWorking {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("本地模型正在比较候选差异…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    if !store.guidedOptions.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(store.guidedOptions, id: \.self) { option in
                                Button(option) { store.submitGuided(option) }
                                    .buttonStyle(.bordered)
                                    .disabled(store.guidedIsWorking)
                            }
                            Text("也可以在下方自由回答，例如“都不是”“不确定”或补充新的记忆。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !store.guidedCandidates.isEmpty {
                        HStack {
                            Text("当前候选 \(store.guidedCandidates.count) 条")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("可随时直接打开")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)

                        ForEach(store.guidedCandidates) { hit in
                            ResultCard(
                                hit: hit,
                                query: "",
                                isFavorite: store.isFavorite(hit),
                                toggleFavorite: { store.toggleFavorite(hit) },
                                copy: { store.copyQuestionAnswer(hit) },
                                open: { store.open(hit) }
                            )
                        }
                    }
                }
            }

            HStack(spacing: 7) {
                TextField("补充你还记得的线索，或直接回答上面的问题…", text: $store.guidedInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.submitGuided() }
                    .disabled(store.guidedIsWorking)
                Button("发送") { store.submitGuided() }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.guidedIsWorking || store.guidedInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct GuidedMessageBubble: View {
    let message: GuidedMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 45) }
            Text(message.text)
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    message.role == .user ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            if message.role == .assistant { Spacer(minLength: 45) }
        }
    }
}

private struct AdvancedSearchEditor: View {
    @ObservedObject var store: IndexStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(store.advancedRules.indices), id: \.self) { index in
                HStack(spacing: 6) {
                    if index == 0 {
                        Text("包含")
                            .frame(width: 42)
                    } else {
                        Picker("关系", selection: $store.advancedRules[index].relation) {
                            ForEach(SearchRelation.allCases) { relation in
                                Text(relation.label).tag(relation)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 58)
                    }

                    Picker("字段", selection: $store.advancedRules[index].scope) {
                        ForEach(SearchScope.allCases) { scope in
                            Text(scope.label).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 92)

                    Picker("匹配", selection: $store.advancedRules[index].matchMode) {
                        ForEach(SearchMatchMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 68)

                    TextField(index == 0 ? "输入第一个关键词或短语" : "输入另一个条件", text: $store.advancedRules[index].query)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        store.removeAdvancedRule(id: store.advancedRules[index].id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("删除这个条件")
                }
            }

            HStack {
                Text("且：同时满足　或：满足任一　不含：排除命中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空") { store.clearAdvancedRules() }
                    .buttonStyle(.link)
                Button("添加条件") { store.addAdvancedRule() }
                    .buttonStyle(.link)
                    .disabled(store.advancedRules.count >= 6)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct EmptyState: View {
    @ObservedObject var store: IndexStore

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "quote.bubble")
                .font(.system(size: 38))
                .foregroundStyle(.tint)
            Text(store.conversations.isEmpty ? "先建立你的对话索引" : "可以开始搜索了")
                .font(.headline)
            Text(store.conversations.isEmpty
                 ? "同步豆包客户端，或导入已有的 JSON 对话记录。所有索引只保存在这台 Mac。"
                 : "已索引 \(store.conversations.count) 个对话、\(store.messageCount) 条消息。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack {
                Button("同步豆包") { store.syncFromDoubao() }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isWorking)
                Button("导入 JSON") { store.importJSON() }
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ResultCard: View {
    let hit: SearchHit
    let query: String
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let copy: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(hit.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("第 \(hit.ordinal) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(hit.matchReason)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.tint.opacity(0.12), in: Capsule())

            if let question = hit.question {
                HighlightedSnippet(
                    prefix: "你问：",
                    text: question,
                    fragments: hit.matchFragments,
                    maxLength: 150
                )
                .font(.subheadline)
                .lineLimit(3)
            }
            if let answer = hit.answer, answer != hit.question {
                HighlightedSnippet(
                    prefix: "豆包：",
                    text: answer,
                    fragments: hit.matchFragments,
                    maxLength: 190
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            }

            HStack {
                if let date = hit.updatedAt {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .help(isFavorite ? "取消收藏" : "收藏这轮问答")
                Button("复制问答", action: copy)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("打开并定位", action: open)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct HighlightedSnippet: View {
    let prefix: String
    let text: String
    let fragments: [String]
    let maxLength: Int

    var body: some View {
        highlightedText(prefix + excerpt)
    }

    private var excerpt: String {
        let characters = Array(text)
        guard characters.count > maxLength else { return text }

        let anchor = fragments.compactMap { fragment -> Int? in
            guard let range = text.range(of: fragment, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) else { return nil }
            return text.distance(from: text.startIndex, to: range.lowerBound)
        }.min() ?? 0

        var start = max(0, anchor - maxLength / 3)
        if start + maxLength > characters.count { start = max(0, characters.count - maxLength) }
        let end = min(characters.count, start + maxLength)
        let content = String(characters[start..<end])
        return (start > 0 ? "…" : "") + content + (end < characters.count ? "…" : "")
    }

    private func highlightedText(_ value: String) -> Text {
        let ordered = fragments.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        guard let fragment = ordered.first(where: {
            value.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
        }), let range = value.range(of: fragment, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) else {
            return Text(value)
        }

        return Text(String(value[..<range.lowerBound]))
            + Text(String(value[range])).bold().foregroundColor(.accentColor)
            + Text(String(value[range.upperBound...]))
    }
}
