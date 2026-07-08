export type AgentDescriptor = {
  id: string;
  display: string;
  glyph: string;
};

export type TokenBreakdown = {
  output: number;
  inputFresh: number;
  cacheCreate: number;
  cacheRead: number;
};

export type LiveSession = {
  id: string;
  pid: number;
  tool: AgentDescriptor;
  project: string;
  cwd: string;
  state: "working" | "idle";
  tokens: number;
  idleSeconds: number;
};

export type ToolStat = {
  tool: AgentDescriptor;
  live: number;
  working: number;
  idle: number;
  tokensAllTime: TokenBreakdown;
  tokensToday: TokenBreakdown;
  sessionsAllTime: number;
};

export type DashStats = {
  sessions: LiveSession[];
  perTool: ToolStat[];
  totalLive: number;
  totalWorking: number;
  totalIdle: number;
  tokensAllTime: TokenBreakdown;
  tokensToday: TokenBreakdown;
  sessionsAllTime: number;
  updatedAtEpoch: number;
};

export const emptyStats: DashStats = {
  sessions: [],
  perTool: [],
  totalLive: 0,
  totalWorking: 0,
  totalIdle: 0,
  tokensAllTime: { output: 0, inputFresh: 0, cacheCreate: 0, cacheRead: 0 },
  tokensToday: { output: 0, inputFresh: 0, cacheCreate: 0, cacheRead: 0 },
  sessionsAllTime: 0,
  updatedAtEpoch: 0,
};
