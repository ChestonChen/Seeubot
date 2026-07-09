import { invoke } from "@tauri-apps/api/tauri";
import { useEffect, useRef, useState } from "react";
import { compact, toolColor, toolGradient, totalTokens } from "./format";
import MascotCanvas, { type Mood } from "./MascotCanvas";
import { emptyStats, type DashStats, type LiveSession, type TokenBreakdown, type ToolStat } from "./types";
import { setIslandFrame } from "./windowFrame";

type IslandPhase = "collapsed" | "expanding" | "expanded" | "collapsing";
const CONTENT_REVEAL_MS = 150;

export default function App() {
  const [stats, setStats] = useState<DashStats>(emptyStats);
  const [phase, setPhase] = useState<IslandPhase>("collapsed");
  const [dashboardReady, setDashboardReady] = useState(false);
  const phaseRef = useRef<IslandPhase>("collapsed");
  const transitionToken = useRef(0);
  const revealTimer = useRef<number | null>(null);

  useEffect(() => {
    let mounted = true;
    const refresh = async () => {
      try {
        const next = await invoke<DashStats>("get_stats");
        if (mounted) setStats(next);
      } catch (error) {
        console.error("failed to collect stats", error);
      }
    };
    refresh();
    const timer = window.setInterval(refresh, 1000);
    return () => {
      mounted = false;
      window.clearInterval(timer);
    };
  }, []);

  const setIslandPhase = (next: IslandPhase) => {
    phaseRef.current = next;
    setPhase(next);
  };

  const enter = () => {
    if (phaseRef.current === "expanded" || phaseRef.current === "expanding") return;
    const token = ++transitionToken.current;
    if (revealTimer.current) window.clearTimeout(revealTimer.current);
    setDashboardReady(false);
    setIslandPhase("expanding");
    revealTimer.current = window.setTimeout(() => {
      if (transitionToken.current === token && phaseRef.current === "expanding") {
        setDashboardReady(true);
      }
    }, CONTENT_REVEAL_MS);
    setIslandFrame(true)
      .then(() => {
        if (transitionToken.current !== token) return;
        setIslandPhase("expanded");
        setDashboardReady(true);
      })
      .catch(console.error);
  };

  const leave = () => {
    if (phaseRef.current === "collapsed" || phaseRef.current === "collapsing") return;
    const token = ++transitionToken.current;
    if (revealTimer.current) window.clearTimeout(revealTimer.current);
    setDashboardReady(false);
    setIslandPhase("collapsing");
    setIslandFrame(false)
      .then(() => {
        if (transitionToken.current !== token) return;
        setIslandPhase("collapsed");
      })
      .catch(console.error);
  };

  return (
    <main className={`island ${phase} ${dashboardReady ? "dashboardReady" : ""}`} onMouseEnter={enter} onMouseLeave={leave}>
      <CollapsedPill stats={stats} />
      <Dashboard stats={stats} />
    </main>
  );
}

function moodFromStats(stats: DashStats): Mood {
  if (stats.totalWorking > 0) return "excited";
  if (stats.totalLive > 0) return "idle";
  return "sleeping";
}

function CollapsedPill({ stats }: { stats: DashStats }) {
  return (
    <section className="pill">
      <div className={stats.totalWorking > 0 ? "mascotRunway active" : "mascotRunway"}>
        <div className="runwayBot">
          <MascotCanvas mood={moodFromStats(stats)} size={23} />
        </div>
      </div>
      <div className="pillMetrics">
        <MiniMetric label="Working" icon="⚡" value={stats.totalWorking} color="var(--working)" pulse={stats.totalWorking > 0} />
        <MiniMetric label="Idle" icon="☾" value={stats.totalIdle} color="var(--idle)" />
      </div>
    </section>
  );
}

function MiniMetric({ label, icon, value, color, pulse = false }: { label: string; icon: string; value: number; color: string; pulse?: boolean }) {
  return (
    <div className="miniMetric" title={label}>
      <span className={pulse ? "miniIcon pulse" : "miniIcon"} style={{ color }}>
        {icon}
      </span>
      <strong style={{ color }}>{value}</strong>
    </div>
  );
}

function Dashboard({ stats }: { stats: DashStats }) {
  const toolList = stats.perTool.map((tool) => tool.tool.display).join(" · ") || "No agents";
  return (
    <section className="dashboard">
      <div className="dashboardContent">
        <header className="header">
          <MascotCanvas mood={moodFromStats(stats)} size={34} />
          <div>
            <h1>Seeubot</h1>
            <p>AI SESSION MONITOR</p>
          </div>
          <div className="spacer" />
          <span className="modeBadge">Windows Island</span>
        </header>

        <div className="statGrid">
          <StatTile title="Sessions" value={stats.totalLive} color="var(--ink)" glyph="◎" />
          <StatTile title="Working" value={stats.totalWorking} color="var(--working)" glyph="⚡" pulse={stats.totalWorking > 0} />
          <StatTile title="Idle" value={stats.totalIdle} color="var(--idle)" glyph="☾" />
        </div>

        <TokenHero all={stats.tokensAllTime} today={stats.tokensToday} working={stats.totalWorking > 0} />

        <div className="toolRows">
          {stats.perTool.map((stat) => (
            <ToolRow key={stat.tool.id} stat={stat} grandTotal={Math.max(1, totalTokens(stats.tokensAllTime))} />
          ))}
        </div>

        <LiveSessions sessions={stats.sessions} />

        <footer className="footer">
          <span>{stats.sessionsAllTime} sessions all-time</span>
          <span>{toolList}</span>
        </footer>
      </div>
    </section>
  );
}

function StatTile({ title, value, color, glyph, pulse = false }: { title: string; value: number; color: string; glyph: string; pulse?: boolean }) {
  return (
    <div className="statTile" style={{ "--accent": color } as React.CSSProperties}>
      <div className="statTitle">
        <span className={pulse ? "dot pulse" : "dot"} style={{ background: color }} />
        {title}
      </div>
      <div className="statValue">
        <strong>{value}</strong>
        <span>{glyph}</span>
      </div>
    </div>
  );
}

function TokenHero({ all, today, working }: { all: TokenBreakdown; today: TokenBreakdown; working: boolean }) {
  const total = Math.max(1, totalTokens(all));
  const segments = [
    ["Output", all.output, "var(--output)"],
    ["Input", all.inputFresh, "var(--input)"],
    ["Cache-W", all.cacheCreate, "var(--cacheWrite)"],
    ["Cache-R", all.cacheRead, "var(--cacheRead)"],
  ] as const;

  return (
    <section className={`tokenHero ${working ? "workingAura" : ""}`}>
      <div className="tokenTop">
        <div>
          <h2>Total Tokens</h2>
          <strong>{compact(totalTokens(all))}</strong>
        </div>
        <div className="outputBox">
          <span>Output</span>
          <b>{compact(all.output)}</b>
          <em>today {compact(totalTokens(today))}</em>
        </div>
      </div>
      <div className="tokenBar">
        {segments.map(([label, value, color]) => (
          <span key={label} title={`${label} ${compact(value)}`} style={{ width: `${Math.max(value > 0 ? 2 : 0, (value / total) * 100)}%`, background: color }} />
        ))}
      </div>
      <div className="legend">
        {segments.map(([label, value, color]) => (
          <span key={label}>
            <i style={{ background: color }} />
            {label} <b>{compact(value)}</b>
          </span>
        ))}
      </div>
    </section>
  );
}

function ToolRow({ stat, grandTotal }: { stat: ToolStat; grandTotal: number }) {
  const color = toolColor(stat.tool);
  const share = Math.max(0, Math.min(100, (totalTokens(stat.tokensAllTime) / grandTotal) * 100));
  return (
    <div className="toolRow">
      <div className="toolBadge" style={{ background: toolGradient(stat.tool) }}>
        {stat.tool.glyph}
      </div>
      <div className="toolMain">
        <div className="toolMeta">
          <strong>{stat.tool.display}</strong>
          {stat.working > 0 && <span className="workingText">⚡ {stat.working}</span>}
          {stat.idle > 0 && <span className="idleText">☾ {stat.idle}</span>}
          <b style={{ color }}>{compact(totalTokens(stat.tokensAllTime))}</b>
        </div>
        <div className="shareTrack">
          <span style={{ width: `${share}%`, background: toolGradient(stat.tool) }} />
        </div>
      </div>
    </div>
  );
}

function LiveSessions({ sessions }: { sessions: LiveSession[] }) {
  return (
    <section className="liveBlock">
      <h2>
        Live Sessions <span>{sessions.length}</span>
      </h2>
      {sessions.length === 0 ? (
        <p className="quiet">All quiet — grab a coffee</p>
      ) : (
        <div className="chips">
          {sessions.slice(0, 8).map((session) => (
            <span className="chip" key={session.id} style={{ "--accent": session.state === "working" ? "var(--working)" : "var(--idle)" } as React.CSSProperties}>
              <i className={session.state === "working" ? "dot pulse" : "dot"} />
              <b>{session.tool.glyph}</b>
              {session.project}
            </span>
          ))}
        </div>
      )}
    </section>
  );
}
