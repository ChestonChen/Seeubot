import Foundation

// 系统 API 速览：
// - Codable：系统协议，让结构体可以被 JSONEncoder/JSONDecoder 编解码。
// - Equatable / Hashable：系统协议，用于比较、放进 Set/Dictionary。
// - Identifiable：SwiftUI 常用协议，ForEach 可以通过 id 稳定识别元素。
// - String(format:)：Foundation 的格式化字符串函数，用于压缩数字显示。
// MARK: - Core domain models shared by the collector and the UI.
// 这里是“采集层”和“UI 层”的共同语言：采集器只负责产出这些结构，
// SwiftUI 页面只读取这些结构来渲染，不需要知道底层文件怎么解析。

struct AgentDescriptor: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var display: String
    /// 每个 AI 工具的展示信息。新增 agent 时优先在这里补 id/name/glyph。
    var glyph: String

    static let claude = AgentDescriptor(id: "claude", display: "Claude", glyph: "✦")
    static let codex = AgentDescriptor(id: "codex", display: "Codex", glyph: "◆")
    static let cursor = AgentDescriptor(id: "cursor", display: "Cursor", glyph: "C")
}

enum SessionState: String, Codable {
    case working   // 最近仍有输出/任务回合未结束，UI 上显示为工作中
    case idle      // session 还在，但最近没有活动，UI 上显示为空闲
}

/// How the collapsed widget is presented around the notch.
enum WidgetMode: String, Codable, CaseIterable {
    case hanging   // one pill hanging below the notch center
    case sides     // two "ears" flanking the notch, at the menu-bar line

    var next: WidgetMode { self == .hanging ? .sides : .hanging }
    var label: String { self == .hanging ? "Hanging" : "Bar" }
    var icon: String { self == .hanging ? "arrowtriangle.down.fill" : "arrow.left.and.right" }
}

/// 一个当前可展示的 agent 会话。Claude/Codex 通常对应进程，Cursor 则可能来自 transcript。
struct LiveSession: Codable, Identifiable, Equatable {
    var id: String            // stable id: "\(tool)-\(pid)"
    var pid: Int
    var tool: AgentDescriptor
    var project: String       // last path component of the working dir
    var cwd: String
    var state: SessionState
    var tokens: Int           // tokens accumulated in this session's transcript
    var idleSeconds: Double   // seconds since the transcript last changed
}

/// token 拆分。Dashboard 的总量、today、分段条都来自这里。
struct TokenBreakdown: Codable, Equatable {
    var output: Int = 0        // tokens the model generated
    var inputFresh: Int = 0    // uncached prompt tokens
    var cacheCreate: Int = 0   // tokens written into the prompt cache (Claude)
    var cacheRead: Int = 0     // tokens served from cache (cheap re-reads)

    var total: Int { output + inputFresh + cacheCreate + cacheRead }
    /// Everything that isn't a cheap cache re-read — closer to "real" throughput.
    var billableish: Int { output + inputFresh + cacheCreate }

    static func + (a: TokenBreakdown, b: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(output: a.output + b.output,
                       inputFresh: a.inputFresh + b.inputFresh,
                       cacheCreate: a.cacheCreate + b.cacheCreate,
                       cacheRead: a.cacheRead + b.cacheRead)
    }
    static func += (a: inout TokenBreakdown, b: TokenBreakdown) { a = a + b }

    /// Component-wise (a − b), clamped at 0. Used to derive "today" from two
    /// cumulative Codex snapshots.
    static func clampedMinus(_ a: TokenBreakdown, _ b: TokenBreakdown) -> TokenBreakdown {
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        TokenBreakdown(output: max(0, a.output - b.output),
                       // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
                       inputFresh: max(0, a.inputFresh - b.inputFresh),
                       // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
                       cacheCreate: max(0, a.cacheCreate - b.cacheCreate),
                       // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
                       cacheRead: max(0, a.cacheRead - b.cacheRead))
    }
}

/// 某一个工具（Claude/Codex/Cursor）的聚合统计。
struct ToolStat: Codable, Equatable {
    var tool: AgentDescriptor
    var live: Int
    var working: Int
    var idle: Int
    var tokensAllTime: TokenBreakdown
    var tokensToday: TokenBreakdown
    var sessionsAllTime: Int   // number of transcript files on disk
}

/// UI 每次刷新拿到的完整快照。可以把它理解为整个组件的“页面数据模型”。
struct DashStats: Codable, Equatable {
    var sessions: [LiveSession]
    var perTool: [ToolStat]

    var totalLive: Int
    var totalWorking: Int
    var totalIdle: Int
    var tokensAllTime: TokenBreakdown
    var tokensToday: TokenBreakdown
    var sessionsAllTime: Int
    var updatedAtEpoch: Double

    static let empty = DashStats(
        sessions: [], perTool: [],
        totalLive: 0, totalWorking: 0, totalIdle: 0,
        tokensAllTime: TokenBreakdown(), tokensToday: TokenBreakdown(),
        sessionsAllTime: 0, updatedAtEpoch: 0
    )

    func stat(for tool: AgentDescriptor) -> ToolStat {
        perTool.first { $0.tool.id == tool.id }
            ?? ToolStat(tool: tool, live: 0, working: 0, idle: 0,
                        tokensAllTime: TokenBreakdown(), tokensToday: TokenBreakdown(),
                        sessionsAllTime: 0)
    }
}

// MARK: - Human-friendly number formatting.

enum Fmt {
    /// 1234 -> "1.2K", 1_250_000 -> "1.25M", 3_400_000_000 -> "3.4B"
    static func compact(_ n: Int) -> String {
        let v = Double(n)
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        switch abs(n) {
        case 1_000_000_000...:
            return trim(v / 1_000_000_000) + "B"
        case 1_000_000...:
            return trim(v / 1_000_000) + "M"
        case 1_000...:
            return trim(v / 1_000) + "K"
        default:
            return "\(n)"
        }
    }

    private static func trim(_ d: Double) -> String {
        // up to 2 significant decimals, no trailing zeros
        let s = String(format: d < 10 ? "%.2f" : (d < 100 ? "%.1f" : "%.0f"), d)
        if s.contains(".") {
            var t = s
            while t.hasSuffix("0") { t.removeLast() }
            if t.hasSuffix(".") { t.removeLast() }
            return t
        }
        return s
    }
}
