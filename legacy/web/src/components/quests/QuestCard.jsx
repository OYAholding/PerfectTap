import React from "react";
import { motion } from "framer-motion";
import { Check, Coins, Gift } from "lucide-react";

const DIFFICULTY_COLORS = {
  easy: "text-green-400 bg-green-500/10 border-green-500/20",
  medium: "text-amber-400 bg-amber-500/10 border-amber-500/20",
  hard: "text-red-400 bg-red-500/10 border-red-500/20",
};

export default function QuestCard({ quest, onClaim, index }) {
  const progress = Math.min(quest.progress, quest.target);
  const pct = Math.round((progress / quest.target) * 100);
  const diffColor = DIFFICULTY_COLORS[quest.difficulty] || DIFFICULTY_COLORS.easy;

  return (
    <motion.div
      initial={{ opacity: 0, y: 15 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: index * 0.08 }}
      className={`rounded-2xl border p-4 ${
        quest.claimed
          ? "bg-white/2 border-white/5 opacity-50"
          : quest.completed
          ? "bg-violet-500/5 border-violet-500/30"
          : "bg-white/5 border-white/10"
      }`}
    >
      <div className="flex items-start gap-3">
        <div className="text-2xl mt-0.5">{quest.icon}</div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-0.5">
            <p className={`font-bold text-sm ${quest.claimed ? "text-white/30" : "text-white"}`}>
              {quest.title}
            </p>
            <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded-full border ${diffColor}`}>
              {quest.difficulty.toUpperCase()}
            </span>
          </div>
          <p className="text-white/30 text-xs mb-2">{quest.description}</p>

          {/* Progress bar */}
          <div className="flex items-center gap-2">
            <div className="flex-1 h-1.5 rounded-full bg-white/10 overflow-hidden">
              <motion.div
                initial={{ width: 0 }}
                animate={{ width: `${pct}%` }}
                transition={{ duration: 0.5, delay: index * 0.08 + 0.2 }}
                className={`h-full rounded-full ${quest.completed ? "bg-violet-500" : "bg-white/30"}`}
              />
            </div>
            <span className="text-white/30 text-[10px] font-bold tabular-nums whitespace-nowrap">
              {progress}/{quest.target}
            </span>
          </div>
        </div>

        {/* Reward / Claim */}
        <div className="flex-shrink-0 ml-1">
          {quest.claimed ? (
            <div className="w-8 h-8 rounded-full bg-green-500/20 flex items-center justify-center">
              <Check className="w-4 h-4 text-green-400" />
            </div>
          ) : quest.completed ? (
            <motion.button
              whileTap={{ scale: 0.9 }}
              onClick={() => onClaim(quest.id)}
              className="px-3 py-1.5 rounded-xl bg-gradient-to-r from-violet-500 to-cyan-400 text-white text-xs font-bold shadow-lg"
            >
              <Gift className="w-3.5 h-3.5 inline mr-1" />
              CLAIM
            </motion.button>
          ) : (
            <div className="flex items-center gap-1 bg-amber-400/10 border border-amber-400/20 rounded-full px-2 py-1">
              <Coins className="w-3 h-3 text-amber-400" />
              <span className="text-amber-400 text-[10px] font-bold">+{quest.reward.amount}</span>
            </div>
          )}
        </div>
      </div>
    </motion.div>
  );
}