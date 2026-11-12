// PERFECT hit particle effects
import React, { useEffect, useRef } from "react";

const COLORS_PERFECT = ["#a78bfa", "#c084fc", "#818cf8", "#e879f9", "#38bdf8"];
const COLORS_GREAT = ["#22d3ee", "#06b6d4", "#67e8f9"];

export default function ParticleExplosion({ trigger, accuracy }) {
  const canvasRef = useRef(null);
  const particles = useRef([]);
  const animRef = useRef(null);

  useEffect(() => {
    if (!trigger || !canvasRef.current) return;
    if (accuracy !== "PERFECT" && accuracy !== "GREAT") return;

    const canvas = canvasRef.current;
    const ctx = canvas.getContext("2d");
    const w = canvas.width = canvas.offsetWidth;
    const h = canvas.height = canvas.offsetHeight;
    const cx = w / 2;
    const cy = h / 2;

    const colors = accuracy === "PERFECT" ? COLORS_PERFECT : COLORS_GREAT;
    const count = accuracy === "PERFECT" ? 20 : 10;

    particles.current = Array.from({ length: count }, () => ({
      x: cx,
      y: cy,
      vx: (Math.random() - 0.5) * 8,
      vy: (Math.random() - 0.5) * 8 - 2,
      r: Math.random() * 4 + 2,
      color: colors[Math.floor(Math.random() * colors.length)],
      life: 1,
      decay: 0.015 + Math.random() * 0.02,
    }));

    const animate = () => {
      ctx.clearRect(0, 0, w, h);
      let alive = false;

      for (const p of particles.current) {
        if (p.life <= 0) continue;
        alive = true;
        p.x += p.vx;
        p.y += p.vy;
        p.vy += 0.15; // gravity
        p.life -= p.decay;

        ctx.globalAlpha = p.life;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r * p.life, 0, Math.PI * 2);
        ctx.fillStyle = p.color;
        ctx.fill();
      }

      ctx.globalAlpha = 1;
      if (alive) animRef.current = requestAnimationFrame(animate);
    };

    animRef.current = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(animRef.current);
  }, [trigger, accuracy]);

  return (
    <canvas
      ref={canvasRef}
      className="absolute inset-0 pointer-events-none z-20"
      style={{ width: "100%", height: "100%" }}
    />
  );
}