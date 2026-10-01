import AppKit
import Foundation

enum AdapterError: LocalizedError {
    case cliUnavailable
    case commandFailed(String)
    case malformedOutput

    var errorDescription: String? {
        switch self {
        case .cliUnavailable:
            "已找到豆包客户端，但尚未安装 doubao-cli。当前可先导入 JSON 验证搜索。"
        case .commandFailed(let detail):
            "豆包同步失败：\(detail)"
        case .malformedOutput:
            "doubao-cli 返回了无法识别的数据。"
        }
    }
}

struct DoubaoAdapter: Sendable {
    private var isolatedRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/doubao-recall", isDirectory: true)
    }

    private var isolatedCLI: URL {
        isolatedRoot.appendingPathComponent("tooling/bin/doubao")
    }

    private var sandboxedDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.bot.neotix.doubao/Data/Library/Application Support/Doubao", isDirectory: true)
    }

    private var officialDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Doubao", isDirectory: true)
    }

    func isCLIAvailable() -> Bool {
        if FileManager.default.isExecutableFile(atPath: isolatedCLI.path) { return true }
        return run(["/usr/bin/which", "doubao"]).status == 0
    }

    func sync(
        existingIDs: Set<String> = [],
        full: Bool = false,
        progress: ((Int, Int) -> Void)? = nil
    ) throws -> SyncBatch {
        guard isCLIAvailable() else { throw AdapterError.cliUnavailable }
        try ensureCDP()
        let list = runDoubao(["--app", "doubao", "sessions", "list", "--json"])
        guard list.status == 0 else { throw AdapterError.commandFailed(list.error) }
        guard let data = list.output.data(using: .utf8) else { throw AdapterError.malformedOutput }

        let listed = try ImportNormalizer.decodeSessionStubs(data: data)
        let targets: [Conversation]
        if full || existingIDs.isEmpty {
            targets = listed
        } else {
            // The CLI session list is ordered by recent activity. Refresh every
            // new conversation plus the ten most recently active existing ones.
            targets = listed.enumerated().compactMap { index, conversation in
                (!existingIDs.contains(conversation.id) || index < 10) ? conversation : nil
            }
        }

        var hydrated: [Conversation] = []
        var failures = 0
        progress?(0, targets.count)
        for (index, conversation) in targets.enumerated() {
            let read = runDoubao([
                "--app", "doubao", "sessions", "read",
                conversation.id, "--limit", "1000", "--json"
            ])
            if read.status == 0,
               let payload = read.output.data(using: .utf8),
               let detail = try? ImportNormalizer.decode(data: payload).first {
                var merged = detail
                if merged.title == "未命名对话" { merged.title = conversation.title }
                if merged.url == nil { merged.url = conversation.url }
                if merged.updatedAt == nil { merged.updatedAt = conversation.updatedAt }
                merged.recencyRank = conversation.recencyRank
                hydrated.append(merged)
            } else {
                failures += 1
            }
            progress?(index + 1, targets.count)
        }
        return SyncBatch(
            conversations: hydrated.filter { !$0.messages.isEmpty },
            listedCount: listed.count,
            attemptedCount: targets.count,
            failureCount: failures
        )
    }

    func openAndLocate(_ hit: SearchHit) async -> Bool {
        if isCLIAvailable() {
            let opened = await Task.detached(priority: .userInitiated) {
                try? ensureCDP()
                let result = runDoubao(["--app", "doubao", "sessions", "open", hit.conversationID])
                return result.status == 0
            }.value
            guard opened else { return false }
            try? await Task.sleep(for: .milliseconds(900))
            for attempt in 0..<3 {
                if (try? await locateMessage(hit)) == true { return true }
                if attempt < 2 { try? await Task.sleep(for: .milliseconds(650)) }
            }
            return false
        }

        let fallback = hit.url.flatMap(URL.init(string:))
            ?? URL(string: "https://www.doubao.com/chat/\(hit.conversationID)")!
        _ = await MainActor.run { NSWorkspace.shared.open(fallback) }
        return false
    }

    static func anchorCandidates(for hit: SearchHit) -> [String] {
        let prefersAnswer = hit.matchReason.contains("回答")
        let ordered = prefersAnswer
            ? [hit.answer, hit.question, hit.matchedText]
            : [hit.question, hit.answer, hit.matchedText]
        var seen = Set<String>()
        return ordered.compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 6, seen.insert(trimmed).inserted else { return nil }
            return String(trimmed.prefix(140))
        }
    }

    static func focusCandidates(for hit: SearchHit) -> [String] {
        var seen = Set<String>()
        return (hit.matchFragments + [hit.matchedText]).compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard trimmed.count >= 2, seen.insert(key).inserted else { return nil }
            return String(trimmed.prefix(90))
        }
    }

    static func locatorPayloadJSON(anchors: [String], focusTerms: [String], messageID: String) throws -> String {
        let payload: [String: Any] = [
            "anchors": anchors,
            "focusTerms": focusTerms,
            "messageID": messageID
        ]
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw AdapterError.malformedOutput
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let result = String(data: data, encoding: .utf8) else {
            throw AdapterError.malformedOutput
        }
        return result
    }

    private func locateMessage(_ hit: SearchHit) async throws -> Bool {
        let targetsURL = URL(string: "http://127.0.0.1:9225/json/list")!
        var target: CDPTarget?
        for _ in 0..<15 {
            let (data, _) = try await URLSession.shared.data(from: targetsURL)
            let targets = try JSONDecoder().decode([CDPTarget].self, from: data)
            target = targets.first {
                $0.type == "page" && $0.url.contains("doubao-chat/chat/\(hit.conversationID)")
            }
            if target != nil { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard let websocketURL = target?.webSocketDebuggerUrl else { return false }

        let anchors = Self.anchorCandidates(for: hit)
        guard !anchors.isEmpty else { return false }
        let locatorPayloadJSON = try Self.locatorPayloadJSON(
            anchors: anchors,
            focusTerms: Self.focusCandidates(for: hit),
            messageID: hit.messageID
        )
        let expression = """
        (async () => {
          const locator = \(locatorPayloadJSON);
          const anchors = locator.anchors;
          const focusTerms = locator.focusTerms;
          const preferredMessageId = locator.messageID;
          const normalize = value => (value || '').toLowerCase().replace(/[\\p{P}\\p{S}\\s]+/gu, '');
          const needles = anchors.map(normalize).filter(value => value.length >= 6).map(value => value.slice(0, 90));
          const find = () => {
            if (preferredMessageId && !preferredMessageId.startsWith('message-')) {
              const exact = document.querySelector('[data-message-id="' + CSS.escape(preferredMessageId) + '"]');
              if (exact) return exact;
            }
            return [...document.querySelectorAll('[data-testid="message_content"], [data-testid="message_text_content"]')]
              .find(el => {
                const text = normalize(el.innerText || el.textContent);
                return needles.some(needle => text.includes(needle));
              });
          };
          const scrollables = [...document.querySelectorAll('*')]
            .filter(el => el.scrollHeight > el.clientHeight + 300 && el.clientHeight > 300)
            .sort((a, b) => b.scrollHeight - a.scrollHeight);
          const scroller = scrollables[0];
          if (!scroller) return {found: false, reason: 'no-scroller'};
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          let match = find();
          const step = Math.max(300, Math.floor(scroller.clientHeight * 0.72));
          for (let top = 0; !match && top <= scroller.scrollHeight; top += step) {
            scroller.scrollTop = top;
            scroller.dispatchEvent(new Event('scroll', {bubbles: true}));
            await sleep(85);
            match = find();
          }
          if (!match) return {found: false, reason: 'text-not-found'};
          const bubble = match.closest('[data-testid="message_content"]') || match;
          const focusNeedles = focusTerms.map(normalize).filter(value => value.length >= 2);
          const descendants = [bubble, ...bubble.querySelectorAll('*')]
            .map(el => {
              const text = normalize(el.innerText || el.textContent);
              const score = focusNeedles.reduce((sum, needle) => sum + (text.includes(needle) ? 1 : 0), 0);
              return {el, text, score};
            })
            .filter(item => item.score > 0 && item.el.getClientRects().length > 0)
            .sort((a, b) => b.score - a.score || a.text.length - b.text.length);
          const focus = descendants[0]?.el || bubble;
          const reveal = () => {
            const targetRect = focus.getBoundingClientRect();
            const scrollRect = scroller.getBoundingClientRect();
            scroller.scrollTop += targetRect.top - scrollRect.top -
              (scroller.clientHeight - Math.min(targetRect.height, scroller.clientHeight)) / 2;
            scroller.dispatchEvent(new Event('scroll', {bubbles: true}));
          };
          reveal();
          // Doubao restores its previous reading position shortly after a chat
          // opens. Re-assert the target after those asynchronous layout passes.
          await sleep(350);
          reveal();
          await sleep(750);
          reveal();
          focus.style.outline = '3px solid #5B8CFF';
          focus.style.outlineOffset = '6px';
          focus.style.borderRadius = '10px';
          focus.style.backgroundColor = 'rgba(91,140,255,0.18)';
          focus.animate(
            [{boxShadow: '0 0 0 0 rgba(91,140,255,.65)'}, {boxShadow: '0 0 0 12px rgba(91,140,255,0)'}],
            {duration: 1100, iterations: 3}
          );
          return {found: true, focusedText: (focus.innerText || focus.textContent || '').slice(0, 160)};
        })()
        """

        // Chromium rejects URLSessionWebSocketTask's handshake in some Doubao
        // desktop builds. Use the already-bundled Node runtime (also used by
        // doubao-cli), whose WebSocket handshake is accepted by the CDP server.
        let bridge = """
        const [url, expression] = process.argv.slice(1);
        const socket = new WebSocket(url);
        const timer = setTimeout(() => { console.error('CDP timeout'); process.exit(2); }, 12000);
        socket.addEventListener('open', () => socket.send(JSON.stringify({
          id: 1,
          method: 'Runtime.evaluate',
          params: {expression, returnByValue: true, awaitPromise: true}
        })));
        socket.addEventListener('message', event => {
          const message = JSON.parse(event.data);
          if (message.id !== 1) return;
          clearTimeout(timer);
          console.log(JSON.stringify(message));
          socket.close();
        });
        socket.addEventListener('error', () => { clearTimeout(timer); process.exit(3); });
        """
        let bundledNode = isolatedRoot.appendingPathComponent("node/bin/node").path
        let command = FileManager.default.isExecutableFile(atPath: bundledNode)
            ? [bundledNode, "-e", bridge, websocketURL, expression]
            : ["/usr/bin/env", "node", "-e", bridge, websocketURL, expression]
        let response = await Task.detached(priority: .userInitiated) { run(command) }.value
        guard response.status == 0,
              let data = response.output.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let result = object["result"] as? [String: Any]
        let remote = result?["result"] as? [String: Any]
        let value = remote?["value"] as? [String: Any]
        return value?["found"] as? Bool == true
    }

    private func ensureCDP() throws {
        let status = runDoubao(["--app", "doubao", "cdp", "status", "--json"])
        if status.status == 0,
           let data = status.output.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["available"] as? Bool == true {
            return
        }

        let launch = runDoubao(["--app", "doubao", "cdp", "launch", "--yes", "--json"])
        guard launch.status == 0 else {
            throw AdapterError.commandFailed(launch.error.isEmpty ? launch.output : launch.error)
        }
    }

    private func runDoubao(_ arguments: [String]) -> (status: Int32, output: String, error: String) {
        let cli = FileManager.default.isExecutableFile(atPath: isolatedCLI.path)
            ? isolatedCLI.path
            : "/usr/bin/env"
        let command = cli == "/usr/bin/env" ? [cli, "doubao"] + arguments : [cli] + arguments
        var environment = ProcessInfo.processInfo.environment
        let nodePath = isolatedRoot.appendingPathComponent("node/bin").path
        let toolingPath = isolatedRoot.appendingPathComponent("tooling/bin").path
        environment["PATH"] = [nodePath, toolingPath, environment["PATH"] ?? ""].joined(separator: ":")
        if FileManager.default.fileExists(atPath: officialDataDirectory.appendingPathComponent("Local State").path) {
            environment["DOUBAO_DATA_DIR"] = officialDataDirectory.path
        } else if FileManager.default.fileExists(atPath: sandboxedDataDirectory.path) {
            environment["DOUBAO_DATA_DIR"] = sandboxedDataDirectory.path
        }
        return run(command, environment: environment)
    }
}

private struct CDPTarget: Decodable {
    let type: String
    let url: String
    let webSocketDebuggerUrl: String?
}

private func run(_ command: [String], environment: [String: String]? = nil) -> (status: Int32, output: String, error: String) {
    guard let executable = command.first else { return (-1, "", "empty command") }
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = Array(command.dropFirst())
    if let environment { process.environment = environment }
    process.standardOutput = stdout
    process.standardError = stderr
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return (-1, "", error.localizedDescription)
    }
    let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, output, error.trimmingCharacters(in: .whitespacesAndNewlines))
}
