import React from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { ArrowLeft, Play, Leaf, Crosshair, Repeat, Timer, Skull, Link as LinkIcon, Coins } from "lucide-react";

const MODES = [
  {
    id: "classic",
    title: "CLASSIC",
    description: "3 lives. Score as high as you can before you're out.",
    icon: <Crosshair className="w-7 h-7" />,
    gradient: "from-violet-600 to-cyan-500",
    shadow: "shadow-violet-500/30",
    border: "border-violet-500/30",
    bg: "bg-violet-500/10",
    earnsCoins: true,
  },
  {
    id: "sudden_death",
    title: "SUDDEN DEATH",
    description: "One miss and you're done. Speed ramps up fast. High risk, high reward!",
    icon: <Skull className="w-7 h-7" />,
    gradient: "from-red-600 to-rose-400",
    shadow: "shadow-red-500/30",
    border: "border-red-500/30",
    bg: "bg-red-500/10",
  },
  {
    id: "combo_frenzy",
    title: "COMBO FRENZY",
    description: "3 lives. Build massive combos for huge multipliers. Keep the chain alive!",
    icon: <LinkIcon className="w-7 h-7" />,
    gradient: "from-fuchsia-500 to-violet-400",
    shadow: "shadow-fuchsia-500/30",
    border: "border-fuchsia-500/30",
    bg: "bg-fuchsia-500/10",
  },
  {
    id: "endless",
    title: "ENDLESS",
    description: "3 lives. Speed keeps increasing forever. How long can you last?",
    icon: <Repeat className="w-7 h-7" />,
    gradient: "from-orange-500 to-pink-500",
    shadow: "shadow-orange-500/30",
    border: "border-orange-500/30",
    bg: "bg-orange-500/10",
  },
  {
    id: "timed",
    title: "TIMED",
    description: "3 lives + 60 seconds. Score as high as you can before time or lives run out!",
    icon: <Timer className="w-7 h-7" />,
    gradient: "from-rose-500 to-amber-400",
    shadow: "shadow-rose-500/30",
    border: "border-rose-500/30",
    bg: "bg-rose-500/10",
  },
  {
    id: "zen",
    title: "ZEN",
    description: "No score. No lives. Just you and the rhythm. Pure relaxation.",
    icon: <Leaf className="w-7 h-7" />,
    gradient: "from-emerald-500 to-teal-400",
    shadow: "shadow-emerald-500/30",
    border: "border-emerald-500/30",
    bg: "bg-emerald-500/10",
  },
];

export default function ModeSelect() {
  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col px-6 py-10">
      <div className="max-w-sm mx-auto w-full">
        {/* Header */}
        <div className="flex items-center gap-4 mb-8">
          <Link to={createPageUrl("Home")}>
            <motion.button whileTap={{ scale: 0.9 }} className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/60">
              <ArrowLeft className="w-5 h-5" />
            </motion.button>
          </Link>
          <div>
            <h1 className="text-2xl font-black text-white">SELECT MODE</h1>
            <p className="text-white/30 text-xs tracking-widest">Choose your playstyle</p>
          </div>
        </div>

        {/* Mode Cards */}
        <div className="flex flex-col gap-4">
          {MODES.map((mode, i) => (
            <Link key={mode.id} to={createPageUrl("Game") + `?mode=${mode.id}`}>
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: i * 0.1 }}
                whileTap={{ scale: 0.97 }}
                className={`rounded-2xl border ${mode.border} ${mode.bg} p-5 transition-all`}
              >
                <div className="flex items-center gap-4">
                  <div className={`w-14 h-14 rounded-xl bg-gradient-to-br ${mode.gradient} flex items-center justify-center text-white shadow-lg ${mode.shadow}`}>
                    {mode.icon}
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <p className="text-white font-black text-lg tracking-wide">{mode.title}</p>
                      {mode.earnsCoins && (
                        <span className="flex items-center gap-0.5 bg-amber-400/10 border border-amber-400/20 rounded-full px-1.5 py-0.5">
                          <Coins className="w-2.5 h-2.5 text-amber-400" />
                          <span className="text-amber-400 text-[9px] font-bold">COINS</span>
                        </span>
                      )}
                    </div>
                    <p className="text-white/40 text-xs leading-relaxed mt-0.5">{mode.description}</p>
                  </div>
                  <div className={`w-10 h-10 rounded-full bg-gradient-to-br ${mode.gradient} flex items-center justify-center shadow-lg ${mode.shadow}`}>
                    <Play className="w-4 h-4 text-white fill-white" />
                  </div>
                </div>
              </motion.div>
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
}