import Foundation

// MARK: - Core domain models shared by the collector and the UI.

enum Tool: String, Codable, CaseIterable {
    case claude
    case codex

    var display: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        }
    }

    /// Short glyph used in the collapsed pill.
    var glyph: String {
        switch self {
        case .claude: return "✦"
        case .codex:  return "◆"
        }
    }
}

enum SessionState: String, Codable {
    case working   // transcript written within the "working" window -> actively producing
    case idle      // process alive but quiet -> waiting on the human
}

/// How the collapsed widget is presented around the notch.
enum WidgetMode: String, Codable, CaseIterable {
    case hanging   // one pill hanging below the notch center
    case sides     // two "ears" flanking the notch, at the menu-bar line

    var next: WidgetMode { self == .hanging ? .sides : .hanging }
    var label: String { self == .hanging ? "Hanging" : "Bar" }
    var icon: String { self == .hanging ? "arrowtriangle.down.fill" : "arrow.left.and.right" }
}

/// One currently-open agent session (backed by a running process).
struct LiveSession: Codable, Identifiable, Equatable {
    var id: String            // stable id: "\(tool)-\(pid)"
    var pid: Int
    var tool: Tool
    var project: String       // last path component of the working dir
    var cwd: String
    var state: SessionState
    var tokens: Int           // tokens accumulated in this session's transcript
    var idleSeconds: Double   // seconds since the transcript last changed
}

/// A breakdown of token usage so the dashboard can explain the (large) totals.
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
        TokenBreakdown(output: max(0, a.output - b.output),
                       inputFresh: max(0, a.inputFresh - b.inputFresh),
                       cacheCreate: max(0, a.cacheCreate - b.cacheCreate),
                       cacheRead: max(0, a.cacheRead - b.cacheRead))
    }
}

/// Aggregate numbers for a single tool.
struct ToolStat: Codable, Equatable {
    var tool: Tool
    var live: Int
    var working: Int
    var idle: Int
    var tokensAllTime: TokenBreakdown
    var tokensToday: TokenBreakdown
    var sessionsAllTime: Int   // number of transcript files on disk
}

/// The full snapshot the widget renders.
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

    func stat(for tool: Tool) -> ToolStat {
        perTool.first { $0.tool == tool }
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
