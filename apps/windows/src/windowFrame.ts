import { appWindow, currentMonitor, PhysicalPosition, PhysicalSize } from "@tauri-apps/api/window";

const COLLAPSED = { width: 244, height: 46 };
const EXPANDED = { width: 384, height: 540 };
const TOP_OFFSET = 18;

let lastFrame = { width: 0, height: 0, x: 0, y: 0 };

export async function setIslandFrame(expanded: boolean): Promise<void> {
  const monitor = await currentMonitor();
  if (!monitor) return;

  const target = expanded ? EXPANDED : COLLAPSED;
  const targetX = monitor.position.x + Math.round((monitor.size.width - target.width) / 2);
  const targetY = monitor.position.y + TOP_OFFSET;

  if (target.width === lastFrame.width && target.height === lastFrame.height && targetX === lastFrame.x && targetY === lastFrame.y) return;

  lastFrame = { width: target.width, height: target.height, x: targetX, y: targetY };
  await Promise.all([
    appWindow.setSize(new PhysicalSize(target.width, target.height)),
    appWindow.setPosition(new PhysicalPosition(targetX, targetY)),
  ]);
}
