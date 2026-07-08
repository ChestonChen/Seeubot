use chrono::{DateTime, Local, Utc};
use serde::Serialize;
use serde_json::Value;
use std::{
    collections::{HashMap, HashSet},
    fs,
    path::{Path, PathBuf},
    process::Command,
    sync::Mutex,
    time::{SystemTime, UNIX_EPOCH},
};
use tauri::{
    CustomMenuItem, Manager, PhysicalPosition, PhysicalSize, Position, Size, SystemTray,
    SystemTrayEvent, SystemTrayMenu, Window,
};
use walkdir::WalkDir;

const WORKING_WINDOW_SECS: f64 = 45.0;
const CURSOR_WORKING_WINDOW_SECS: f64 = 12.0;
const CURSOR_OPEN_TURN_WINDOW_SECS: f64 = 30.0 * 60.0;
const CURSOR_IDLE_RETENTION_SECS: f64 = 10.0 * 60.0;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Serialize)]
#[serde(rename_all = "camelCase")]
struct AgentDescriptor {
    id: &'static str,
    display: &'static str,
    glyph: &'static str,
}

impl AgentDescriptor {
    const CLAUDE: AgentDescriptor = AgentDescriptor { id: "claude", display: "Claude", glyph: "✦" };
    const CODEX: AgentDescriptor = AgentDescriptor { id: "codex", display: "Codex", glyph: "◆" };
    const CURSOR: AgentDescriptor = AgentDescriptor { id: "cursor", display: "Cursor", glyph: "C" };
}

#[derive(Clone, Copy, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct TokenBreakdown {
    output: i64,
    input_fresh: i64,
    cache_create: i64,
    cache_read: i64,
}

impl TokenBreakdown {
    fn total(&self) -> i64 {
        self.output + self.input_fresh + self.cache_create + self.cache_read
    }

    fn add(&mut self, other: TokenBreakdown) {
        self.output += other.output;
        self.input_fresh += other.input_fresh;
        self.cache_create += other.cache_create;
        self.cache_read += other.cache_read;
    }

    fn clamped_minus(a: TokenBreakdown, b: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown {
            output: (a.output - b.output).max(0),
            input_fresh: (a.input_fresh - b.input_fresh).max(0),
            cache_create: (a.cache_create - b.cache_create).max(0),
            cache_read: (a.cache_read - b.cache_read).max(0),
        }
    }
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct LiveSession {
    id: String,
    pid: u32,
    tool: AgentDescriptor,
    project: String,
    cwd: String,
    state: String,
    tokens: i64,
    idle_seconds: f64,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ToolStat {
    tool: AgentDescriptor,
    live: usize,
    working: usize,
    idle: usize,
    tokens_all_time: TokenBreakdown,
    tokens_today: TokenBreakdown,
    sessions_all_time: usize,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DashStats {
    sessions: Vec<LiveSession>,
    per_tool: Vec<ToolStat>,
    total_live: usize,
    total_working: usize,
    total_idle: usize,
    tokens_all_time: TokenBreakdown,
    tokens_today: TokenBreakdown,
    sessions_all_time: usize,
    updated_at_epoch: f64,
}

#[derive(Clone, Debug)]
struct FileInfo {
    agent_id: &'static str,
    mtime: f64,
    size: u64,
    tokens: TokenBreakdown,
    today_tokens: TokenBreakdown,
    cwd: Option<String>,
}

#[derive(Clone, Debug)]
struct ProcessInfo {
    command: String,
}

struct Collector {
    cache: HashMap<PathBuf, FileInfo>,
}

impl Collector {
    fn new() -> Self {
        Self { cache: HashMap::new() }
    }

    fn collect(&mut self) -> DashStats {
        let now = now_epoch();
        let start_of_today = start_of_today_epoch();
        let processes = live_processes();

        let descriptors = [AgentDescriptor::CLAUDE, AgentDescriptor::CODEX, AgentDescriptor::CURSOR];
        let mut paths_by_agent: HashMap<&'static str, Vec<PathBuf>> = HashMap::new();
        let mut info_by_path: HashMap<PathBuf, FileInfo> = HashMap::new();

        for agent in descriptors {
            let paths = self.enumerate_agent_files(agent.id);
            for path in &paths {
                let info = self.info_for(path, agent.id, start_of_today);
                info_by_path.insert(path.clone(), info);
            }
            paths_by_agent.insert(agent.id, paths);
        }

        self.cache.retain(|path, _| info_by_path.contains_key(path));

        let mut sessions = Vec::new();
        sessions.extend(self.transcript_sessions_for_agent(
            AgentDescriptor::CLAUDE,
            &paths_by_agent,
            &info_by_path,
            &processes,
            now,
        ));
        sessions.extend(self.transcript_sessions_for_agent(
            AgentDescriptor::CODEX,
            &paths_by_agent,
            &info_by_path,
            &processes,
            now,
        ));
        sessions.extend(self.cursor_sessions(&paths_by_agent, &info_by_path, now));

        sessions.sort_by(|a, b| {
            let aw = a.state == "working";
            let bw = b.state == "working";
            bw.cmp(&aw).then_with(|| a.idle_seconds.total_cmp(&b.idle_seconds))
        });

        let mut per_tool = Vec::new();
        for agent in descriptors {
            let paths = paths_by_agent.get(agent.id).cloned().unwrap_or_default();
            let mut totals = totals(&paths, &info_by_path);
            if agent.id == AgentDescriptor::CURSOR.id {
                if let Some(cursor) = cursor_usage_cache_totals() {
                    totals.0 = cursor;
                    totals.1 = cursor;
                }
            }

            let tool_sessions: Vec<_> = sessions.iter().filter(|s| s.tool.id == agent.id).collect();
            if tool_sessions.is_empty() && paths.is_empty() {
                continue;
            }

            per_tool.push(ToolStat {
                tool: agent,
                live: tool_sessions.len(),
                working: tool_sessions.iter().filter(|s| s.state == "working").count(),
                idle: tool_sessions.iter().filter(|s| s.state == "idle").count(),
                tokens_all_time: totals.0,
                tokens_today: totals.1,
                sessions_all_time: paths.len(),
            });
        }

        let mut tokens_all_time = TokenBreakdown::default();
        let mut tokens_today = TokenBreakdown::default();
        let mut sessions_all_time = 0;
        for stat in &per_tool {
            tokens_all_time.add(stat.tokens_all_time);
            tokens_today.add(stat.tokens_today);
            sessions_all_time += stat.sessions_all_time;
        }

        DashStats {
            total_live: sessions.len(),
            total_working: sessions.iter().filter(|s| s.state == "working").count(),
            total_idle: sessions.iter().filter(|s| s.state == "idle").count(),
            sessions,
            per_tool,
            tokens_all_time,
            tokens_today,
            sessions_all_time,
            updated_at_epoch: now,
        }
    }

    fn enumerate_agent_files(&self, agent_id: &'static str) -> Vec<PathBuf> {
        let mut roots = Vec::new();
        if let Some(home) = dirs::home_dir() {
            match agent_id {
                "claude" => roots.push(home.join(".claude").join("projects")),
                "codex" => roots.push(home.join(".codex").join("sessions")),
                "cursor" => roots.push(home.join(".cursor").join("projects")),
                _ => {}
            }
        }

        let mut paths = Vec::new();
        for root in roots {
            if !root.exists() {
                continue;
            }
            for entry in WalkDir::new(root).into_iter().filter_map(Result::ok) {
                if !entry.file_type().is_file() || entry.path().extension().and_then(|s| s.to_str()) != Some("jsonl") {
                    continue;
                }
                let path_string = entry.path().to_string_lossy().replace('\\', "/");
                if path_string.contains("/subagents/") {
                    continue;
                }
                if agent_id == "cursor" && !path_string.contains("/agent-transcripts/") {
                    continue;
                }
                paths.push(entry.path().to_path_buf());
            }
        }
        paths
    }

    fn info_for(&mut self, path: &Path, agent_id: &'static str, start_of_today: f64) -> FileInfo {
        let (mtime, size) = file_stat(path).unwrap_or((0.0, 0));
        if let Some(cached) = self.cache.get(path) {
            if cached.agent_id == agent_id && cached.mtime == mtime && cached.size == size {
                return cached.clone();
            }
        }

        let (tokens, today_tokens, cwd) = match agent_id {
            "claude" => {
                let (all, today) = parse_claude(path, start_of_today);
                (all, today, claude_cwd_from_path(path))
            }
            "codex" => parse_codex(path, start_of_today),
            "cursor" => (TokenBreakdown::default(), TokenBreakdown::default(), cursor_cwd_from_path(path)),
            _ => (TokenBreakdown::default(), TokenBreakdown::default(), None),
        };
        let info = FileInfo { agent_id, mtime, size, tokens, today_tokens, cwd };
        self.cache.insert(path.to_path_buf(), info.clone());
        info
    }

    fn transcript_sessions_for_agent(
        &self,
        agent: AgentDescriptor,
        paths_by_agent: &HashMap<&'static str, Vec<PathBuf>>,
        info_by_path: &HashMap<PathBuf, FileInfo>,
        processes: &[ProcessInfo],
        now: f64,
    ) -> Vec<LiveSession> {
        let running = processes.iter().any(|p| match agent.id {
            "claude" => is_claude_process(&p.command),
            "codex" => is_interactive_codex(&p.command),
            _ => false,
        });
        if !running {
            return Vec::new();
        }

        let mut paths = paths_by_agent.get(agent.id).cloned().unwrap_or_default();
        paths.sort_by(|a, b| {
            let am = info_by_path.get(a).map(|i| i.mtime).unwrap_or(0.0);
            let bm = info_by_path.get(b).map(|i| i.mtime).unwrap_or(0.0);
            bm.total_cmp(&am)
        });

        let mut sessions = Vec::new();
        let mut seen = HashSet::new();
        for path in paths.into_iter().take(8) {
            let Some(info) = info_by_path.get(&path) else { continue };
            let idle = (now - info.mtime).max(0.0);
            if idle > CURSOR_IDLE_RETENTION_SECS && sessions.len() >= 1 {
                continue;
            }
            let cwd = info.cwd.clone().unwrap_or_default();
            let key = if cwd.is_empty() { path.to_string_lossy().to_string() } else { cwd.clone() };
            if !seen.insert(key) {
                continue;
            }
            sessions.push(LiveSession {
                id: format!("{}-file-{}", agent.id, stable_hash(&path.to_string_lossy())),
                pid: 0,
                tool: agent.clone(),
                project: project_name(&cwd),
                cwd,
                state: if idle < WORKING_WINDOW_SECS { "working" } else { "idle" }.to_string(),
                tokens: info.tokens.total(),
                idle_seconds: idle,
            });
        }
        sessions
    }

    fn cursor_sessions(
        &self,
        paths_by_agent: &HashMap<&'static str, Vec<PathBuf>>,
        info_by_path: &HashMap<PathBuf, FileInfo>,
        now: f64,
    ) -> Vec<LiveSession> {
        let mut paths = paths_by_agent.get("cursor").cloned().unwrap_or_default();
        paths.sort_by(|a, b| {
            let am = info_by_path.get(a).map(|i| i.mtime).unwrap_or(0.0);
            let bm = info_by_path.get(b).map(|i| i.mtime).unwrap_or(0.0);
            bm.total_cmp(&am)
        });

        let mut sessions = Vec::new();
        let mut seen = HashSet::new();
        for path in paths {
            let Some(info) = info_by_path.get(&path) else { continue };
            let idle = (now - info.mtime).max(0.0);
            let open_turn = cursor_transcript_open_turn(&path);
            let visible = match open_turn {
                Some(true) => idle < CURSOR_OPEN_TURN_WINDOW_SECS,
                Some(false) => idle < CURSOR_IDLE_RETENTION_SECS,
                None => idle < CURSOR_WORKING_WINDOW_SECS,
            };
            if !visible {
                continue;
            }
            let cwd = info.cwd.clone().unwrap_or_default();
            let key = if cwd.is_empty() { path.to_string_lossy().to_string() } else { cwd.clone() };
            if !seen.insert(key) {
                continue;
            }
            let state = match open_turn {
                Some(true) => {
                    if idle < CURSOR_OPEN_TURN_WINDOW_SECS { "working" } else { "idle" }
                }
                Some(false) => "idle",
                None => {
                    if idle < CURSOR_WORKING_WINDOW_SECS { "working" } else { "idle" }
                }
            };
            sessions.push(LiveSession {
                id: format!("cursor-file-{}", stable_hash(&path.to_string_lossy())),
                pid: 0,
                tool: AgentDescriptor::CURSOR,
                project: project_name(&cwd),
                cwd,
                state: state.to_string(),
                tokens: 0,
                idle_seconds: idle,
            });
            if sessions.len() >= 8 {
                break;
            }
        }
        sessions
    }
}

#[tauri::command]
fn get_stats(state: tauri::State<Mutex<Collector>>) -> DashStats {
    state.lock().expect("collector poisoned").collect()
}

fn position_pill(window: &Window, width: u32, height: u32) {
    if let Ok(Some(monitor)) = window.current_monitor() {
        let size = monitor.size();
        let pos = monitor.position();
        let x = pos.x + ((size.width as i32 - width as i32) / 2);
        let y = pos.y + 24;
        let _ = window.set_size(Size::Physical(PhysicalSize { width, height }));
        let _ = window.set_position(Position::Physical(PhysicalPosition { x, y }));
    }
}

fn main() {
    let show = CustomMenuItem::new("show".to_string(), "Show Seeubot");
    let homepage = CustomMenuItem::new("homepage".to_string(), "Homepage");
    let quit = CustomMenuItem::new("quit".to_string(), "Quit");
    let tray = SystemTray::new().with_menu(SystemTrayMenu::new().add_item(show).add_item(homepage).add_item(quit));

    tauri::Builder::default()
        .manage(Mutex::new(Collector::new()))
        .invoke_handler(tauri::generate_handler![get_stats])
        .system_tray(tray)
        .setup(|app| {
            if let Some(window) = app.get_window("main") {
                position_pill(&window, 260, 72);
                let _ = window.show();
            }
            Ok(())
        })
        .on_system_tray_event(|app, event| match event {
            SystemTrayEvent::MenuItemClick { id, .. } if id.as_str() == "quit" => {
                std::process::exit(0);
            }
            SystemTrayEvent::MenuItemClick { id, .. } if id.as_str() == "homepage" => {
                let _ = tauri::api::shell::open(&app.shell_scope(), "https://github.com/ChestonChen/Seeubot", None);
            }
            SystemTrayEvent::MenuItemClick { id, .. } if id.as_str() == "show" => {
                if let Some(window) = app.get_window("main") {
                    position_pill(&window, 260, 72);
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            _ => {}
        })
        .run(tauri::generate_context!())
        .expect("failed to run Seeubot Windows");
}

fn totals(paths: &[PathBuf], info_by_path: &HashMap<PathBuf, FileInfo>) -> (TokenBreakdown, TokenBreakdown) {
    let mut all = TokenBreakdown::default();
    let mut today = TokenBreakdown::default();
    for path in paths {
        if let Some(info) = info_by_path.get(path) {
            all.add(info.tokens);
            today.add(info.today_tokens);
        }
    }
    (all, today)
}

fn parse_claude(path: &Path, start_of_today: f64) -> (TokenBreakdown, TokenBreakdown) {
    let text = fs::read_to_string(path).unwrap_or_default();
    let mut all = TokenBreakdown::default();
    let mut today = TokenBreakdown::default();
    let mut seen = HashSet::new();

    for line in text.lines().filter(|line| line.contains("\"usage\"")) {
        let Ok(obj) = serde_json::from_str::<Value>(line) else { continue };
        if obj.get("type").and_then(Value::as_str) != Some("assistant") {
            continue;
        }
        let Some(message) = obj.get("message") else { continue };
        let Some(usage) = message.get("usage") else { continue };
        if let Some(id) = message.get("id").or_else(|| obj.get("uuid")).and_then(Value::as_str) {
            if !seen.insert(id.to_string()) {
                continue;
            }
        }

        let breakdown = TokenBreakdown {
            input_fresh: int_field(usage, "input_tokens"),
            cache_create: int_field(usage, "cache_creation_input_tokens"),
            cache_read: int_field(usage, "cache_read_input_tokens"),
            output: int_field(usage, "output_tokens"),
        };
        all.add(breakdown);
        if obj.get("timestamp").and_then(Value::as_str).and_then(parse_epoch).unwrap_or(0.0) >= start_of_today {
            today.add(breakdown);
        }
    }
    (all, today)
}

fn parse_codex(path: &Path, start_of_today: f64) -> (TokenBreakdown, TokenBreakdown, Option<String>) {
    let text = fs::read_to_string(path).unwrap_or_default();
    let mut cwd = None;
    let mut last = None;
    let mut before_today = None;

    for (index, line) in text.lines().enumerate() {
        let Ok(obj) = serde_json::from_str::<Value>(line) else { continue };
        if index == 0 && obj.get("type").and_then(Value::as_str) == Some("session_meta") {
            cwd = obj.pointer("/payload/cwd").and_then(Value::as_str).map(str::to_string);
        }
        if !line.contains("total_token_usage") {
            continue;
        }
        if obj.pointer("/payload/type").and_then(Value::as_str) != Some("token_count") {
            continue;
        }
        let Some(total_usage) = obj.pointer("/payload/info/total_token_usage") else { continue };
        let input = int_field(total_usage, "input_tokens");
        let cached = int_field(total_usage, "cached_input_tokens");
        let breakdown = TokenBreakdown {
            output: int_field(total_usage, "output_tokens"),
            input_fresh: (input - cached).max(0),
            cache_create: 0,
            cache_read: cached,
        };
        last = Some(breakdown);
        if obj.get("timestamp").and_then(Value::as_str).and_then(parse_epoch).unwrap_or(f64::MAX) < start_of_today {
            before_today = Some(breakdown);
        }
    }

    let all = last.unwrap_or_default();
    let today = TokenBreakdown::clamped_minus(all, before_today.unwrap_or_default());
    (all, today, cwd)
}

fn cursor_usage_cache_totals() -> Option<TokenBreakdown> {
    let appdata = std::env::var("APPDATA").ok().map(PathBuf::from)?;
    let path = appdata
        .join("Cursor")
        .join("User")
        .join("globalStorage")
        .join("panshenbing.cursor-usage-dashboard")
        .join("usage-refresh-cache.json");
    let data = fs::read_to_string(path).ok()?;
    let root = serde_json::from_str::<Value>(&data).ok()?;
    let stats = root.pointer("/data/todayStats")?;
    Some(TokenBreakdown {
        output: int_field(stats, "outputTokens"),
        input_fresh: int_field(stats, "inputTokens"),
        cache_create: int_field(stats, "cacheWriteTokens"),
        cache_read: int_field(stats, "cacheReadTokens"),
    })
}

fn live_processes() -> Vec<ProcessInfo> {
    let output = Command::new("powershell")
        .args([
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            "Get-CimInstance Win32_Process | Select-Object ProcessId,Name,CommandLine,ExecutablePath | ConvertTo-Json -Compress",
        ])
        .output();
    let Ok(output) = output else { return Vec::new() };
    let text = String::from_utf8_lossy(&output.stdout);
    let Ok(value) = serde_json::from_str::<Value>(&text) else { return Vec::new() };

    let rows: Vec<Value> = match value {
        Value::Array(rows) => rows,
        Value::Object(_) => vec![value],
        _ => Vec::new(),
    };

    rows.into_iter()
        .filter_map(|row| {
            let command = row
                .get("CommandLine")
                .or_else(|| row.get("ExecutablePath"))
                .or_else(|| row.get("Name"))
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            Some(ProcessInfo { command })
        })
        .collect()
}

fn is_claude_process(command: &str) -> bool {
    executable_base(command).eq_ignore_ascii_case("claude")
        || command.to_ascii_lowercase().contains("\\claude")
}

fn is_interactive_codex(command: &str) -> bool {
    let base = executable_base(command).to_ascii_lowercase();
    if base != "codex" && base != "codex.exe" && !command.to_ascii_lowercase().contains("\\codex") {
        return false;
    }
    let first_arg = command.split_whitespace().skip(1).next().unwrap_or("");
    !matches!(
        first_arg,
        "exec" | "app-server" | "mcp" | "login" | "logout" | "proto" | "completion" | "ls" | "help" | "--help" | "-h" | "--version" | "-V"
    )
}

fn executable_base(command: &str) -> String {
    let first = command.split_whitespace().next().unwrap_or("").trim_matches('"');
    Path::new(first)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(first)
        .to_string()
}

fn cursor_transcript_open_turn(path: &Path) -> Option<bool> {
    let text = fs::read_to_string(path).ok()?;
    let last = text.lines().rev().find(|line| !line.trim().is_empty())?;
    Some(!last.contains("\"type\":\"turn_ended\""))
}

fn claude_cwd_from_path(path: &Path) -> Option<String> {
    let encoded = path.parent()?.file_name()?.to_string_lossy();
    Some(format!("/{}", encoded.replace('-', "/")))
}

fn cursor_cwd_from_path(path: &Path) -> Option<String> {
    let parts: Vec<String> = path.components().map(|c| c.as_os_str().to_string_lossy().to_string()).collect();
    let index = parts.iter().position(|part| part == "projects")?;
    let encoded = parts.get(index + 1)?;
    if encoded == "empty-window" {
        return Some("empty-window".to_string());
    }
    Some(encoded.replace('-', "\\"))
}

fn file_stat(path: &Path) -> Option<(f64, u64)> {
    let meta = fs::metadata(path).ok()?;
    let modified = meta.modified().ok()?.duration_since(UNIX_EPOCH).ok()?.as_secs_f64();
    Some((modified, meta.len()))
}

fn now_epoch() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs_f64()
}

fn start_of_today_epoch() -> f64 {
    let now = Local::now();
    now.date_naive()
        .and_hms_opt(0, 0, 0)
        .and_then(|d| d.and_local_timezone(Local).single())
        .map(|d| d.timestamp() as f64)
        .unwrap_or(0.0)
}

fn parse_epoch(value: &str) -> Option<f64> {
    DateTime::parse_from_rfc3339(value)
        .map(|d| d.with_timezone(&Utc).timestamp() as f64)
        .ok()
}

fn int_field(value: &Value, key: &str) -> i64 {
    value.get(key).and_then(Value::as_i64).unwrap_or(0)
}

fn project_name(cwd: &str) -> String {
    if cwd.is_empty() {
        return "-".to_string();
    }
    cwd.replace('\\', "/")
        .split('/')
        .filter(|s| !s.is_empty())
        .last()
        .unwrap_or(cwd)
        .to_string()
}

fn stable_hash(value: &str) -> String {
    let mut hash: u64 = 1469598103934665603;
    for byte in value.as_bytes() {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(1099511628211);
    }
    format!("{hash:x}")
}
