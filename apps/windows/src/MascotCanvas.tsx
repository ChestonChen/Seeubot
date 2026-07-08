import { useEffect, useRef } from "react";

export type Mood = "excited" | "idle" | "sleeping";

type Props = {
  mood: Mood;
  size?: number;
};

function moodColor(mood: Mood): string {
  if (mood === "excited") return "#39db84";
  if (mood === "idle") return "#8ea1ff";
  return "#737789";
}

function moodEnergy(mood: Mood): number {
  if (mood === "excited") return 1;
  if (mood === "idle") return 0.5;
  return 0.15;
}

function hash01(value: number): number {
  const next = Math.sin(value * 12.9898) * 43758.5453;
  return next - Math.floor(next);
}

function hump(value: number): number {
  return value <= 0 || value >= 1 ? 0 : Math.sin(value * Math.PI);
}

export default function MascotCanvas({ mood, size = 34 }: Props) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let frame = 0;
    const scale = window.devicePixelRatio || 1;
    const width = size * 1.6;
    const height = size * 1.7;
    canvas.width = Math.round(width * scale);
    canvas.height = Math.round(height * scale);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    const draw = (time: number) => {
      const t = time / 1000;
      ctx.save();
      ctx.scale(scale, scale);
      ctx.clearRect(0, 0, width, height);
      drawMascot(ctx, width, height, size, mood, t);
      ctx.restore();
      frame = requestAnimationFrame(draw);
    };

    frame = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(frame);
  }, [mood, size]);

  return <canvas className="mascotCanvas" ref={canvasRef} aria-hidden="true" />;
}

function roundedRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  const rr = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.lineTo(x + w - rr, y);
  ctx.quadraticCurveTo(x + w, y, x + w, y + rr);
  ctx.lineTo(x + w, y + h - rr);
  ctx.quadraticCurveTo(x + w, y + h, x + w - rr, y + h);
  ctx.lineTo(x + rr, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - rr);
  ctx.lineTo(x, y + rr);
  ctx.quadraticCurveTo(x, y, x + rr, y);
  ctx.closePath();
}

function drawSparkle(ctx: CanvasRenderingContext2D, x: number, y: number, r: number, color: string) {
  const k = r * 0.34;
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(x, y - r);
  ctx.quadraticCurveTo(x + k, y - k, x + r, y);
  ctx.quadraticCurveTo(x + k, y + k, x, y + r);
  ctx.quadraticCurveTo(x - k, y + k, x - r, y);
  ctx.quadraticCurveTo(x - k, y - k, x, y - r);
  ctx.closePath();
  ctx.fill();
}

function drawMascot(ctx: CanvasRenderingContext2D, width: number, height: number, s: number, mood: Mood, t: number) {
  const cx = width / 2;
  const cy = height * 0.56;
  const energy = moodEnergy(mood);
  const color = moodColor(mood);

  const slotLen = 4.2;
  const slot = Math.floor(t / slotLen);
  const sp = (t - slot * slotLen) / slotLen;
  const random = hash01(slot);
  const doHop = mood !== "sleeping" && random < 0.3;
  const doWiggle = mood !== "sleeping" && random >= 0.3 && random < 0.58;
  const hopP = doHop ? hump(Math.min(1, sp * 3)) : 0;
  const wiggleP = doWiggle ? hump(Math.min(1, sp * 2.2)) : 0;

  const bob = Math.sin(t * 1.9) * 0.02 * (0.5 + energy) * s - hopP * s * 0.16;
  const breathe = 1 + Math.sin(t * 1.9) * 0.02;
  const stretch = 1 + hopP * 0.1;
  const squashX = 1 / (1 + hopP * 0.06);
  let tilt = Math.sin(t * 0.8) * 0.05 * (0.4 + energy);
  tilt += Math.sin(sp * Math.PI * 6) * 0.16 * wiggleP;

  const headX = cx;
  const headY = cy + bob;
  const hw = s * 0.92;
  const hh = s * 0.88;
  const eyeColor = "#22263b";

  if (mood === "excited") {
    const spots: Array<[number, number, number]> = [
      [-0.62, -0.3, 0],
      [0.64, -0.12, 0.5],
      [-0.58, 0.28, 0.85],
      [0.6, 0.34, 0.3],
      [0, -0.66, 0.7],
    ];
    for (const [dx, dy, ph] of spots) {
      const tw = 0.5 + 0.5 * Math.sin(t * 3.4 + ph * 6.28);
      if (tw > 0.15) drawSparkle(ctx, cx + dx * s * 0.95, headY + dy * s * 0.95, s * 0.07 * tw, `rgba(57, 219, 132, ${0.9 * tw})`);
    }
  }

  ctx.save();
  ctx.translate(headX, headY);
  ctx.rotate(tilt);
  ctx.scale(breathe * squashX, breathe * stretch);

  const sway = Math.sin(t * 1.6 + 0.6) * s * 0.05 * (0.5 + energy);
  const tipX = sway;
  const tipY = -hh / 2 - s * 0.26 - hopP * s * 0.03;
  ctx.strokeStyle = "rgba(255,255,255,0.55)";
  ctx.lineWidth = s * 0.045;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(0, -hh / 2);
  ctx.quadraticCurveTo(sway * 0.5, -hh / 2 - s * 0.14, tipX, tipY);
  ctx.stroke();

  const pulse = 0.55 + 0.45 * Math.sin(t * (mood === "excited" ? 7 : 2.4));
  const bulbR = s * 0.075 * (1 + 0.22 * pulse * energy);
  const glow = ctx.createRadialGradient(tipX, tipY, 0, tipX, tipY, bulbR * 2.6);
  glow.addColorStop(0, color);
  glow.addColorStop(1, "rgba(255,255,255,0)");
  ctx.globalAlpha = 0.6 * pulse;
  ctx.fillStyle = glow;
  ctx.beginPath();
  ctx.arc(tipX, tipY, bulbR * 2.6, 0, Math.PI * 2);
  ctx.fill();
  ctx.globalAlpha = 1;
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(tipX, tipY, bulbR, 0, Math.PI * 2);
  ctx.fill();

  const headGradient = ctx.createLinearGradient(0, -hh / 2, 0, hh / 2);
  headGradient.addColorStop(0, "#f7f7f7");
  headGradient.addColorStop(1, "#d2d4dc");
  roundedRect(ctx, -hw / 2, -hh / 2, hw, hh, s * 0.34);
  ctx.fillStyle = headGradient;
  ctx.fill();
  ctx.strokeStyle = "rgba(255,255,255,0.9)";
  ctx.lineWidth = s * 0.02;
  ctx.stroke();

  roundedRect(ctx, -hw / 2 + s * 0.12, -hh / 2 + s * 0.07, hw - s * 0.24, s * 0.19, s * 0.1);
  ctx.fillStyle = "rgba(255,255,255,0.5)";
  ctx.fill();

  const cheekR = s * (0.07 + 0.012 * (0.5 + 0.5 * Math.sin(t * 2.6)) * energy);
  const cheekY = s * 0.15;
  for (const dx of [-s * 0.29, s * 0.29]) {
    ctx.fillStyle = `rgba(255, 140, 158, ${0.45 + 0.15 * pulse})`;
    ctx.beginPath();
    ctx.arc(dx, cheekY, cheekR, 0, Math.PI * 2);
    ctx.fill();
  }

  const lookX = (Math.sin(t * 0.9) * 0.5 + Math.sin(t * 0.37) * 0.3) * s * 0.045 * (0.4 + energy);
  const lookY = Math.sin(t * 0.6 + 1) * 0.4 * s * 0.03 * (0.4 + energy);
  const blinkCycle = t % 3.1;
  let blink = blinkCycle < 0.14 ? 1 - Math.abs(blinkCycle - 0.07) / 0.07 : 0;
  if (hash01(Math.floor(t / 3.1)) < 0.3) {
    const blink2 = blinkCycle - 0.26;
    if (blink2 > 0 && blink2 < 0.14) blink = Math.max(blink, 1 - Math.abs(blink2 - 0.07) / 0.07);
  }

  for (const dir of [-1, 1]) {
    const ecX = dir * s * 0.2 + lookX;
    const ecY = -s * 0.02 + lookY;
    if (mood === "sleeping") {
      ctx.strokeStyle = eyeColor;
      ctx.lineWidth = s * 0.035;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.arc(ecX, ecY - s * 0.02, s * 0.1, Math.PI * 0.14, Math.PI * 0.86);
      ctx.stroke();
    } else {
      const wide = mood === "excited" ? 1.12 : 1;
      const eyeW = s * 0.15 * wide;
      const eyeH = Math.max(1, s * 0.23 * wide * (1 - 0.92 * blink));
      roundedRect(ctx, ecX - eyeW / 2, ecY - eyeH / 2, eyeW, eyeH, eyeW * 0.5);
      ctx.fillStyle = eyeColor;
      ctx.fill();
      if (blink < 0.4) {
        const glint = s * 0.05;
        ctx.fillStyle = "#fff";
        ctx.beginPath();
        ctx.arc(ecX - eyeW * 0.02 + lookX * 0.25, ecY - eyeH * 0.22, glint / 2, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  const mouthY = s * 0.26;
  if (mood === "excited") {
    const chatter = 0.45 + 0.55 * Math.abs(Math.sin(t * 9));
    const mw = s * 0.24;
    const mh = s * (0.07 + 0.13 * chatter);
    roundedRect(ctx, -mw / 2, mouthY - mh / 2, mw, mh, mh * 0.5);
    ctx.fillStyle = eyeColor;
    ctx.fill();
    roundedRect(ctx, -mw * 0.25, mouthY + mh * 0.04, mw * 0.5, mh * 0.45, mh * 0.25);
    ctx.fillStyle = "#ff818d";
    ctx.fill();
  } else if (mood === "idle") {
    ctx.strokeStyle = eyeColor;
    ctx.lineWidth = s * 0.035;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.arc(0, mouthY - s * 0.07, s * 0.14, Math.PI * 0.16, Math.PI * 0.84);
    ctx.stroke();
  } else {
    ctx.strokeStyle = eyeColor;
    ctx.lineWidth = s * 0.03;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(-s * 0.06, mouthY);
    ctx.lineTo(s * 0.06, mouthY);
    ctx.stroke();
  }

  ctx.restore();

  if (mood === "sleeping") {
    const zt = (t % 2.8) / 2.8;
    for (let i = 0; i < 3; i += 1) {
      const phase = zt - i * 0.16;
      if (phase <= 0 || phase >= 1) continue;
      ctx.globalAlpha = 1 - phase;
      ctx.fillStyle = "#8ea1ff";
      ctx.font = `800 ${s * (0.13 + 0.05 * i)}px ui-rounded, system-ui`;
      ctx.fillText("z", headX + hw * 0.42 + phase * s * 0.3, headY - hh * 0.4 - phase * s * 0.42);
      ctx.globalAlpha = 1;
    }
  }
}
