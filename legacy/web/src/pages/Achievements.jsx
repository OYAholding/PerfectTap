import React, { useState, useEffect } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { ArrowLeft, Lock, CheckCircle, Coins } from "lucide-react";
import { ACHIEVEMENTS, getUnlockedAchievements, getAchievementProgress } from "@/components/game/achievementSystem";

export default function Achievements() {
  const [unlocked, setUnlocked] = useState([]);
  const [progress, setProgress] = useState({ unlocked: 0, total: 0 });

  useEffect(() => {
    setUnlocked(getUnlockedAchievements());
    setProgress(getAchievementProgress());
  }, []);

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
            <h1 className="text-2xl font-black text-white">ACHIEVEMENTS</h1>
            <p className="text-white/30 text-xs tracking-widest">{progress.unlocked} / {progress.total} unlocked</p>
          </div>
        </div>

        {/* Progress Bar */}
        <div className="mb-6">
          <div className="h-3 bg-white/5 rounded-full overflow-hidden border border-white/10">
            <motion.div
              initial={{ width: 0 }}
              animate={{ width: `${progress.total > 0 ? (progress.unlocked / progress.total) * 100 : 0}%` }}
              transition={{ duration: 0.5 }}
              className="h-full bg-gradient-to-r from-violet-500 to-cyan-400 rounded-full"
            />
          </div>
        </div>

        {/* Achievement List */}
        <div className="space-y-3">
          {ACHIEVEMENTS.map((ach, i) => {
            const isUnlocked = unlocked.includes(ach.id);
            return (
              <motion.div
                key={ach.id}
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: i * 0.03 }}
                className={`flex items-center gap-4 p-4 rounded-2xl border transition-all ${
                  isUnlocked
                    ? "bg-violet-500/10 border-violet-500/30"
                    : "bg-white/5 border-white/10 opacity-60"
                }`}
              >
                <div className={`w-12 h-12 rounded-xl flex items-center justify-center text-2xl ${
                  isUnlocked ? "bg-violet-500/20" : "bg-white/5"
                }`}>
                  {isUnlocked ? ach.icon : <Lock className="w-5 h-5 text-white/20" />}
                </div>
                <div className="flex-1 min-w-0">
                  <p className={`font-bold text-sm ${isUnlocked ? "text-white" : "text-white/40"}`}>
                    {ach.title}
                  </p>
                  <p className="text-white/30 text-xs">{ach.desc}</p>
                </div>
                <div className="flex items-center gap-1 shrink-0">
                  {isUnlocked ? (
                    <CheckCircle className="w-5 h-5 text-green-400" />
                  ) : (
                    <div className="flex items-center gap-1 bg-amber-400/10 rounded-full px-2 py-1">
                      <Coins className="w-3 h-3 text-amber-400" />
                      <span className="text-amber-400 text-xs font-bold">{ach.reward}</span>
                    </div>
                  )}
                </div>
              </motion.div>
            );
          })}
        </div>
      </div>
    </div>
  );
}