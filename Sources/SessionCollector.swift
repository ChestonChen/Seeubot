import Foundation

// 系统 API 速览：
// - FileManager：Foundation 文件系统 API，用来枚举 transcript、读取文件属性和内容。
// - Date / Calendar：系统时间 API，用来算“今天开始时间”和文件距今多久。
// - JSONSerialization：把 JSONL 每一行解析成字典，读取 usage/token 字段。
// - ISO8601DateFormatter：解析 transcript 里的 ISO 时间字符串。
// - Process / Pipe：启动 ps、lsof 等系统命令并读取输出。
// - FileHandle：读文件尾部、写 debug 输出、关闭文件句柄。
// - NSHomeDirectory：获取当前用户 home 目录，拼出 ~/.claude、~/.codex、~/.cursor 路径。
/// 采集器核心：扫描本地 agent transcript、token cache 和实时进程列表，
/// 最终产出一个 `DashStats` 快照给 UI。
///
/// 你读这个文件时记住一条主线：
/// 1. 每个工具先通过 `AgentAdapter` 定义“去哪找文件 / 怎么解析 / 怎么识别进程”
/// 2. `collect()` 调所有 adapter，得到 sessions + token totals
/// 3. UI 只看 `DashStats`，不关心底层是 Claude、Codex 还是 Cursor。
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
        // 一个 agent 的完整适配说明。新增工具时主要就是新增一个 adapter。
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

    /// 每秒被 `StatsStore` 调用一次，是采集链路总入口。
    /// 这里会把“文件统计 + 进程状态 + Cursor 额外 session”合并成 Dashboard 数据。
    func collect() -> DashStats {
        // 系统 API（行级）：Date() 获取当前时间。
        let now = Date().timeIntervalSince1970
        // 系统 API（行级）：Calendar.startOfDay 计算当天零点时间。
        let startOfToday = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let activeAdapters = adapters

        var pathsByAgent: [String: [String]] = [:]
        var infoByPath: [String: FileInfo] = [:]

        // 第一步：让每个 adapter 枚举自己的 transcript 文件，并解析/缓存 token 信息。
        for adapter in activeAdapters {
            let paths = adapter.enumerateFiles(self)
            pathsByAgent[adapter.descriptor.id] = paths
            for path in paths {
                infoByPath[path] = info(for: path, adapter: adapter, startOfToday: startOfToday)
            }
        }

        // Bound the long-lived cache to files still on disk (evict deleted/rotated).
        cache = cache.filter { infoByPath.keys.contains($0.key) }

        // 第二步：扫描当前进程。Claude/Codex 的 live session 主要从进程反推。
        let procs = liveProcesses(adapters: activeAdapters)
        let probe = probeProcesses(pids: procs.map { $0.pid })

        var sessions: [LiveSession] = []
        var claimed = Set<String>()
        // 第三步：把进程和打开的 transcript 对上，生成 Claude/Codex live session。
        for proc in procs {
            guard let adapter = activeAdapters.first(where: { $0.descriptor.id == proc.agent.id }) else { continue }
            let probedCwd = probe[proc.pid]?.cwd ?? ""
            // Cursor 主进程常驻，不能代表一个 agent session，所以这里跳过 Cursor；
            // Cursor 的 session 会在后面的 extraSessions 里由 transcript 生成。
            let transcript = adapter.descriptor.id == AgentDescriptor.cursor.id
                ? nil
                : adapter.resolveTranscript(self, probedCwd, probe[proc.pid]?.transcript, infoByPath, &claimed)
            if adapter.descriptor.id == AgentDescriptor.cursor.id { continue }
            let sessionCwd = transcript?.cwd ?? probedCwd
            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
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
        // 第四步：给 Cursor 这类“不能直接靠进程判断”的工具补充逻辑 session。
        for adapter in activeAdapters {
            sessions.append(contentsOf: adapter.extraSessions(self, now, infoByPath, claimed))
        }

        sessions.sort {
            if ($0.state == .working) != ($1.state == .working) { return $0.state == .working }
            return $0.idleSeconds < $1.idleSeconds
        }

        // 第五步：按工具聚合 token、working/idle 数量，供 dashboard 的工具列表使用。
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
        // Claude：保留原来的 ~/.claude/projects transcript 解析和进程识别逻辑。
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
        // Codex：读取 ~/.codex/sessions，并过滤掉非交互型 codex 子命令。
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
        // Cursor：不把主 App 进程当 session，而是读取 ~/.cursor/projects 下的 agent-transcripts。
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
        // 递归枚举 jsonl transcript。subagents 暂时跳过，避免把子任务重复算成主 session。
        // 系统 API（行级）：FileManager.default 是系统文件管理器，用来枚举和读取本地文件。
        let fm = FileManager.default
        // 系统 API（行级）：FileManager.enumerator 递归遍历目录。
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
        // 系统 API（行级）：FileManager.default 是系统文件管理器，用来枚举和读取本地文件。
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? Int) ?? 0
        return (mtime, size)
    }

    private func info(for path: String, adapter: AgentAdapter, startOfToday: TimeInterval) -> FileInfo {
        // 解析结果按 path + mtime + size 缓存；文件没变就不重复解析，降低 1 秒刷新成本。
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
        // Claude 的 usage 字段是逐条 assistant message 写入的，因此按 message 去重后累加。
        // 系统 API（行级）：FileManager.default 是系统文件管理器，用来枚举和读取本地文件。
        guard let data = FileManager.default.contents(atPath: path) else { return (TokenBreakdown(), TokenBreakdown()) }
        let text = String(decoding: data, as: UTF8.self)
        var all = TokenBreakdown(), today = TokenBreakdown()
        var seen = Set<String>()
        text.enumerateLines { line, _ in
            guard line.contains("\"usage\"") else { return }
            guard let lineData = line.data(using: .utf8),
                  // 系统 API（行级）：JSONSerialization.jsonObject 把 JSON Data 解析成字典/数组。
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
        // Codex 记录的是累计 total_token_usage，所以 today 需要用“当前累计 - 今日前累计”推出来。
        // 系统 API（行级）：FileManager.default 是系统文件管理器，用来枚举和读取本地文件。
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
                   // 系统 API（行级）：JSONSerialization.jsonObject 把 JSON Data 解析成字典/数组。
                   let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   (obj["type"] as? String) == "session_meta",
                   let payload = obj["payload"] as? [String: Any] {
                    cwd = payload["cwd"] as? String
                }
            }
            guard line.contains("total_token_usage") else { return }
            guard let lineData = line.data(using: .utf8),
                  // 系统 API（行级）：JSONSerialization.jsonObject 把 JSON Data 解析成字典/数组。
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let totalUsage = info["total_token_usage"] as? [String: Any] else { return }
            var breakdown = TokenBreakdown()
            let input = totalUsage["input_tokens"] as? Int ?? 0
            let cached = totalUsage["cached_input_tokens"] as? Int ?? 0
            breakdown.output = totalUsage["output_tokens"] as? Int ?? 0
            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
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
        // Cursor transcript 没有稳定 per-session token 字段，所以 token 只从本地 usage cache 读 todayStats。
        let path = home + "/Library/Application Support/Cursor/User/globalStorage/panshenbing.cursor-usage-dashboard/usage-refresh-cache.json"
        // 系统 API（行级）：FileManager.default 是系统文件管理器，用来枚举和读取本地文件。
        guard let data = FileManager.default.contents(atPath: path),
              // 系统 API（行级）：JSONSerialization.jsonObject 把 JSON Data 解析成字典/数组。
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
        // 系统 API（行级）：ISO8601DateFormatter 解析 ISO8601 时间字符串。
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        // 系统 API（行级）：ISO8601DateFormatter 解析 ISO8601 时间字符串。
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
        // 用 ps 拿全量进程，再交给各 adapter 判断是不是自己关心的 agent。
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
        // 只统计真正的交互式 Codex，会话外的 login/help/mcp 等命令不算 live session。
        guard executableBase(command) == "codex" else { return false }
        let firstToken = command.split(separator: " ").first.map(String.init) ?? ""
        let rest = command.dropFirst(firstToken.count).trimmingCharacters(in: .whitespaces)
        let firstArg = rest.split(separator: " ").first.map(String.init) ?? ""
        return !Self.codexNonInteractive.contains(firstArg)
    }

    private func isCursor(command: String) -> Bool {
        // 只识别 Cursor 主程序，过滤 Cursor Helper，避免把渲染/插件进程误算成 session。
        command.contains(".app/Contents/MacOS/Cursor") && !command.contains("Cursor Helper")
    }

    private func probeProcesses(pids: [Int]) -> [Int: (cwd: String?, transcript: String?)] {
        // 用 lsof 反查进程 cwd 和当前打开的 jsonl 文件，用来把“进程”对到“transcript”。
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
        // Claude 的目录名是 cwd 编码后的结果，所以先精确匹配打开文件，再按 cwd 编码找最新 transcript。
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
        // Codex transcript 里有 cwd，按 cwd 找对应 session。
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
            // 系统 API（行级）：Date() 获取当前时间。
            return cwd.isEmpty || info.cwd == cwd || info.mtime >= Date().timeIntervalSince1970 - 6 * 3600
        }
        if let match { claimed.insert(match.path) }
        return match
    }

    private func cursorTranscriptSessions(now: TimeInterval, infoByPath: [String: FileInfo],
                                          claimed: Set<String>) -> [LiveSession] {
        // Cursor 的 live session 由最近活跃的 agent transcript 生成：
        // 未 turn_ended -> working；已结束 -> 保留一小段 idle；同 workspace 去重。
        let cursorInfos = infoByPath
            .filter { path, info in
                guard info.agentID == AgentDescriptor.cursor.id, !claimed.contains(path) else { return false }
                // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
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
            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
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
        // 只读最后一行即可判断 Cursor 当前 turn 是否结束；读全文件会浪费。
        guard let line = lastLine(path), !line.isEmpty else { return nil }
        return !line.contains("\"type\":\"turn_ended\"")
    }

    private func lastLine(_ path: String, maxBytes: UInt64 = 64 * 1024) -> String? {
        // 系统 API（行级）：FileHandle(forReadingAtPath:) 打开文件用于读取。
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
        // Cursor 会把项目路径编码进 ~/.cursor/projects/<encoded>，这里尽量还原成人能看懂的 cwd。
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
        // 系统 API（行级）：Process 用来启动系统命令。
        let process = Process()
        // 系统 API（行级）：URL 构造系统 URL 对象。
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = args
        // 系统 API（行级）：Pipe 接收子进程标准输出。
        let pipe = Pipe()
        process.standardOutput = pipe
        // 系统 API（行级）：FileHandle 读写文件句柄或标准输出/错误。
        process.standardError = FileHandle.nullDevice
        // 系统 API（行级）：app.run() 进入 macOS 主事件循环，窗口和菜单开始响应事件。
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
