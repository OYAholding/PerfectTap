import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ChevronRight, Target, Zap, Heart, Coins } from "lucide-react";

const STEPS = [
  {
    icon: <Target className="w-10 h-10 text-violet-400" />,
    title: "Tap at the Right Moment",
    desc: "A bar slides back and forth. Tap when it's in the center for a PERFECT hit!",
    emoji: "🎯",
  },
  {
    icon: <Zap className="w-10 h-10 text-cyan-400" />,
    title: "Build Combos",
    desc: "Hit PERFECT or GREAT multiple times in a row to build combos and multiply your score!",
    emoji: "⚡",
  },
  {
    icon: <Heart className="w-10 h-10 text-rose-400" />,
    title: "Don't Miss!",
    desc: "You have 3 lives. Missing the target zone costs you a life. Lose them all and it's game over.",
    emoji: "❤️",
  },
  {
    icon: <Coins className="w-10 h-10 text-amber-400" />,
    title: "Earn & Upgrade",
    desc: "Earn coins in Classic mode to buy themes, avatars, and more in the Shop!",
    emoji: "🪙",
  },
];

export default function TutorialOverlay({ onComplete }) {
  const [step, setStep] = useState(0);

  const next = () => {
    if (step < STEPS.length - 1) {
      setStep(step + 1);
    } else {
      onComplete();
    }
  };

  const current = STEPS[step];

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 bg-black/90 flex items-center justify-center z-50 px-6"
      onClick={next}
    >
      <motion.div
        key={step}
        initial={{ opacity: 0, y: 30 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -30 }}
        className="max-w-sm w-full text-center"
        onClick={(e) => e.stopPropagation()}
      >
        <motion.div
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ type: "spring", delay: 0.1 }}
          className="text-6xl mb-4"
        >
          {current.emoji}
        </motion.div>

        <div className="mb-3">{current.icon}</div>

        <h2 className="text-white font-black text-2xl mb-2">{current.title}</h2>
        <p className="text-white/50 text-sm leading-relaxed mb-8">{current.desc}</p>

        {/* Step dots */}
        <div className="flex items-center justify-center gap-2 mb-6">
          {STEPS.map((_, i) => (
            <div
              key={i}
              className={`w-2 h-2 rounded-full transition-all ${
                i === step ? "bg-violet-400 w-6" : i < step ? "bg-violet-400/50" : "bg-white/20"
              }`}
            />
          ))}
        </div>

        <motion.button
          whileTap={{ scale: 0.97 }}
          onClick={next}
          className="w-full py-4 rounded-2xl bg-gradient-to-r from-violet-600 to-cyan-500 text-white font-black text-lg tracking-wide shadow-xl shadow-violet-500/30 flex items-center justify-center gap-2"
        >
          {step < STEPS.length - 1 ? "NEXT" : "LET'S PLAY!"}
          <ChevronRight className="w-5 h-5" />
        </motion.button>

        <button
          onClick={onComplete}
          className="text-white/20 text-xs mt-4 hover:text-white/40 transition-colors"
        >
          Skip tutorial
        </button>
      </motion.div>
    </motion.div>
  );
}