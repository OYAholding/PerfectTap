import React, { useState, useEffect } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Coins, Crown, Zap, Calendar, ChevronRight } from "lucide-react";
import { getCoins, spendCoins } from "@/components/game/coinSystem";
import {
  CURRENT_SEASON,
  SEASON_REWARDS,
  getSeasonData,
  initSeason,
  claimFreeReward,
  claimPremiumReward,
  purchasePremiumPass,
  getSeasonDaysLeft,
} from "@/components/game/seasonSystem";
import SeasonTierCard from "@/components/season/SeasonTierCard";
import { playSfx } from "@/components/game/soundEngine";

const PREMIUM_COST = 2000;

export default function SeasonPass() {
  const [data, setData] = useState(null);
  const [coins, setCoinsState] = useState(0);
  const [showCelebration, setShowCelebration] = useState(null);
  const [showPurchaseConfirm, setShowPurchaseConfirm] = useState(false);

  useEffect(() => {
    initSeason();
    setData(getSeasonData());
    setCoinsState(getCoins());
  }, []);

  if (!data) return null;

  const daysLeft = getSeasonDaysLeft();
  const tierProgress = data.tier < CURRENT_SEASON.maxTier
    ? data.seasonXP / CURRENT_SEASON.xpPerTier
    : 1;

  const handleClaimFree = (tierNum) => {
    const reward = claimFreeReward(tierNum);
    if (reward) {
      playSfx("dailyReward");
      setData(getSeasonData());
      setCoinsState(getCoins());
      setShowCelebration(reward);
      setTimeout(() => setShowCelebration(null), 2000);
    }
  };

  const handleClaimPremium = (tierNum) => {
    const reward = claimPremiumReward(tierNum);
    if (reward) {
      playSfx("comboMilestone");
      setData(getSeasonData());
      setCoinsState(getCoins());
      setShowCelebration(reward);
      setTimeout(() => setShowCelebration(null), 2000);
    }
  };

  const handlePurchasePremium = () => {
    if (coins < PREMIUM_COST) return;
    const spent = spendCoins(PREMIUM_COST);
    if (!spent) return;
    purchasePremiumPass();
    setData(getSeasonData());
    setCoinsState(getCoins());
    setShowPurchaseConfirm(false);
    playSfx("comboMilestone");
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
            <h1 className="text-2xl font-black text-white">SEASON PASS</h1>
            <p className="text-white/30 text-xs tracking-widest">{CURRENT_SEASON.name}</p>
          </div>
          <div className="flex items-center gap-1.5 bg-amber-400/10 border border-amber-400/20 rounded-full px-3 py-1.5">
            <Coins className="w-4 h-4 text-amber-400" />
            <span className="text-amber-400 text-sm font-black">{coins}</span>
          </div>
        </div>

        {/* Season Info Bar */}
        <div className="flex items-center gap-3 mb-4">
          <div className="flex items-center gap-1.5 bg-violet-500/10 border border-violet-500/20 rounded-xl px-3 py-2">
            <Zap className="w-4 h-4 text-violet-400" />
            <span className="text-violet-300 text-sm font-black">Tier {data.tier}/{CURRENT_SEASON.maxTier}</span>
          </div>
          <div className="flex items-center gap-1.5 bg-cyan-500/10 border border-cyan-500/20 rounded-xl px-3 py-2">
            <Calendar className="w-4 h-4 text-cyan-400" />
            <span className="text-cyan-300 text-sm font-bold">{daysLeft}d left</span>
          </div>
          {data.isPremium && (
            <div className="flex items-center gap-1.5 bg-amber-500/10 border border-amber-500/20 rounded-xl px-3 py-2">
              <Crown className="w-4 h-4 text-amber-400" />
              <span className="text-amber-300 text-xs font-bold">PREMIUM</span>
            </div>
          )}
        </div>

        {/* Tier Progress */}
        {data.tier < CURRENT_SEASON.maxTier && (
          <div className="mb-6">
            <div className="flex items-center justify-between mb-1.5">
              <span className="text-white/40 text-xs font-bold">Tier {data.tier}</span>
              <span className="text-white/40 text-xs font-bold">Tier {data.tier + 1}</span>
            </div>
            <div className="h-3 bg-white/5 rounded-full overflow-hidden border border-white/10">
              <motion.div
                initial={{ width: 0 }}
                animate={{ width: `${tierProgress * 100}%` }}
                transition={{ duration: 0.5 }}
                className="h-full bg-gradient-to-r from-violet-500 to-cyan-400 rounded-full"
              />
            </div>
            <p className="text-white/20 text-[10px] text-center mt-1">{data.seasonXP} / {CURRENT_SEASON.xpPerTier} Season XP</p>
          </div>
        )}

        {/* Premium Purchase Banner */}
        {!data.isPremium && (
          <motion.button
            whileTap={{ scale: 0.97 }}
            onClick={() => setShowPurchaseConfirm(true)}
            className="w-full mb-6 p-4 rounded-2xl bg-gradient-to-r from-amber-500/20 to-orange-500/20 border border-amber-500/30 flex items-center gap-3"
          >
            <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-amber-400 to-orange-500 flex items-center justify-center shadow-lg">
              <Crown className="w-6 h-6 text-white" />
            </div>
            <div className="flex-1 text-left">
              <p className="text-amber-300 font-black text-sm">UPGRADE TO PREMIUM</p>
              <p className="text-white/40 text-xs">Unlock exclusive rewards & themes</p>
            </div>
            <div className="flex items-center gap-1">
              <Coins className="w-3.5 h-3.5 text-amber-400" />
              <span className="text-amber-400 font-bold text-sm">{PREMIUM_COST}</span>
            </div>
            <ChevronRight className="w-4 h-4 text-amber-400/50" />
          </motion.button>
        )}

        {/* Reward Track */}
        <div className="space-y-3">
          {SEASON_REWARDS.map((tierData, i) => {
            const isUnlocked = data.tier >= tierData.tier;
            const isCurrentTier = data.tier === tierData.tier - 1;

            return (
              <div key={tierData.tier}>
                {/* Tier number header */}
                <div className="flex items-center gap-2 mb-1.5">
                  <div className={`w-7 h-7 rounded-lg flex items-center justify-center text-xs font-black ${
                    isUnlocked
                      ? "bg-gradient-to-br from-violet-500 to-cyan-400 text-white"
                      : isCurrentTier
                      ? "bg-violet-500/20 border border-violet-500/40 text-violet-300"
                      : "bg-white/5 border border-white/10 text-white/30"
                  }`}>
                    {tierData.tier}
                  </div>
                  {isCurrentTier && (
                    <span className="text-violet-400 text-[10px] font-bold tracking-widest animate-pulse">← YOU ARE HERE</span>
                  )}
                  {tierData.tier % 5 === 0 && isUnlocked && (
                    <span className="text-amber-400 text-[10px] font-bold">★ MILESTONE</span>
                  )}
                </div>

                {/* Two-track row */}
                <div className="grid grid-cols-2 gap-2">
                  <SeasonTierCard
                    tier={tierData.tier}
                    reward={tierData.free}
                    track="free"
                    isUnlocked={isUnlocked}
                    isClaimed={data.claimedFree.includes(tierData.tier)}
                    isPremium={true}
                    onClaim={() => handleClaimFree(tierData.tier)}
                    index={i}
                  />
                  <SeasonTierCard
                    tier={tierData.tier}
                    reward={tierData.premium}
                    track="premium"
                    isUnlocked={isUnlocked}
                    isClaimed={data.claimedPremium.includes(tierData.tier)}
                    isPremium={data.isPremium}
                    onClaim={() => handleClaimPremium(tierData.tier)}
                    index={i}
                  />
                </div>
              </div>
            );
          })}
        </div>

        {/* Track Labels */}
        <div className="grid grid-cols-2 gap-2 mt-4 mb-8">
          <div className="text-center">
            <span className="text-white/30 text-[10px] font-bold tracking-widest">FREE TRACK</span>
          </div>
          <div className="text-center">
            <span className="text-amber-400/50 text-[10px] font-bold tracking-widest">PREMIUM TRACK</span>
          </div>
        </div>
      </div>

      {/* Purchase Confirmation Modal */}
      <AnimatePresence>
        {showPurchaseConfirm && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/80 flex items-center justify-center z-50 px-6"
            onClick={() => setShowPurchaseConfirm(false)}
          >
            <motion.div
              initial={{ scale: 0.9, y: 20 }}
              animate={{ scale: 1, y: 0 }}
              exit={{ scale: 0.9, opacity: 0 }}
              onClick={(e) => e.stopPropagation()}
              className="bg-[#0a0a0f] border border-amber-500/30 rounded-3xl p-6 max-w-sm w-full"
            >
              <div className="text-center mb-4">
                <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-amber-400 to-orange-500 flex items-center justify-center mx-auto mb-3">
                  <Crown className="w-8 h-8 text-white" />
                </div>
                <h2 className="text-white font-black text-xl">Premium Pass</h2>
                <p className="text-white/40 text-sm mt-1">Unlock exclusive themes, avatars, and bonus coins for this season!</p>
              </div>

              <div className="flex items-center justify-center gap-1.5 mb-4">
                <Coins className="w-5 h-5 text-amber-400" />
                <span className="text-amber-400 font-black text-2xl">{PREMIUM_COST}</span>
                <span className="text-white/30 text-sm">coins</span>
              </div>

              {coins < PREMIUM_COST ? (
                <p className="text-red-400/70 text-center text-sm mb-4">Not enough coins! You need {PREMIUM_COST - coins} more.</p>
              ) : null}

              <div className="flex gap-3">
                <button
                  onClick={() => setShowPurchaseConfirm(false)}
                  className="flex-1 py-3 rounded-xl bg-white/5 border border-white/10 text-white/50 font-bold text-sm"
                >
                  CANCEL
                </button>
                <motion.button
                  whileTap={coins >= PREMIUM_COST ? { scale: 0.97 } : {}}
                  onClick={handlePurchasePremium}
                  disabled={coins < PREMIUM_COST}
                  className={`flex-1 py-3 rounded-xl font-bold text-sm ${
                    coins >= PREMIUM_COST
                      ? "bg-gradient-to-r from-amber-500 to-orange-500 text-white shadow-lg"
                      : "bg-white/5 text-white/20 cursor-not-allowed"
                  }`}
                >
                  BUY NOW
                </motion.button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Claim Celebration */}
      <AnimatePresence>
        {showCelebration && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 flex items-center justify-center z-50 pointer-events-none"
          >
            <motion.div
              initial={{ scale: 0.5, y: 40 }}
              animate={{ scale: 1, y: 0 }}
              exit={{ scale: 0.8, opacity: 0 }}
              className="bg-[#0a0a0f] border-2 border-violet-400/60 rounded-3xl px-10 py-8 text-center shadow-2xl"
            >
              <p className="text-5xl mb-3">{showCelebration.icon}</p>
              <p className="text-violet-400 font-black text-xl">REWARD CLAIMED!</p>
              <p className="text-white/50 text-sm mt-1">{showCelebration.label}</p>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}