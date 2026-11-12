import React from "react";
import { motion } from "framer-motion";
import { Lock, Check, Gift } from "lucide-react";

export default function SeasonTierCard({ tier, reward, track, isUnlocked, isClaimed, isPremium, onClaim, index }) {
  const canClaim = isUnlocked && !isClaimed && reward;
  const isLocked = !isUnlocked && reward;
  const isPremiumLocked = track === "premium" && !isPremium && reward;

  if (!reward) return (
    <div className="h-16 flex items-center justify-center">
      <div className="w-8 h-8 rounded-lg bg-white/5 border border-white/5 flex items-center justify-center">
        <span className="text-white/10 text-xs">—</span>
      </div>
    </div>
  );

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ delay: index * 0.02 }}
      className={`relative p-3 rounded-xl border transition-all ${
        isClaimed
          ? "bg-green-500/10 border-green-500/30"
          : canClaim && !isPremiumLocked
          ? "bg-violet-500/15 border-violet-500/40 shadow-lg shadow-violet-500/10"
          : isLocked || isPremiumLocked
          ? "bg-white/3 border-white/5 opacity-50"
          : "bg-white/5 border-white/10"
      }`}
    >
      <div className="flex flex-col items-center gap-1.5">
        <span className="text-xl">{reward.icon}</span>
        <p className={`text-[10px] font-bold text-center leading-tight ${
          isClaimed ? "text-green-300" : canClaim ? "text-white" : "text-white/40"
        }`}>
          {reward.label}
        </p>
        {isClaimed ? (
          <Check className="w-3.5 h-3.5 text-green-400" />
        ) : canClaim && !isPremiumLocked ? (
          <motion.button
            whileTap={{ scale: 0.9 }}
            onClick={onClaim}
            className="px-2.5 py-1 rounded-lg bg-violet-500 text-white text-[10px] font-bold"
          >
            CLAIM
          </motion.button>
        ) : isPremiumLocked ? (
          <Lock className="w-3 h-3 text-amber-400/50" />
        ) : (
          <Lock className="w-3 h-3 text-white/20" />
        )}
      </div>
    </motion.div>
  );
}