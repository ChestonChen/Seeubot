import { appWindow, currentMonitor, PhysicalPosition, PhysicalSize } from "@tauri-apps/api/window";

const COLLAPSED = { width: 244, height: 46 };
const EXPANDED = { width: 384, height: 540 };
const TOP_OFFSET = 18;
const DURATION_MS = 280;

let frameAnimation = 0;
let lastFrame = { width: 0, height: 0, x: 0, y: 0 };

function easeOutCubic(value: number): number {
  return 1 - Math.pow(1 - value, 3);
}

export async function setIslandFrame(expanded: boolean): Promise<void> {
  const monitor = await currentMonitor();
  if (!monitor) return;

  const target = expanded ? EXPANDED : COLLAPSED;
  const startSize = await appWindow.outerSize();
  const startPosition = await appWindow.outerPosition();
  const targetX = monitor.position.x + Math.round((monitor.size.width - target.width) / 2);
  const targetY = monitor.position.y + TOP_OFFSET;
  const start = performance.now();
  const token = ++frameAnimation;

  const step = async (now: number) => {
    if (token !== frameAnimation) return;
    const progress = Math.min(1, (now - start) / DURATION_MS);
    const eased = easeOutCubic(progress);
    const width = Math.round(startSize.width + (target.width - startSize.width) * eased);
    const height = Math.round(startSize.height + (target.height - startSize.height) * eased);
    const x = Math.round(startPosition.x + (targetX - startPosition.x) * eased);
    const y = Math.round(startPosition.y + (targetY - startPosition.y) * eased);

    if (width !== lastFrame.width || height !== lastFrame.height || x !== lastFrame.x || y !== lastFrame.y) {
      lastFrame = { width, height, x, y };
      await Promise.all([
        appWindow.setSize(new PhysicalSize(width, height)),
        appWindow.setPosition(new PhysicalPosition(x, y)),
      ]);
    }

    if (progress < 1) {
      requestAnimationFrame(step);
    }
  };

  requestAnimationFrame(step);
}
