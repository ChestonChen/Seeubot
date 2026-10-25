import Foundation
//每一个agent的信息
struct AgentDescriptor: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var display: String //展示的名称
    var glyph: String //图标
    static let claude = AgentDescriptor(id: "claude", display: "Claude", glyph: "✦")
    static let codex = AgentDescriptor(id: "codex", display: "Codex", glyph: "◆")
}
//记录会话状态
enum SessionState: String, Codable {
    case working
    case idle
}

//枚举不同状态
enum WidgetMode: String, Codable, CaseIterable {
    case hanging //药丸
    case sides  //长条
    var next: WidgetMode { self == .hanging ? .sides : .hanging }
    var label: String { self == .hanging ? "Hanging" : "Bar" }
    var icon: String { self == .hanging ? "arrowtriangle.down.fill" : "arrow.left.and.right" }
}

//活着的会话
struct LiveSession: Codable, Identifiable, Equatable {
    var id: String
    var pid: Int
    var tool: AgentDescriptor
    var project: String
    var cwd: String
    var state: SessionState
    var tokens: Int
    var idleSeconds: Double
}

//把token拆解
struct TokenBreakdown: Codable, Equatable {
    var output: Int = 0 //输出
    var inputFresh: Int = 0 //新输入的
    var cacheCreate: Int = 0 //写进缓存
    var cacheRead: Int = 0  //读取缓存量
    var total: Int { output + inputFresh + cacheCreate + cacheRead } //总量
    //求和
    static func + (a: TokenBreakdown, b: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(output: a.output + b.output,
                       inputFresh: a.inputFresh + b.inputFresh,
                       cacheCreate: a.cacheCreate + b.cacheCreate,
                       cacheRead: a.cacheRead + b.cacheRead)
    }
    static func += (a: inout TokenBreakdown, b: TokenBreakdown) { a = a + b }
    //用两个快照相减求今日量
    static func clampedMinus(_ a: TokenBreakdown, _ b: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(output: max(0, a.output - b.output),
                       inputFresh: max(0, a.inputFresh - b.inputFresh),
                       cacheCreate: max(0, a.cacheCreate - b.cacheCreate),
                       cacheRead: max(0, a.cacheRead - b.cacheRead))
    }
}

//一个agent内部该有的配置信息
struct ToolStat: Codable, Equatable {
    var tool: AgentDescriptor
    var live: Int
    var working: Int
    var idle: Int
    var tokensAllTime: TokenBreakdown
    var tokensToday: TokenBreakdown
    var sessionsAllTime: Int
}
//界面每次刷新拿到的数据快照
struct DashStats: Codable, Equatable {
    var sessions: [LiveSession] //每个ai的的活着的会话
    var perTool: [ToolStat] //一个agent的汇总
    var totalLive: Int //活会话数量
    var totalWorking: Int //working状态的
    var totalIdle: Int
    var tokensAllTime: TokenBreakdown //所有会话的token
    var tokensToday: TokenBreakdown
    var sessionsAllTime: Int //历史会话数
    var updatedAtEpoch: Double //采集的时间戳
    static let empty = DashStats( //先拿个空快照，防止为nil崩溃
        sessions: [], perTool: [],
        totalLive: 0, totalWorking: 0, totalIdle: 0,
        tokensAllTime: TokenBreakdown(), tokensToday: TokenBreakdown(),
        sessionsAllTime: 0, updatedAtEpoch: 0
    )
}

enum Fmt { //把数量压成不同数量级
    static func compact(_ n: Int) -> String {
        let v = Double(n)
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