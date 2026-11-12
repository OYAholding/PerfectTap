import React, { useState, useEffect } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Coins, ScrollText, Sparkles } from "lucide-react";
import { getCoins, addCoins } from "@/components/game/coinSystem";
import { getDailyQuests, claimQuestReward } from "@/components/game/questSystem";
import { incrementQuestsCompleted } from "@/components/game/statsSystem";
import { playSfx } from "@/components/game/soundEngine";
import QuestCard from "@/components/quests/QuestCard";

export default function DailyQuests() {
  const [quests, setQuests] = useState([]);
  const [coins, setCoins] = useState(0);
  const [showCelebration, setShowCelebration] = useState(null);

  useEffect(() => {
    setCoins(getCoins());
    const data = getDailyQuests();
    setQuests(data.quests);
  }, []);

  const handleClaim = (questId) => {
    const reward = claimQuestReward(questId);
    if (!reward) return;

    if (reward.type === "coins") {
      addCoins(reward.amount);
      setCoins(getCoins());
    }
    incrementQuestsCompleted();
    playSfx("dailyReward");

    const data = getDailyQuests();
    setQuests(data.quests);

    setShowCelebration(reward);
    setTimeout(() => setShowCelebration(null), 2000);
  };

  const completedCount = quests.filter(q => q.completed).length;
  const claimedCount = quests.filter(q => q.claimed).length;

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
            <h1 className="text-2xl font-black text-white">DAILY QUESTS</h1>
            <p className="text-white/30 text-xs tracking-widest">New quests every day</p>
          </div>
          <div className="flex items-center gap-1.5 bg-amber-400/10 border border-amber-400/20 rounded-full px-3 py-1.5">
            <Coins className="w-4 h-4 text-amber-400" />
            <span className="text-amber-400 text-sm font-black">{coins}</span>
          </div>
        </div>

        {/* Progress */}
        <motion.div
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          className="flex items-center justify-center gap-3 bg-violet-500/10 border border-violet-500/20 rounded-2xl p-4 mb-6"
        >
          <ScrollText className="w-6 h-6 text-violet-400" />
          <div className="text-center">
            <p className="text-violet-300 font-black text-2xl leading-none">{claimedCount}/{quests.length}</p>
            <p className="text-violet-400/60 text-xs tracking-widest mt-0.5">QUESTS COMPLETED</p>
          </div>
          {claimedCount === quests.length && quests.length > 0 && (
            <Sparkles className="w-6 h-6 text-yellow-400" />
          )}
        </motion.div>

        {/* Quest List */}
        <div className="flex flex-col gap-3">
          {quests.map((quest, i) => (
            <QuestCard
              key={quest.id}
              quest={quest}
              onClaim={handleClaim}
              index={i}
            />
          ))}
        </div>

        <p className="text-white/20 text-center text-xs mt-6 tracking-widest">
          Quests reset at midnight
        </p>
      </div>

      {/* Claim celebration */}
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
              <p className="text-5xl mb-3">🎉</p>
              <p className="text-violet-400 font-black text-2xl">QUEST COMPLETE!</p>
              <p className="text-amber-400 text-sm font-bold mt-1">+{showCelebration.amount} Coins</p>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}