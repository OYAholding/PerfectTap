import React, { memo } from "react";
import { motion } from "framer-motion";

const STYLES = {
  PERFECT: {
    text: "✨ PERFECT",
    color: "text-violet-300",
    bg: "bg-violet-500/20",
    border: "border-violet-500/40",
    glow: "0 0 20px rgba(139,92,246,0.5)",
  },
  GREAT: {
    text: "⚡ GREAT",
    color: "text-cyan-300",
    bg: "bg-cyan-500/20",
    border: "border-cyan-500/40",
    glow: "0 0 20px rgba(6,182,212,0.4)",
  },
  GOOD: {
    text: "👍 GOOD",
    color: "text-green-300",
    bg: "bg-green-500/20",
    border: "border-green-500/40",
    glow: "0 0 20px rgba(74,222,128,0.3)",
  },
  MISS: {
    text: "💀 MISS",
    color: "text-red-400",
    bg: "bg-red-500/20",
    border: "border-red-500/40",
    glow: "0 0 20px rgba(239,68,68,0.4)",
  },
};

const HitFeedback = memo(function HitFeedback({ accuracy, points }) {
  const style = STYLES[accuracy];
  if (!style) return null;

  return (
    <motion.div
      initial={{ scale: 0.5, opacity: 0, y: 10 }}
      animate={{ scale: 1, opacity: 1, y: 0 }}
      exit={{ scale: 0.8, opacity: 0, y: -10 }}
      transition={{ type: "spring", stiffness: 500, damping: 25 }}
      className={`flex items-center gap-2 ${style.bg} border ${style.border} rounded-full px-5 py-2`}
      style={{ boxShadow: style.glow }}
    >
      <span className={`text-lg font-black tracking-wider ${style.color}`}>
        {style.text}
      </span>
      {points != null && points > 0 && (
        <motion.span
          initial={{ opacity: 0, x: -5 }}
          animate={{ opacity: 1, x: 0 }}
          className="text-white/60 text-sm font-bold"
        >
          +{points}
        </motion.span>
      )}
    </motion.div>
  );
});

export default HitFeedback;