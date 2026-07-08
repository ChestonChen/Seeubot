import Foundation

/// Scans local agent transcripts plus the live process list to produce a
/// `DashStats` snapshot. Each supported agent owns its transcript discovery,
/// process detection and token parsing through an adapter entry.
final class SessionCollector {

    /// A transcript written within this many seconds is treated as "working".
    static let workingWindow: TimeInterval = 45
    /// Cursor transcript writes happen near interaction boundaries, so a shorter
    /// window keeps the UI from lingering in "working" after a task finishes.
    static let cursorWorkingWindow: TimeInterval = 12
    /// If Cursor has started a turn but has not appended `turn_ended`, keep the
    /// session working even if no transcript bytes are written during a long tool run.
    static let cursorOpenTurnWindow: TimeInterval = 30 * 60
    /// A finished Cursor turn stays visible briefly as idle, then drops out of
    /// the live session list while its aggregate usage remains counted.
    static let cursorIdleRetentionWindow: TimeInterval = 10 * 60

    private let home = NSHomeDirectory()

    private struct FileInfo {
        var agentID: String
        var mtime: TimeInterval
        var size: Int
        var tokens: TokenBreakdown
        var todayTokens: TokenBreakdown
        var cwd: String?
    }

    private struct Match {
        var path: String
        var mtime: TimeInterval
        var tokens: TokenBreakdown
        var cwd: String?
    }

    private struct Proc {
        var pid: Int
        var agent: AgentDescriptor
    }

    private struct AgentAdapter {
        var descriptor: AgentDescriptor
        var enumerateFiles: (SessionCollector) -> [String]
        var parseFile: (SessionCollector, String, TimeInterval) -> (TokenBreakdown, TokenBreakdown, String?)
        var classifyProcess: (SessionCollector, String) -> Bool
        var resolveTranscript: (SessionCollector, String, String?, [String: FileInfo], inout Set<String>) -> Match?
        var extraSessions: (SessionCollector, TimeInterval, [String: FileInfo], Set<String>) -> [LiveSession]
    }

    // path -> parsed info (validated against size+mtime so stale entries are ignored)
    private var cache: [String: FileInfo] = [:]

    private var adapters: [AgentAdapter] {
        [claudeAdapter(), codexAdapter(), cursorAdapter()]
    }

    // MARK: - Public entry point

    func collect() -> DashStats {
        let now = Date().timeIntervalSince1970
        let startOfToday = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let activeAdapters = adapters

        var pathsByAgent: [String: [String]] = [:]
        var infoByPath: [String: FileInfo] = [:]

        for adapter in activeAdapters {
            let paths = adapter.enumerateFiles(self)
            pathsByAgent[adapter.descriptor.id] = paths
            for path in paths {
                infoByPath[path] = info(for: path, adapter: adapter, startOfToday: startOfToday)
            }
        }

        // Bound the long-lived cache to files still on disk (evict deleted/rotated).
        cache = cache.filter { infoByPath.keys.contains($0.key) }

        let procs = liveProcesses(adapters: activeAdapters)
        let probe = probeProcesses(pids: procs.map { $0.pid })

        var sessions: [LiveSession] = []
        var claimed = Set<String>()
        for proc in procs {
            guard let adapter = activeAdapters.first(where: { $0.descriptor.id == proc.agent.id }) else { continue }
            let probedCwd = probe[proc.pid]?.cwd ?? ""
            let transcript = adapter.descriptor.id == AgentDescriptor.cursor.id
                ? nil
                : adapter.resolveTranscript(self, probedCwd, probe[proc.pid]?.transcript, infoByPath, &claimed)
            if adapter.descriptor.id == AgentDescriptor.cursor.id { continue }
            let sessionCwd = transcript?.cwd ?? probedCwd
            let idleSeconds = transcript.map { max(0, now - $0.mtime) } ?? .infinity
            let state: SessionState = idleSeconds < Self.workingWindow ? .working : .idle
            sessions.append(LiveSession(
                id: "\(proc.agent.id)-\(proc.pid)",
                pid: proc.pid,
                tool: proc.agent,
                project: projectName(from: sessionCwd),
                cwd: sessionCwd,
                state: state,
                tokens: transcript?.tokens.total ?? 0,
                idleSeconds: idleSeconds.isFinite ? idleSeconds : -1
            ))
        }
        for adapter in activeAdapters {
            sessions.append(contentsOf: adapter.extraSessions(self, now, infoByPath, claimed))
        }

        sessions.sort {
            if ($0.state == .working) != ($1.state == .working) { return $0.state == .working }
            return $0.idleSeconds < $1.idleSeconds
        }

        var perTool: [ToolStat] = []
        for adapter in activeAdapters {
            let paths = pathsByAgent[adapter.descriptor.id] ?? []
            var totals = totals(paths, infoByPath: infoByPath, startOfToday: startOfToday)
            if adapter.descriptor.id == AgentDescriptor.cursor.id, let usage = cursorUsageCacheTotals() {
                totals = (all: usage.all, today: usage.today, count: totals.count)
            }
            let toolSessions = sessions.filter { $0.tool.id == adapter.descriptor.id }
            // Show agents that are currently live or have historical transcripts.
            // Installed-but-never-used tools stay hidden because they have neither.
            if toolSessions.isEmpty && totals.count == 0 { continue }
            perTool.append(ToolStat(
                tool: adapter.descriptor,
                live: toolSessions.count,
                working: toolSessions.filter { $0.state == .working }.count,
                idle: toolSessions.filter { $0.state == .idle }.count,
                tokensAllTime: totals.all,
                tokensToday: totals.today,
                sessionsAllTime: totals.count
            ))
        }

        let tokensAll = perTool.reduce(TokenBreakdown()) { $0 + $1.tokensAllTime }
        let tokensToday = perTool.reduce(TokenBreakdown()) { $0 + $1.tokensToday }

        return DashStats(
            sessions: sessions,
            perTool: perTool,
            totalLive: sessions.count,
            totalWorking: sessions.filter { $0.state == .working }.count,
            totalIdle: sessions.filter { $0.state == .idle }.count,
            tokensAllTime: tokensAll,
            tokensToday: tokensToday,
            sessionsAllTime: perTool.reduce(0) { $0 + $1.sessionsAllTime },
            updatedAtEpoch: now
        )
    }

    // MARK: - Adapters

    private func claudeAdapter() -> AgentAdapter {
        AgentAdapter(
            descriptor: .claude,
            enumerateFiles: { collector in collector.enumerateJSONL(dir: collector.home + "/.claude/projects") },
            parseFile: { collector, path, startOfToday in
                let parsed = collector.parseClaude(path, startOfToday: startOfToday)
                return (parsed.0, parsed.1, nil)
            },
            classifyProcess: { collector, command in collector.executableBase(command) == "claude" },
            resolveTranscript: { collector, cwd, openPath, infoByPath, claimed in
                collector.resolveClaude(cwd: cwd, openPath: openPath, infoByPath: infoByPath, claimed: &claimed)
            },
            extraSessions: { _, _, _, _ in [] }
        )
    }

    private func codexAdapter() -> AgentAdapter {
        AgentAdapter(
            descriptor: .codex,
            enumerateFiles: { collector in collector.enumerateJSONL(dir: collector.home + "/.codex/sessions") },
            parseFile: { collector, path, startOfToday in collector.parseCodex(path, startOfToday: startOfToday) },
            classifyProcess: { collector, command in collector.isInteractiveCodex(command: command) },
            resolveTranscript: { collector, cwd, openPath, infoByPath, claimed in
                collector.resolveCodex(cwd: cwd, openPath: openPath, infoByPath: infoByPath, claimed: &claimed)
            },
            extraSessions: { _, _, _, _ in [] }
        )
    }

    private func cursorAdapter() -> AgentAdapter {
        AgentAdapter(
            descriptor: .cursor,
            enumerateFiles: { collector in
                collector.enumerateJSONL(dir: collector.home + "/.cursor/projects")
                    .filter { $0.contains("/agent-transcripts/") && !$0.contains("/subagents/") }
            },
            parseFile: { collector, path, _ in
                // Cursor agent transcripts do not expose stable per-session usage
                // buckets locally. Aggregate usage is merged at the ToolStat level.
                (TokenBreakdown(), TokenBreakdown(), collector.cursorCwd(from: path))
            },
            classifyProcess: { collector, command in collector.isCursor(command: command) },
            resolveTranscript: { collector, cwd, openPath, infoByPath, claimed in
                collector.resolveCursor(cwd: cwd, openPath: openPath, infoByPath: infoByPath, claimed: &claimed)
            },
            extraSessions: { collector, now, infoByPath, claimed in
                collector.cursorTranscriptSessions(now: now, infoByPath: infoByPath, claimed: claimed)
            }
        )
    }

    // MARK: - File enumeration and cache

    private func enumerateJSONL(dir: String) -> [String] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: URL(fileURLWithPath: dir),
                                     includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            if url.path.contains("/subagents/") { continue }
            out.append(url.path)
        }
        return out
    }

    private func statOf(_ path: String) -> (mtime: TimeInterval, size: Int)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? Int) ?? 0
        return (mtime, size)
    }

    private func info(for path: String, adapter: AgentAdapter, startOfToday: TimeInterval) -> FileInfo {
        guard let st = statOf(path) else {
            return FileInfo(agentID: adapter.descriptor.id, mtime: 0, size: 0,
                            tokens: TokenBreakdown(), todayTokens: TokenBreakdown(), cwd: nil)
        }
        if let cached = cache[path],
           cached.agentID == adapter.descriptor.id,
           cached.mtime == st.mtime,
           cached.size == st.size {
            return cached
        }
        let parsed = adapter.parseFile(self, path, startOfToday)
        let info = FileInfo(agentID: adapter.descriptor.id, mtime: st.mtime, size: st.size,
                            tokens: parsed.0, todayTokens: parsed.1, cwd: parsed.2)
        cache[path] = info
        return info
    }

    private func totals(_ paths: [String], infoByPath: [String: FileInfo],
                        startOfToday: TimeInterval) -> (all: TokenBreakdown, today: TokenBreakdown, count: Int) {
        var all = TokenBreakdown(), today = TokenBreakdown()
        for path in paths {
            guard let info = infoByPath[path] else { continue }
            all += info.tokens
            if info.mtime >= startOfToday { today += info.todayTokens }
        }
        return (all, today, paths.count)
    }

    // MARK: - Token parsers

    private func parseClaude(_ path: String, startOfToday: TimeInterval) -> (TokenBreakdown, TokenBreakdown) {
        guard let data = FileManager.default.contents(atPath: path) else { return (TokenBreakdown(), TokenBreakdown()) }
        let text = String(decoding: data, as: UTF8.self)
        var all = TokenBreakdown(), today = TokenBreakdown()
        var seen = Set<String>()
        text.enumerateLines { line, _ in
            guard line.contains("\"usage\"") else { return }
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  (obj["type"] as? String) == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any] else { return }
            let messageID = msg["id"] as? String ?? (obj["uuid"] as? String ?? "")
            if !messageID.isEmpty { guard seen.insert(messageID).inserted else { return } }
            var breakdown = TokenBreakdown()
            breakdown.inputFresh = usage["input_tokens"] as? Int ?? 0
            breakdown.cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
            breakdown.cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            breakdown.output = usage["output_tokens"] as? Int ?? 0
            all += breakdown
            if let ts = obj["timestamp"] as? String, let epoch = self.epoch(ts), epoch >= startOfToday {
                today += breakdown
            }
        }
        return (all, today)
    }

    private func parseCodex(_ path: String, startOfToday: TimeInterval) -> (TokenBreakdown, TokenBreakdown, String?) {
        guard let data = FileManager.default.contents(atPath: path) else { return (TokenBreakdown(), TokenBreakdown(), nil) }
        let text = String(decoding: data, as: UTF8.self)
        var cwd: String? = nil
        var last: TokenBreakdown? = nil
        var beforeToday: TokenBreakdown? = nil
        var isFirst = true
        text.enumerateLines { line, _ in
            if isFirst {
                isFirst = false
                if let lineData = line.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   (obj["type"] as? String) == "session_meta",
                   let payload = obj["payload"] as? [String: Any] {
                    cwd = payload["cwd"] as? String
                }
            }
            guard line.contains("total_token_usage") else { return }
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let totalUsage = info["total_token_usage"] as? [String: Any] else { return }
            var breakdown = TokenBreakdown()
            let input = totalUsage["input_tokens"] as? Int ?? 0
            let cached = totalUsage["cached_input_tokens"] as? Int ?? 0
            breakdown.output = totalUsage["output_tokens"] as? Int ?? 0
            breakdown.inputFresh = max(0, input - cached)
            breakdown.cacheRead = cached
            last = breakdown
            if let ts = obj["timestamp"] as? String, let epoch = self.epoch(ts), epoch < startOfToday {
                beforeToday = breakdown
            }
        }
        let all = last ?? TokenBreakdown()
        let today = TokenBreakdown.clampedMinus(all, beforeToday ?? TokenBreakdown())
        return (all, today, cwd)
    }

    private func cursorUsageCacheTotals() -> (all: TokenBreakdown, today: TokenBreakdown)? {
        let path = home + "/Library/Application Support/Cursor/User/globalStorage/panshenbing.cursor-usage-dashboard/usage-refresh-cache.json"
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any] else { return nil }

        guard let today = cursorTokenBreakdown(from: payload["todayStats"] as? [String: Any]) else {
            return nil
        }
        return (today, today)
    }

    private func cursorTokenBreakdown(from stats: [String: Any]?) -> TokenBreakdown? {
        guard let stats else { return nil }
        return TokenBreakdown(
            output: intValue(stats["outputTokens"]),
            inputFresh: intValue(stats["inputTokens"]),
            cacheCreate: intValue(stats["cacheWriteTokens"]),
            cacheRead: intValue(stats["cacheReadTokens"])
        )
    }

    private func intValue(_ value: Any?) -> Int {
        switch value {
        case let n as Int:
            return n
        case let n as NSNumber:
            return n.intValue
        case let d as Double:
            return Int(d)
        default:
            return 0
        }
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func epoch(_ s: String) -> TimeInterval? {
        if let date = Self.isoFrac.date(from: s) { return date.timeIntervalSince1970 }
        if let date = Self.isoPlain.date(from: s) { return date.timeIntervalSince1970 }
        return nil
    }

    // MARK: - Live process detection

    private func liveProcesses(adapters: [AgentAdapter]) -> [Proc] {
        let out = runCmd("/bin/ps", ["-axo", "pid=,command="])
        var result: [Proc] = []
        for raw in out.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " "), let pid = Int(line[..<space]) else { continue }
            let command = String(line[line.index(after: space)...])
            guard let adapter = adapters.first(where: { $0.classifyProcess(self, command) }) else { continue }
            result.append(Proc(pid: pid, agent: adapter.descriptor))
        }
        return result
    }

    private static let codexNonInteractive: Set<String> =
        ["exec", "app-server", "mcp", "login", "logout", "proto", "completion",
         "ls", "help", "--help", "-h", "--version", "-V"]

    private func executableBase(_ command: String) -> String {
        let firstToken = command.split(separator: " ").first.map(String.init) ?? ""
        return (firstToken as NSString).lastPathComponent
    }

    private func isInteractiveCodex(command: String) -> Bool {
        guard executableBase(command) == "codex" else { return false }
        let firstToken = command.split(separator: " ").first.map(String.init) ?? ""
        let rest = command.dropFirst(firstToken.count).trimmingCharacters(in: .whitespaces)
        let firstArg = rest.split(separator: " ").first.map(String.init) ?? ""
        return !Self.codexNonInteractive.contains(firstArg)
    }

    private func isCursor(command: String) -> Bool {
        command.contains(".app/Contents/MacOS/Cursor") && !command.contains("Cursor Helper")
    }

    private func probeProcesses(pids: [Int]) -> [Int: (cwd: String?, transcript: String?)] {
        guard !pids.isEmpty else { return [:] }
        let csv = pids.map(String.init).joined(separator: ",")
        let out = runCmd("/usr/sbin/lsof", ["-w", "-p", csv, "-Fpfn"])
        var map: [Int: (cwd: String?, transcript: String?)] = [:]
        var pid = -1, fd = ""
        for raw in out.split(separator: "\n") {
            let s = String(raw)
            guard let tag = s.first else { continue }
            let val = String(s.dropFirst())
            switch tag {
            case "p":
                pid = Int(val) ?? -1
                fd = ""
            case "f":
                fd = val
            case "n":
                guard pid != -1 else { continue }
                if fd == "cwd" {
                    map[pid, default: (nil, nil)].cwd = val
                } else if val.hasSuffix(".jsonl"),
                          val.contains("/.codex/sessions/")
                            || val.contains("/.claude/projects/")
                            || val.contains("/.cursor/projects/") {
                    map[pid, default: (nil, nil)].transcript = val
                }
            default:
                break
            }
        }
        return map
    }

    // MARK: - Transcript resolution

    private func resolveClaude(cwd: String, openPath: String?, infoByPath: [String: FileInfo],
                               claimed: inout Set<String>) -> Match? {
        if let exact = exactMatch(openPath, infoByPath: infoByPath, claimed: &claimed) { return exact }
        guard !cwd.isEmpty else { return nil }
        let needle = "/projects/" + claudeEncode(cwd) + "/"
        let match = newest(infoByPath, claimed: claimed) { path, info in
            guard info.agentID == AgentDescriptor.claude.id, let range = path.range(of: needle) else { return false }
            return !path[range.upperBound...].contains("/")
        }
        if let match { claimed.insert(match.path) }
        return match
    }

    private func resolveCodex(cwd: String, openPath: String?, infoByPath: [String: FileInfo],
                              claimed: inout Set<String>) -> Match? {
        if let exact = exactMatch(openPath, infoByPath: infoByPath, claimed: &claimed) { return exact }
        guard !cwd.isEmpty else { return nil }
        let match = newest(infoByPath, claimed: claimed) { _, info in
            info.agentID == AgentDescriptor.codex.id && info.cwd == cwd
        }
        if let match { claimed.insert(match.path) }
        return match
    }

    private func resolveCursor(cwd: String, openPath: String?, infoByPath: [String: FileInfo],
                               claimed: inout Set<String>) -> Match? {
        if let exact = exactMatch(openPath, infoByPath: infoByPath, claimed: &claimed) { return exact }
        let match = newest(infoByPath, claimed: claimed) { _, info in
            guard info.agentID == AgentDescriptor.cursor.id else { return false }
            return cwd.isEmpty || info.cwd == cwd || info.mtime >= Date().timeIntervalSince1970 - 6 * 3600
        }
        if let match { claimed.insert(match.path) }
        return match
    }

    private func cursorTranscriptSessions(now: TimeInterval, infoByPath: [String: FileInfo],
                                          claimed: Set<String>) -> [LiveSession] {
        let cursorInfos = infoByPath
            .filter { path, info in
                guard info.agentID == AgentDescriptor.cursor.id, !claimed.contains(path) else { return false }
                let idleSeconds = max(0, now - info.mtime)
                switch cursorTranscriptOpenTurn(path) {
                case .some(true):
                    return idleSeconds < Self.cursorOpenTurnWindow
                case .some(false):
                    return idleSeconds < Self.cursorIdleRetentionWindow
                case .none:
                    return idleSeconds < Self.cursorWorkingWindow
                }
            }
            .sorted { $0.value.mtime > $1.value.mtime }

        var seenCwds = Set<String>()
        var sessions: [LiveSession] = []
        for (path, info) in cursorInfos {
            let cwd = info.cwd ?? cursorCwd(from: path) ?? ""
            let dedupeKey = cwd.isEmpty ? path : cwd
            guard seenCwds.insert(dedupeKey).inserted else { continue }
            let idleSeconds = max(0, now - info.mtime)
            let state: SessionState
            switch cursorTranscriptOpenTurn(path) {
            case .some(true):
                state = idleSeconds < Self.cursorOpenTurnWindow ? .working : .idle
            case .some(false):
                state = .idle
            case .none:
                state = idleSeconds < Self.cursorWorkingWindow ? .working : .idle
            }
            sessions.append(LiveSession(
                id: "cursor-file-\(stableHash(path))",
                pid: 0,
                tool: .cursor,
                project: projectName(from: cwd),
                cwd: cwd,
                state: state,
                tokens: info.tokens.total,
                idleSeconds: idleSeconds
            ))
            if sessions.count >= 8 { break }
        }
        return sessions
    }

    private func cursorTranscriptOpenTurn(_ path: String) -> Bool? {
        guard let line = lastLine(path), !line.isEmpty else { return nil }
        return !line.contains("\"type\":\"turn_ended\"")
    }

    private func lastLine(_ path: String, maxBytes: UInt64 = 64 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > maxBytes ? size - maxBytes : 0
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(whereSeparator: \.isNewline).last.map(String.init)
    }

    private func exactMatch(_ openPath: String?, infoByPath: [String: FileInfo], claimed: inout Set<String>) -> Match? {
        guard let openPath, !claimed.contains(openPath), let info = infoByPath[openPath] else { return nil }
        claimed.insert(openPath)
        return Match(path: openPath, mtime: info.mtime, tokens: info.tokens, cwd: info.cwd)
    }

    private func newest(_ infoByPath: [String: FileInfo], claimed: Set<String>,
                        where predicate: (String, FileInfo) -> Bool) -> Match? {
        var best: Match? = nil
        for (path, info) in infoByPath where !claimed.contains(path) && predicate(path, info) {
            if best == nil || info.mtime > best!.mtime {
                best = Match(path: path, mtime: info.mtime, tokens: info.tokens, cwd: info.cwd)
            }
        }
        return best
    }

    private func claudeEncode(_ cwd: String) -> String {
        String(cwd.unicodeScalars.map { s in
            (s >= "a" && s <= "z") || (s >= "A" && s <= "Z") || (s >= "0" && s <= "9")
                ? Character(s) : "-"
        })
    }

    private func cursorCwd(from path: String) -> String? {
        guard let range = path.range(of: "/.cursor/projects/") else { return nil }
        let rest = path[range.upperBound...]
        guard let projectFolder = rest.split(separator: "/").first else { return nil }
        if projectFolder == "empty-window" { return "empty-window" }
        let encoded = String(projectFolder)
        let knownPrefixes = ["Users-bytedance-Projects-", "Users-bytedance-TikTok-", "Users-bytedance-"]
        for prefix in knownPrefixes where encoded.hasPrefix(prefix) {
            let suffix = String(encoded.dropFirst(prefix.count))
            switch prefix {
            case "Users-bytedance-":
                return "/Users/bytedance/" + suffix
            case "Users-bytedance-Projects-":
                return "/Users/bytedance/Projects/" + suffix
            case "Users-bytedance-TikTok-":
                return "/Users/bytedance/TikTok/" + suffix
            default:
                break
            }
        }
        return "/" + encoded.split(separator: "-").joined(separator: "/")
    }

    private func projectName(from cwd: String) -> String {
        if cwd.isEmpty { return "-" }
        let base = (cwd as NSString).lastPathComponent
        return base.isEmpty ? cwd : base
    }

    private func stableHash(_ s: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

    // MARK: - Subprocess helper

    private func runCmd(_ launch: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
