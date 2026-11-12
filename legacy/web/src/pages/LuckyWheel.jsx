import React, { useState, useEffect, useRef } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Coins, RotateCw } from "lucide-react";
import { addCoins, getCoins } from "@/components/game/coinSystem";
import { getCachedProfile, quickSave } from "@/components/game/playerService";
import { playSfx } from "@/components/game/soundEngine";

const WHEEL_PRIZES = [
  { label: "25", coins: 25, color: "#7c3aed" },
  { label: "50", coins: 50, color: "#06b6d4" },
  { label: "100", coins: 100, color: "#f59e0b" },
  { label: "10", coins: 10, color: "#64748b" },
  { label: "200", coins: 200, color: "#ec4899" },
  { label: "25", coins: 25, color: "#8b5cf6" },
  { label: "75", coins: 75, color: "#10b981" },
  { label: "500", coins: 500, color: "#ef4444" },
];

function getDayKey() {
  return new Date().toISOString().slice(0, 10);
}

export default function LuckyWheel() {
  const [spinning, setSpinning] = useState(false);
  const [result, setResult] = useState(null);
  const [hasSpunToday, setHasSpunToday] = useState(false);
  const [coins, setCoinsState] = useState(0);
  const [rotation, setRotation] = useState(0);
  const canvasRef = useRef(null);

  const segmentAngle = 360 / WHEEL_PRIZES.length;

  useEffect(() => {
    const p = getCachedProfile();
    const wheelData = p?.lucky_wheel || {};
    setHasSpunToday(wheelData.lastSpin === getDayKey());
    setCoinsState(getCoins());
    drawWheel(0);
  }, []);

  function drawWheel(angle) {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    const size = canvas.width;
    const cx = size / 2;
    const cy = size / 2;
    const r = size / 2 - 10;

    ctx.clearRect(0, 0, size, size);
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate((angle * Math.PI) / 180);

    for (let i = 0; i < WHEEL_PRIZES.length; i++) {
      const startA = (i * segmentAngle * Math.PI) / 180;
      const endA = ((i + 1) * segmentAngle * Math.PI) / 180;

      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.arc(0, 0, r, startA, endA);
      ctx.closePath();
      ctx.fillStyle = WHEEL_PRIZES[i].color;
      ctx.fill();
      ctx.strokeStyle = "rgba(0,0,0,0.3)";
      ctx.lineWidth = 2;
      ctx.stroke();

      // Text
      ctx.save();
      ctx.rotate(startA + (segmentAngle * Math.PI) / 360);
      ctx.textAlign = "center";
      ctx.fillStyle = "#fff";
      ctx.font = "bold 18px sans-serif";
      ctx.fillText("🪙" + WHEEL_PRIZES[i].label, r * 0.6, 6);
      ctx.restore();
    }

    ctx.restore();

    // Center circle
    ctx.beginPath();
    ctx.arc(cx, cy, 20, 0, Math.PI * 2);
    ctx.fillStyle = "#1e1b4b";
    ctx.fill();
    ctx.strokeStyle = "#a78bfa";
    ctx.lineWidth = 3;
    ctx.stroke();
  }

  const spin = () => {
    if (spinning || hasSpunToday) return;
    setSpinning(true);
    setResult(null);

    const prizeIndex = Math.floor(Math.random() * WHEEL_PRIZES.length);
    const prize = WHEEL_PRIZES[prizeIndex];

    // Calculate final rotation: full spins + land on prize
    const targetAngle = 360 * 5 + (360 - prizeIndex * segmentAngle - segmentAngle / 2);
    const startRotation = rotation;
    const totalRotation = targetAngle;

    let startTime = null;
    const duration = 4000;

    const animate = (timestamp) => {
      if (!startTime) startTime = timestamp;
      const elapsed = timestamp - startTime;
      const progress = Math.min(elapsed / duration, 1);

      // Ease-out cubic
      const ease = 1 - Math.pow(1 - progress, 3);
      const currentAngle = startRotation + totalRotation * ease;

      drawWheel(currentAngle);

      if (progress < 1) {
        requestAnimationFrame(animate);
      } else {
        setRotation(currentAngle % 360);
        setSpinning(false);
        setResult(prize);
        setHasSpunToday(true);
        addCoins(prize.coins);
        setCoinsState(getCoins());
        quickSave({ lucky_wheel: { lastSpin: getDayKey() } });
        playSfx("comboMilestone");
      }
    };

    playSfx("countdown");
    requestAnimationFrame(animate);
  };

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col px-6 py-10">
      <div className="max-w-sm mx-auto w-full">
        {/* Header */}
        <div className="flex items-center gap-4 mb-6">
          <Link to={createPageUrl("Home")}>
            <motion.button whileTap={{ scale: 0.9 }} className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/60">
              <ArrowLeft className="w-5 h-5" />
            </motion.button>
          </Link>
          <div className="flex-1">
            <h1 className="text-2xl font-black text-white">LUCKY WHEEL</h1>
            <p className="text-white/30 text-xs tracking-widest">Spin daily for coins!</p>
          </div>
          <div className="flex items-center gap-1.5 bg-amber-400/10 border border-amber-400/20 rounded-full px-3 py-1.5">
            <Coins className="w-4 h-4 text-amber-400" />
            <span className="text-amber-400 text-sm font-black">{coins}</span>
          </div>
        </div>

        {/* Wheel */}
        <div className="relative flex items-center justify-center mb-6">
          {/* Pointer triangle */}
          <div className="absolute top-0 left-1/2 -translate-x-1/2 z-10 w-0 h-0 border-l-[12px] border-l-transparent border-r-[12px] border-r-transparent border-t-[20px] border-t-yellow-400" />
          <canvas
            ref={canvasRef}
            width={300}
            height={300}
            className="w-[300px] h-[300px]"
          />
        </div>

        {/* Spin Button */}
        <motion.button
          whileTap={!hasSpunToday && !spinning ? { scale: 0.97 } : {}}
          onClick={spin}
          disabled={hasSpunToday || spinning}
          className={`w-full py-5 rounded-2xl text-xl font-black tracking-wide flex items-center justify-center gap-3 transition-all ${
            hasSpunToday
              ? "bg-white/5 border border-white/10 text-white/30 cursor-not-allowed"
              : spinning
              ? "bg-violet-600/50 text-white/50 cursor-wait"
              : "bg-gradient-to-r from-violet-600 to-cyan-500 text-white shadow-xl shadow-violet-500/30"
          }`}
        >
          <RotateCw className={`w-6 h-6 ${spinning ? "animate-spin" : ""}`} />
          {hasSpunToday ? "COME BACK TOMORROW" : spinning ? "SPINNING..." : "SPIN!"}
        </motion.button>

        {/* Result */}
        <AnimatePresence>
          {result && (
            <motion.div
              initial={{ opacity: 0, scale: 0.8, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0 }}
              className="mt-6 bg-amber-400/10 border border-amber-400/30 rounded-2xl p-6 text-center"
            >
              <p className="text-4xl mb-2">🎉</p>
              <p className="text-amber-400 font-black text-2xl">+{result.coins} COINS!</p>
              <p className="text-white/40 text-sm mt-1">Come back tomorrow for another spin!</p>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}