import { appWindow, currentMonitor, LogicalPosition, LogicalSize } from "@tauri-apps/api/window";

const COLLAPSED = { width: 260, height: 72 };
const EXPANDED = { width: 384, height: 540 };
const TOP_OFFSET = 24;

export async function setIslandFrame(expanded: boolean): Promise<void> {
  const size = expanded ? EXPANDED : COLLAPSED;
  await appWindow.setSize(new LogicalSize(size.width, size.height));

  const monitor = await currentMonitor();
  if (!monitor) return;

  const x = monitor.position.x + Math.round((monitor.size.width - size.width) / 2);
  const y = monitor.position.y + TOP_OFFSET;
  await appWindow.setPosition(new LogicalPosition(x, y));
}
