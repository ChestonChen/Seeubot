import type { AgentDescriptor, TokenBreakdown } from "./types";

export function compact(value: number): string {
  const abs = Math.abs(value);
  if (abs >= 1_000_000_000) return trim(value / 1_000_000_000) + "B";
  if (abs >= 1_000_000) return trim(value / 1_000_000) + "M";
  if (abs >= 1_000) return trim(value / 1_000) + "K";
  return String(value);
}

function trim(value: number): string {
  const fixed = value >= 10 ? value.toFixed(1) : value.toFixed(2);
  return fixed.replace(/\.0$/, "").replace(/0$/, "");
}

export function totalTokens(tokens: TokenBreakdown): number {
  return tokens.output + tokens.inputFresh + tokens.cacheCreate + tokens.cacheRead;
}

export function toolColor(tool: AgentDescriptor): string {
  switch (tool.id) {
    case "claude":
      return "#ff8c61";
    case "codex":
      return "#5ee6cc";
    case "cursor":
      return "#9eaaff";
    default:
      return "#a6a6ad";
  }
}

export function toolGradient(tool: AgentDescriptor): string {
  switch (tool.id) {
    case "claude":
      return "linear-gradient(135deg, #ff8c61, #eb5433)";
    case "codex":
      return "linear-gradient(135deg, #5ee6cc, #18b8a3)";
    case "cursor":
      return "linear-gradient(135deg, #9eaaff, #5f6bea)";
    default:
      return "linear-gradient(135deg, #b8b8c0, #777985)";
  }
}
