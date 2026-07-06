import Foundation

/// Scans Claude Code and Codex on-disk transcripts plus the live process list to
/// produce a `DashStats` snapshot. Cheap to call repeatedly: per-file token totals
/// are cached and only re-parsed when a file's size/mtime changes.
final class SessionCollector {

    /// A transcript written within this many seconds is treated as "working".
    static let workingWindow: TimeInterval = 45

    private let home = NSHomeDirectory()

    private struct FileInfo {
        var mtime: TimeInterval
        var size: Int
        var tokens: TokenBreakdown        // whole-file total
        var todayTokens: TokenBreakdown   // portion whose timestamps are >= start of today
        var cwd: String?                  // codex only (from session_meta)
    }

    // path -> parsed info (validated against size+mtime so stale entries are ignored)
    private var cache: [String: FileInfo] = [:]

    // MARK: - Public entry point

    func collect() -> DashStats {
        let now = Date().timeIntervalSince1970
        let startOfToday = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970

        let claudeFiles = enumerateJSONL(dir: home + "/.claude/projects")
        let codexFiles  = enumerateJSONL(dir: home + "/.codex/sessions")

        var infoByPath: [String: FileInfo] = [:]
        infoByPath.reserveCapacity(claudeFiles.count + codexFiles.count)
        for p in claudeFiles { infoByPath[p] = info(forClaude: p, startOfToday: startOfToday) }
        for p in codexFiles  { infoByPath[p] = info(forCodex: p, startOfToday: startOfToday) }

        // Bound the long-lived cache to files still on disk (evict deleted/rotated).
        cache = cache.filter { infoByPath.keys.contains($0.key) }

        // ---- Aggregate token totals across every transcript on disk ----
        func totals(_ paths: [String]) -> (all: TokenBreakdown, today: TokenBreakdown, count: Int) {
            var all = TokenBreakdown(), today = TokenBreakdown()
            for p in paths {
                guard let fi = infoByPath[p] else { continue }
                all += fi.tokens
                if fi.mtime >= startOfToday { today += fi.todayTokens }
            }
            return (all, today, paths.count)
        }
        let claudeTotals = totals(claudeFiles)
        let codexTotals  = totals(codexFiles)

        // ---- Live processes -> sessions ----
        let procs = liveProcesses()
        let probe = probeProcesses(pids: procs.map { $0.pid })   // pid -> (cwd, open transcript)

        var sessions: [LiveSession] = []
        var claimed = Set<String>()   // transcripts already assigned to a session
        for p in procs {
            let cwd = probe[p.pid]?.cwd ?? ""
            let transcript = resolveTranscript(tool: p.tool, cwd: cwd,
                                               openPath: probe[p.pid]?.transcript,
                                               infoByPath: infoByPath, claimed: &claimed)
            let idleSeconds = transcript.map { max(0, now - $0.mtime) } ?? .infinity
            let state: SessionState = idleSeconds < Self.workingWindow ? .working : .idle
            sessions.append(LiveSession(
                id: "\(p.tool.rawValue)-\(p.pid)",
                pid: p.pid,
                tool: p.tool,
                project: projectName(from: cwd),
                cwd: cwd,
                state: state,
                tokens: transcript?.tokens.total ?? 0,
                idleSeconds: idleSeconds.isFinite ? idleSeconds : -1
            ))
        }
        // Working first, then most-recently active.
        sessions.sort {
            if ($0.state == .working) != ($1.state == .working) { return $0.state == .working }
            return $0.idleSeconds < $1.idleSeconds
        }

        func toolStat(_ tool: Tool, _ t: (all: TokenBreakdown, today: TokenBreakdown, count: Int)) -> ToolStat {
            let s = sessions.filter { $0.tool == tool }
            return ToolStat(
                tool: tool,
                live: s.count,
                working: s.filter { $0.state == .working }.count,
                idle: s.filter { $0.state == .idle }.count,
                tokensAllTime: t.all,
                tokensToday: t.today,
                sessionsAllTime: t.count
            )
        }
        let perTool = [toolStat(.claude, claudeTotals), toolStat(.codex, codexTotals)]

        return DashStats(
            sessions: sessions,
            perTool: perTool,
            totalLive: sessions.count,
            totalWorking: sessions.filter { $0.state == .working }.count,
            totalIdle: sessions.filter { $0.state == .idle }.count,
            tokensAllTime: claudeTotals.all + codexTotals.all,
            tokensToday: claudeTotals.today + codexTotals.today,
            sessionsAllTime: claudeTotals.count + codexTotals.count,
            updatedAtEpoch: now
        )
    }

    // MARK: - File enumeration

    private func enumerateJSONL(dir: String) -> [String] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: URL(fileURLWithPath: dir),
                                     includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            // Skip nested subagent sidechains / workflow journals — they are not
            // top-level sessions and would inflate counts and token totals.
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

    // MARK: - Cached per-file parsing

    private func info(forClaude path: String, startOfToday: TimeInterval) -> FileInfo {
        guard let st = statOf(path) else {
            return FileInfo(mtime: 0, size: 0, tokens: TokenBreakdown(), todayTokens: TokenBreakdown(), cwd: nil)
        }
        if let c = cache[path], c.mtime == st.mtime, c.size == st.size { return c }
        let (all, today) = parseClaude(path, startOfToday: startOfToday)
        let fi = FileInfo(mtime: st.mtime, size: st.size, tokens: all, todayTokens: today, cwd: nil)
        cache[path] = fi
        return fi
    }

    private func info(forCodex path: String, startOfToday: TimeInterval) -> FileInfo {
        guard let st = statOf(path) else {
            return FileInfo(mtime: 0, size: 0, tokens: TokenBreakdown(), todayTokens: TokenBreakdown(), cwd: nil)
        }
        if let c = cache[path], c.mtime == st.mtime, c.size == st.size { return c }
        let (all, today, cwd) = parseCodex(path, startOfToday: startOfToday)
        let fi = FileInfo(mtime: st.mtime, size: st.size, tokens: all, todayTokens: today, cwd: cwd)
        cache[path] = fi
        return fi
    }

    /// Claude transcript: sum each assistant message's usage buckets, de-duplicated
    /// by message.id (Claude writes one response across several lines, all carrying
    /// the same id and the same cumulative usage). Also computes today's portion.
    private func parseClaude(_ path: String, startOfToday: TimeInterval) -> (TokenBreakdown, TokenBreakdown) {
        guard let data = FileManager.default.contents(atPath: path) else { return (TokenBreakdown(), TokenBreakdown()) }
        let text = String(decoding: data, as: UTF8.self)   // tolerant: bad bytes -> U+FFFD
        var all = TokenBreakdown(), today = TokenBreakdown()
        var seen = Set<String>()
        text.enumerateLines { line, _ in
            guard line.contains("\"usage\"") else { return }
            guard let ld = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any],
                  (obj["type"] as? String) == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any] else { return }
            let mid = msg["id"] as? String ?? (obj["uuid"] as? String ?? "")
            if !mid.isEmpty { guard seen.insert(mid).inserted else { return } }
            var bd = TokenBreakdown()
            bd.inputFresh  = usage["input_tokens"] as? Int ?? 0
            bd.cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
            bd.cacheRead   = usage["cache_read_input_tokens"] as? Int ?? 0
            bd.output      = usage["output_tokens"] as? Int ?? 0
            all += bd
            if let ts = obj["timestamp"] as? String, let e = self.epoch(ts), e >= startOfToday {
                today += bd
            }
        }
        return (all, today)
    }

    /// Codex rollout: cumulative `token_count` totals. All-time = last cumulative;
    /// today = last cumulative minus the last cumulative recorded before today.
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
                if let ld = line.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any],
                   (obj["type"] as? String) == "session_meta",
                   let payload = obj["payload"] as? [String: Any] {
                    cwd = payload["cwd"] as? String
                }
            }
            guard line.contains("total_token_usage") else { return }
            guard let ld = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let inf = payload["info"] as? [String: Any],
                  let tot = inf["total_token_usage"] as? [String: Any] else { return }
            var bd = TokenBreakdown()
            let input  = tot["input_tokens"] as? Int ?? 0
            let cached = tot["cached_input_tokens"] as? Int ?? 0
            bd.output     = tot["output_tokens"] as? Int ?? 0
            bd.inputFresh = max(0, input - cached)
            bd.cacheRead  = cached
            last = bd
            if let ts = obj["timestamp"] as? String, let e = self.epoch(ts), e < startOfToday {
                beforeToday = bd
            }
        }
        let all = last ?? TokenBreakdown()
        let today = TokenBreakdown.clampedMinus(all, beforeToday ?? TokenBreakdown())
        return (all, today, cwd)
    }

    // ISO-8601 timestamp -> epoch seconds (handles both fractional and plain forms).
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private func epoch(_ s: String) -> TimeInterval? {
        if let d = Self.isoFrac.date(from: s) { return d.timeIntervalSince1970 }
        if let d = Self.isoPlain.date(from: s) { return d.timeIntervalSince1970 }
        return nil
    }

    // MARK: - Live process detection

    private struct Proc { var pid: Int; var tool: Tool }

    private func liveProcesses() -> [Proc] {
        let out = runCmd("/bin/ps", ["-axo", "pid=,command="])
        var res: [Proc] = []
        for raw in out.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let sp = line.firstIndex(of: " ") else { continue }
            guard let pid = Int(line[..<sp]) else { continue }
            let command = String(line[line.index(after: sp)...])
            if let tool = classify(command: command) { res.append(Proc(pid: pid, tool: tool)) }
        }
        return res
    }

    // Codex CLI subcommands that are NOT an interactive/working session.
    private static let codexNonInteractive: Set<String> =
        ["exec", "app-server", "mcp", "login", "logout", "proto", "completion",
         "ls", "help", "--help", "-h", "--version", "-V"]

    /// Returns the tool if `command` is an interactive Claude Code / Codex CLI session.
    /// Matches on the executable basename so it is install-layout / arch independent.
    private func classify(command: String) -> Tool? {
        let firstToken = command.split(separator: " ").first.map(String.init) ?? ""
        let firstBase = (firstToken as NSString).lastPathComponent

        if firstBase == "claude" { return .claude }

        if firstBase == "codex" {
            let rest = command.dropFirst(firstToken.count).trimmingCharacters(in: .whitespaces)
            let firstArg = rest.split(separator: " ").first.map(String.init) ?? ""
            if !Self.codexNonInteractive.contains(firstArg) { return .codex }
        }
        return nil
    }

    /// Batched `lsof` for each pid's cwd and (if held open) its transcript jsonl.
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
            case "p": pid = Int(val) ?? -1; fd = ""
            case "f": fd = val
            case "n":
                guard pid != -1 else { continue }
                if fd == "cwd" {
                    map[pid, default: (nil, nil)].cwd = val
                } else if val.hasSuffix(".jsonl"),
                          val.contains("/.codex/sessions/") || val.contains("/.claude/projects/") {
                    map[pid, default: (nil, nil)].transcript = val
                }
            default: break
            }
        }
        return map
    }

    // MARK: - Mapping a process to its transcript

    private struct Match { var path: String; var mtime: TimeInterval; var tokens: TokenBreakdown }

    private func resolveTranscript(tool: Tool, cwd: String, openPath: String?,
                                   infoByPath: [String: FileInfo],
                                   claimed: inout Set<String>) -> Match? {
        // 1. Exact: the process holds the transcript open (Codex does this).
        if let openPath, !claimed.contains(openPath), let fi = infoByPath[openPath] {
            claimed.insert(openPath)
            return Match(path: openPath, mtime: fi.mtime, tokens: fi.tokens)
        }
        // 2. Heuristic by working directory — hand each pid a distinct transcript.
        guard !cwd.isEmpty else { return nil }
        let match: Match?
        switch tool {
        case .claude:
            let needle = "/projects/" + claudeEncode(cwd) + "/"
            match = newest(infoByPath, claimed: claimed) { path, _ in
                guard let r = path.range(of: needle) else { return false }
                // main transcript sits directly in the project dir (no further slash)
                return !path[r.upperBound...].contains("/")
            }
        case .codex:
            match = newest(infoByPath, claimed: claimed) { _, fi in fi.cwd == cwd }
        }
        if let m = match { claimed.insert(m.path) }
        return match
    }

    private func newest(_ infoByPath: [String: FileInfo], claimed: Set<String>,
                        where predicate: (String, FileInfo) -> Bool) -> Match? {
        var best: Match? = nil
        for (path, fi) in infoByPath where !claimed.contains(path) && predicate(path, fi) {
            if best == nil || fi.mtime > best!.mtime {
                best = Match(path: path, mtime: fi.mtime, tokens: fi.tokens)
            }
        }
        return best
    }

    /// Claude derives a project-dir name from a cwd by replacing every
    /// non-alphanumeric character with "-" (matches Claude Code's own encoder).
    private func claudeEncode(_ cwd: String) -> String {
        String(cwd.unicodeScalars.map { s in
            (s >= "a" && s <= "z") || (s >= "A" && s <= "Z") || (s >= "0" && s <= "9")
                ? Character(s) : "-"
        })
    }

    private func projectName(from cwd: String) -> String {
        if cwd.isEmpty { return "—" }
        let base = (cwd as NSString).lastPathComponent
        return base.isEmpty ? cwd : base
    }

    // MARK: - Subprocess helper

    private func runCmd(_ launch: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice   // never let a full stderr pipe deadlock us
        do { try p.run() } catch { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: d, encoding: .utf8) ?? ""
    }
}
