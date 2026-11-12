import React, { useState, useEffect } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Gift, Flame, CheckCircle, Lock, Star, Coins } from "lucide-react";
import { playSfx } from "@/components/game/soundEngine";
import { addCoins, getCoins } from "@/components/game/coinSystem";
import { getCachedProfile, quickSave } from "@/components/game/playerService";

const DAILY_REWARDS = [
  { day: 1, type: "coins", label: "50 Coins", icon: "🪙", coins: 50 },
  { day: 2, type: "boost", label: "1.5× Score Boost", icon: "🚀", duration: "1 game", value: 1.5 },
  { day: 3, type: "coins", label: "100 Coins", icon: "💰", coins: 100 },
  { day: 4, type: "theme", label: "Neon Theme", icon: "🌟", themeId: "neon" },
  { day: 5, type: "coins", label: "150 Coins", icon: "🪙", coins: 150 },
  { day: 6, type: "boost", label: "2× Score Boost", icon: "🔥", duration: "1 game", value: 2.0 },
  { day: 7, type: "coins", label: "300 Coins + Fire Theme", icon: "💎", coins: 300, themeId: "fire" },
];

function getDayKey() {
  return new Date().toISOString().slice(0, 10);
}

export default function DailyRewards() {
  const [streak, setStreak] = useState(0);
  const [claimedToday, setClaimedToday] = useState(false);
  const [claimedDays, setClaimedDays] = useState([]);
  const [claiming, setClaiming] = useState(false);
  const [showCelebration, setShowCelebration] = useState(false);
  const [todayReward, setTodayReward] = useState(null);

  useEffect(() => {
    const p = getCachedProfile();
    const data = p?.daily_rewards || {};
    const today = getDayKey();
    const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10);

    let currentStreak = data.streak || 0;
    let claimed = data.claimedDays || [];

    if (data.lastClaim && data.lastClaim !== today && data.lastClaim !== yesterday) {
      currentStreak = 0;
      claimed = [];
    }

    setStreak(currentStreak);
    setClaimedDays(claimed);
    setClaimedToday(data.lastClaim === today);
    setTodayReward(DAILY_REWARDS[(currentStreak) % 7]);
  }, []);

  const claimReward = () => {
    if (claimedToday || claiming) return;
    setClaiming(true);

    const p = getCachedProfile();
    const data = p?.daily_rewards || {};
    const today = getDayKey();
    const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10);

    let newStreak = data.streak || 0;
    let claimed = data.claimedDays || [];

    if (data.lastClaim === yesterday) {
      newStreak += 1;
    } else if (data.lastClaim !== today) {
      newStreak = 1;
      claimed = [];
    }

    const reward = DAILY_REWARDS[(newStreak - 1) % 7];
    claimed = [...claimed, newStreak];

    const updates = {};
    if (reward.type === "boost") {
      updates.boost = { value: reward.value, used: false };
    } else if (reward.type === "coins") {
      addCoins(reward.coins);
      if (reward.themeId) {
        const owned = [...(p?.owned_items || [])];
        if (!owned.includes(reward.themeId)) {
          owned.push(reward.themeId);
          updates.owned_items = owned;
        }
      }
    } else if (reward.type === "theme") {
      const owned = [...(p?.owned_items || [])];
      if (!owned.includes(reward.themeId)) {
        owned.push(reward.themeId);
        updates.owned_items = owned;
      }
    }

    const newData = { streak: newStreak, lastClaim: today, claimedDays: claimed };
    updates.daily_rewards = newData;
    quickSave(updates);

    setStreak(newStreak);
    setClaimedDays(claimed);
    setClaimedToday(true);
    setTodayReward(reward);
    playSfx("dailyReward");
    setShowCelebration(true);
    setClaiming(false);

    setTimeout(() => setShowCelebration(false), 2500);
  };

  const currentDayIndex = (streak) % 7;

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
          <div className="flex-1">
            <h1 className="text-2xl font-black text-white">DAILY REWARDS</h1>
            <p className="text-white/30 text-xs tracking-widest">Come back every day!</p>
          </div>
          <div className="flex items-center gap-1.5 bg-amber-400/10 border border-amber-400/20 rounded-full px-3 py-1.5">
            <Coins className="w-4 h-4 text-amber-400" />
            <span className="text-amber-400 text-sm font-black">{getCoins()}</span>
          </div>
        </div>

        {/* Streak Badge */}
        <motion.div
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          className="flex items-center justify-center gap-3 bg-orange-500/10 border border-orange-500/20 rounded-2xl p-4 mb-6"
        >
          <Flame className="w-7 h-7 text-orange-400" />
          <div className="text-center">
            <p className="text-orange-300 font-black text-3xl leading-none">{streak}</p>
            <p className="text-orange-400/60 text-xs tracking-widest mt-0.5">DAY STREAK</p>
          </div>
          <Flame className="w-7 h-7 text-orange-400" />
        </motion.div>

        {/* 7-Day Calendar Grid */}
        <div className="grid grid-cols-7 gap-1.5 mb-6">
          {DAILY_REWARDS.map((reward, i) => {
            const dayNum = i + 1;
            const isClaimed = claimedDays.includes(dayNum) || (streak > 0 && i < (streak % 7 === 0 ? 7 : streak % 7));
            const isToday = i === currentDayIndex && !claimedToday;
            const isFuture = !isClaimed && !isToday;

            return (
              <motion.div
                key={i}
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ delay: i * 0.05 }}
                className={`aspect-square rounded-xl flex flex-col items-center justify-center relative border transition-all ${
                  isClaimed
                    ? "bg-green-500/20 border-green-500/40"
                    : isToday
                    ? "bg-violet-500/20 border-violet-500/60 shadow-lg shadow-violet-500/20"
                    : "bg-white/5 border-white/10 opacity-50"
                }`}
              >
                <span className="text-lg leading-none">{reward.icon}</span>
                <span className={`text-xs font-bold mt-0.5 ${isClaimed ? "text-green-400" : isToday ? "text-violet-300" : "text-white/30"}`}>
                  D{dayNum}
                </span>
                {isClaimed && (
                  <div className="absolute -top-1 -right-1 w-4 h-4 bg-green-500 rounded-full flex items-center justify-center">
                    <CheckCircle className="w-3 h-3 text-white" />
                  </div>
                )}
                {isFuture && (
                  <div className="absolute -top-1 -right-1 w-4 h-4 bg-white/10 rounded-full flex items-center justify-center">
                    <Lock className="w-2.5 h-2.5 text-white/30" />
                  </div>
                )}
              </motion.div>
            );
          })}
        </div>

        {/* Today's Reward Card */}
        {todayReward && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3 }}
            className="bg-white/5 border border-white/10 rounded-2xl p-5 mb-6"
          >
            <p className="text-white/40 text-xs tracking-widest uppercase mb-3">Today's Reward</p>
            <div className="flex items-center gap-4">
              <div className="w-14 h-14 rounded-xl bg-violet-500/20 border border-violet-500/30 flex items-center justify-center text-3xl">
                {todayReward.icon}
              </div>
              <div>
                <p className="text-white font-bold text-lg">{todayReward.label}</p>
                <p className="text-white/40 text-xs">
                  {todayReward.type === "boost" ? `Applied to next game` : `Unlocks theme in Shop`}
                </p>
              </div>
            </div>
          </motion.div>
        )}

        {/* Claim Button */}
        <motion.button
          whileTap={!claimedToday ? { scale: 0.97 } : {}}
          onClick={claimReward}
          disabled={claimedToday}
          className={`w-full py-5 rounded-2xl text-xl font-black tracking-wide flex items-center justify-center gap-3 transition-all ${
            claimedToday
              ? "bg-white/5 border border-white/10 text-white/30 cursor-not-allowed"
              : "bg-gradient-to-r from-orange-500 to-yellow-400 text-white shadow-xl shadow-orange-500/30"
          }`}
        >
          <Gift className="w-6 h-6" />
          {claimedToday ? "CLAIMED TODAY ✓" : "CLAIM REWARD"}
        </motion.button>

        {claimedToday && (
          <p className="text-white/30 text-center text-xs mt-3 tracking-widest">Come back tomorrow for Day {(streak % 7) + 1}!</p>
        )}
      </div>

      {/* Celebration overlay */}
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
              className="bg-[#0a0a0f] border-2 border-yellow-400/60 rounded-3xl px-10 py-8 text-center shadow-2xl"
            >
              <p className="text-5xl mb-3">{todayReward?.icon}</p>
              <p className="text-yellow-400 font-black text-2xl">REWARD CLAIMED!</p>
              <p className="text-white/60 text-sm mt-1">{todayReward?.label}</p>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}