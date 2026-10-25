//负责采集数据

import Foundation

//先写一个假的采集器，先返回空快照，并跑通
final class SessionCollector {
    static let workingWindow: TimeInterval = 45 //定义45s算working
    private let home = NSHomeDirectory()//获取用户目录，用于之后路径拼接
    //一个会话文件的「解析结果 + 指纹」
    //属于哪个工具、修改时间、字节数、累计 token、今日 token、工作目录。后三个是结果，前三个用来做缓存判重
    // 1session-1fileinfo，不是1agent-1fileinfo
    private struct FileInfo {
        var agentID: String //属于哪一个agent
        var mtime: TimeInterval //修改时间
        var size: Int //字节数
        var tokens: TokenBreakdown //累计token
        var todayTokens: TokenBreakdown //今日token
        var cwd: String? //工作目录
    }
    //「进程配上文件」的结果：文件路径、修改时间、token、目录
    private struct Match {
        var path: String //文件路径，会话文件在磁盘上的位置
        var mtime: TimeInterval
        var tokens: TokenBreakdown
        var cwd: String? //目录，transcript 里记的工作目录，这个会话运行时所在的目录
    }
    private struct Proc {
        var pid: Int //进程id
        var agent: AgentDescriptor //进程对应的agent信息
    }

    //把「支持一个工具」拆成 4 个函数——去哪找文件、怎么解析、怎么认进程、怎么跟文件配对。加新工具 = 填这 4 个闭包
    //策略模式
    private struct AgentAdapter {
        var descriptor: AgentDescriptor //agent描述
        var enumerateFiles: (SessionCollector) -> [String] //寻找会话文件路径
        //如何读文件
        var parseFile: (SessionCollector, String, TimeInterval) -> (TokenBreakdown, TokenBreakdown, String?)
        //匹配进程
        var classifyProcess: (SessionCollector, String) -> Bool
        //如何把进程和文件配对
        var resolveTranscript: (SessionCollector, String, String?, [String: FileInfo], inout Set<String>) -> Match?
    }
    private var cache: [String: FileInfo] = [:] //字典 文件路径-解析结果 ，缓存
    private var adapters: [AgentAdapter] { //计算属性
        [claudeAdapter(), codexAdapter()]
    }
    //先枚举+解析（上一步）→ 扫进程（闭环 6）→ 配对 → 汇总
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
        cache = cache.filter { infoByPath.keys.contains($0.key) }
        //把闭环 5 里临时改成空值的那两行，恢复成真实调用。改完这一处，界面上的「实时会话」就活了
        let procs = liveProcesses(adapters: activeAdapters)
        let probe = probeProcesses(pids: procs.map { $0.pid })
        var sessions: [LiveSession] = []
        var claimed = Set<String>()
        for proc in procs {
            guard let adapter = activeAdapters.first(where: { $0.descriptor.id == proc.agent.id }) else { continue }
            let probedCwd = probe[proc.pid]?.cwd ?? ""

            // 一个进程可能同时打开多个 transcript（Codex 桌面版就是一个 app-server 宿主多个对话），
            // 所以先把"它打开着的文件"逐个认领；一个都没配上时，才按 cwd 兜底找一次。
            var matches: [Match] = []
            for path in probe[proc.pid]?.transcripts ?? [] {
                guard let info = infoByPath[path], !claimed.contains(path) else { continue }
                claimed.insert(path)
                matches.append(Match(path: path, mtime: info.mtime, tokens: info.tokens, cwd: info.cwd))
            }
            if matches.isEmpty,
               let fallback = adapter.resolveTranscript(self, probedCwd, nil, infoByPath, &claimed) {
                matches.append(fallback)
            }

            if matches.isEmpty {
                // 进程在跑但还没有 transcript：保留旧行为，显示一条 idle -1 的会话。
                sessions.append(LiveSession(
                    id: "\(proc.agent.id)-\(proc.pid)", pid: proc.pid, tool: proc.agent,
                    project: projectName(from: probedCwd), cwd: probedCwd,
                    state: .idle, tokens: 0, idleSeconds: -1))
                continue
            }

            for (idx, m) in matches.enumerated() {
                let sessionCwd = m.cwd ?? probedCwd
                let idleSeconds = max(0, now - m.mtime)
                let state: SessionState = idleSeconds < Self.workingWindow ? .working : .idle
                sessions.append(LiveSession(
                    id: "\(proc.agent.id)-\(proc.pid)-\(idx)",
                    pid: proc.pid,
                    tool: proc.agent,
                    project: projectName(from: sessionCwd),
                    cwd: sessionCwd,
                    state: state,
                    tokens: m.tokens.total,
                    idleSeconds: idleSeconds
                ))
            }
        }
        sessions.sort {
            if ($0.state == .working) != ($1.state == .working) { return $0.state == .working }
            return $0.idleSeconds < $1.idleSeconds
        }
        var perTool: [ToolStat] = []
        for adapter in activeAdapters {
            let paths = pathsByAgent[adapter.descriptor.id] ?? []
            let totals = totals(paths, infoByPath: infoByPath, startOfToday: startOfToday)
            let toolSessions = sessions.filter { $0.tool.id == adapter.descriptor.id }
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
    private func projectName(from cwd: String) -> String {
        if cwd.isEmpty { return "-" }
        let base = (cwd as NSString).lastPathComponent
        return base.isEmpty ? cwd : base
    }
    private func enumerateJSONL(dir: String) -> [String] {//递归找出某个目录下所有 `.jsonl`
        let fm = FileManager.default
        guard let en = fm.enumerator(at: URL(fileURLWithPath: dir),//enumerator` 是系统给的目录遍历器
                                     includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            if url.path.contains("/subagents/") { continue } //跳过 `subagents` 目录：那是「主会话派生出的子任务」，算进去会让 token 重复
            out.append(url.path)
        }
        return out
    }
    //取文件的「修改时间 + 字节数
    private func statOf(_ path: String) -> (mtime: TimeInterval, size: Int)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? Int) ?? 0
        return (mtime, size)
    }
    //带缓存的解析入口：如果「路径 + 工具 + mtime + size」四个都没变，就直接返回上次结果，**完全跳过读文件
    private func info(for path: String, adapter: AgentAdapter, startOfToday: TimeInterval) -> FileInfo {
        guard let st = statOf(path) else {
            return FileInfo(agentID: adapter.descriptor.id, mtime: 0, size: 0,
                            tokens: TokenBreakdown(), todayTokens: TokenBreakdown(), cwd: nil)
        }
        //如果全匹配直接返回缓存
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
    //把一组文件的 token 加起来。注意「今日量」只累加「今天被修改过」的文件
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
    //Claude 的解析。难点：一条 assistant 回复在文件里是**很多行**
    // 每行都带一份 usage，所以要按 `message.id` 去重，否则 token 会被放大几十倍

//cluade文件结构
//     {"type":"user","message":{...},"timestamp":"..."}                                  ← 没有 usage，跳过
// {"type":"assistant","message":{"id":"msg_001","usage":{...}},"timestamp":"..."}    ← 用
// {"type":"assistant","message":{"id":"msg_001","usage":{...}},"timestamp":"..."}    ← 同一个 id，跳过
// {"type":"assistant","message":{"id":"msg_001","usage":{...}},"timestamp":"..."}    ← 同一个 id，跳过
// {"type":"assistant","message":{"id":"msg_002","usage":{...}},"timestamp":"..."}    ← 用
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
    //Codex 的解析。它记的是**累计值**，所以：`last` 不断覆盖得到「最新累计」；
    // `beforeToday` 记录「今天之前最后一次累计」；今日量 = 两者相减

//     {"type":"session_meta","payload":{"cwd":"/Users/x/api","id":"..."}}                       ← 只取 payload.cwd
// {"type":"token_count","payload":{"info":{"total_token_usage":{...}}},"timestamp":"..."}   ← 累计快照 1
// {"type":"token_count","payload":{"info":{"total_token_usage":{...}}},"timestamp":"..."}   ← 累计快照 2（覆盖）
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


    
    //一个通用函数：执行外部命令，把它的输出当字符串返回。全项目只用它跑 `ps` 和 `lsof`
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
    //先用 `ps` 拿到所有进程、用 adapter 判断哪些是 AI 工具的；再用 `lsof` 问每个进程「你的工作目录是什么、你正打开着哪个 jsonl」
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
    private func probeProcesses(pids: [Int]) -> [Int: (cwd: String?, transcripts: [String])] {
        guard !pids.isEmpty else { return [:] }
        let csv = pids.map(String.init).joined(separator: ",")
        let out = runCmd("/usr/sbin/lsof", ["-w", "-p", csv, "-Fpfn"])
        var map: [Int: (cwd: String?, transcripts: [String])] = [:]
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
                    map[pid, default: (nil, [])].cwd = val
                } else if val.hasSuffix(".jsonl"),
                          val.contains("/.codex/sessions/")
                            || val.contains("/.claude/projects/") {
                    map[pid, default: (nil, [])].transcripts.append(val)
                }
            default:
                break
            }
        }
        return map
    }
    //把「进程」和「会话文件」配起来。策略两级：先看它正打开的文件（最准），不行再按工作目录推断
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
    
////先写上支持哪些工具
    //把闭环 5 里那两个**占位 adapter** 换成真实版：接上「怎么认进程」和「怎么配对」。换完之后，`collect()` 才第一次能配出活会话
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
            }
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
            }
        )
    }
    
}
