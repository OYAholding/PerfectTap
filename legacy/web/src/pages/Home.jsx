import React, { useEffect, useState } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { Play, Trophy, Settings, ShoppingBag, Gift, Swords, Users, Coins, User, ScrollText, UserPlus, Award, Star, Disc, Crown } from "lucide-react";
import { loadProfile, getCachedProfile, hasUsername } from "@/components/game/playerService";
import { getLevelProgress } from "@/components/game/xpSystem";
import { AnimatePresence } from "framer-motion";
import TutorialOverlay from "@/components/game/TutorialOverlay";

export default function Home() {
  // Show cached data INSTANTLY — no waiting for network
  const cached = getCachedProfile();
  const [bestScore, setBestScore] = useState(cached?.best_classic || 0);
  const [coins, setCoins] = useState(cached?.coins || 0);
  const [username, setUsernameState] = useState(cached?.username || "");
  const [ready, setReady] = useState(!!cached?.username);
  const [level, setLevel] = useState(cached?.level || 1);
  const [showTutorial, setShowTutorial] = useState(false);

  useEffect(() => {
    // If we already have cached data with a username, show immediately
    // then refresh from server in background
    if (cached?.username) {
      loadProfile().then(() => {
        const p = getCachedProfile();
        if (p) {
          setBestScore(p.best_classic || 0);
          setCoins(p.coins || 0);
          setUsernameState(p.username || "");
          setLevel(p.level || 1);
        }
      });
      return;
    }
    // First time / no cache — must wait
    loadProfile().then(() => {
      if (!hasUsername()) {
        window.location.href = createPageUrl("SetUsername") + "?redirect=Home";
        return;
      }
      const p = getCachedProfile();
      if (p) {
        setBestScore(p.best_classic || 0);
        setCoins(p.coins || 0);
        setUsernameState(p.username || "");
        setLevel(p.level || 1);
        // Show tutorial for brand new players
        if (!p.stats?.totalGames && !localStorage.getItem("perfecttap_tutorial_done")) {
          setShowTutorial(true);
        }
      }
      setReady(true);
    });
  }, []);

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col items-center justify-center px-6 relative overflow-hidden">
      {/* Background glow — uses blur-2xl instead of blur-3xl for mobile perf */}
      <div className="absolute inset-0 pointer-events-none">
        <div className="absolute top-1/4 left-1/2 -translate-x-1/2 w-96 h-96 bg-violet-600/10 rounded-full blur-2xl" />
        <div className="absolute bottom-1/4 left-1/2 -translate-x-1/2 w-64 h-64 bg-cyan-500/10 rounded-full blur-2xl" />
      </div>

      <div className="relative z-10 flex flex-col items-center w-full max-w-sm">
        {/* Logo */}
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.3 }}
          className="mb-2"
        >
          <div className="w-20 h-20 rounded-2xl bg-gradient-to-br from-violet-500 to-cyan-400 flex items-center justify-center shadow-lg shadow-violet-500/30 mb-4 mx-auto">
            <span className="text-3xl">🎯</span>
          </div>
          <h1 className="text-5xl font-black text-white tracking-tight text-center">
            PERFECT
          </h1>
          <h1 className="text-5xl font-black bg-gradient-to-r from-violet-400 to-cyan-400 bg-clip-text text-transparent tracking-tight text-center">
            TAP
          </h1>
          {username && (
            <p className="text-white/40 text-sm font-medium mt-2 text-center">👋 {username} • Lv.{level}</p>
          )}
        </motion.div>

        {/* Stats Badges */}
        <motion.div
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.1, duration: 0.2 }}
          className="flex items-center gap-3 mb-8"
        >
          {bestScore > 0 && (
            <div className="flex items-center gap-1.5 bg-white/5 border border-white/10 rounded-full px-3 py-1.5">
              <Trophy className="w-3.5 h-3.5 text-yellow-400" />
              <span className="text-white/70 text-sm font-medium">Best: <span className="text-white font-bold">{bestScore}</span></span>
            </div>
          )}
          <div className="flex items-center gap-1.5 bg-amber-400/10 border border-amber-400/20 rounded-full px-3 py-1.5">
            <Coins className="w-3.5 h-3.5 text-amber-400" />
            <span className="text-amber-400 text-sm font-bold">{coins}</span>
          </div>
        </motion.div>

        {/* Daily Reward + Challenge + Duel + Friends Buttons */}
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.12, duration: 0.2 }}
          className="grid grid-cols-5 gap-1.5 w-full mb-4"
        >
          <Link to={createPageUrl("DailyRewards")}>
            <motion.button
              whileTap={{ scale: 0.95 }}
              className="w-full py-3 rounded-xl bg-orange-500/10 border border-orange-500/30 text-orange-300 hover:bg-orange-500/20 transition-all flex flex-col items-center gap-1"
            >
              <Gift className="w-4 h-4" />
              <span className="text-[9px] font-bold">DAILY</span>
            </motion.button>
          </Link>
          <Link to={createPageUrl("LuckyWheel")}>
            <motion.button
              whileTap={{ scale: 0.95 }}
              className="w-full py-3 rounded-xl bg-yellow-500/10 border border-yellow-500/30 text-yellow-300 hover:bg-yellow-500/20 transition-all flex flex-col items-center gap-1"
            >
              <Disc className="w-4 h-4" />
              <span className="text-[9px] font-bold">WHEEL</span>
            </motion.button>
          </Link>
          <Link to={createPageUrl("DuelLobby")}>
            <motion.button
              whileTap={{ scale: 0.95 }}
              className="w-full py-3 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-300 hover:bg-rose-500/20 transition-all flex flex-col items-center gap-1"
            >
              <Swords className="w-4 h-4" />
              <span className="text-[9px] font-bold">DUEL</span>
            </motion.button>
          </Link>
          <Link to={createPageUrl("Friends")}>
            <motion.button
              whileTap={{ scale: 0.95 }}
              className="w-full py-3 rounded-xl bg-blue-500/10 border border-blue-500/30 text-blue-300 hover:bg-blue-500/20 transition-all flex flex-col items-center gap-1"
            >
              <UserPlus className="w-4 h-4" />
              <span className="text-[9px] font-bold">FRIENDS</span>
            </motion.button>
          </Link>
          <Link to={createPageUrl("Challenges")}>
            <motion.button
              whileTap={{ scale: 0.95 }}
              className="w-full py-3 rounded-xl bg-cyan-500/10 border border-cyan-500/30 text-cyan-300 hover:bg-cyan-500/20 transition-all flex flex-col items-center gap-1"
            >
              <Users className="w-4 h-4" />
              <span className="text-[9px] font-bold">CHALLENGE</span>
            </motion.button>
          </Link>
        </motion.div>

        {/* Play Button */}
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.15, duration: 0.2 }}
          className="w-full mb-4"
        >
          <Link to={createPageUrl("ModeSelect")}>
            <motion.button
              whileTap={{ scale: 0.97 }}
              className="w-full py-5 rounded-2xl bg-gradient-to-r from-violet-600 to-cyan-500 text-white text-xl font-black tracking-wide shadow-xl shadow-violet-500/30 flex items-center justify-center gap-3"
            >
              <Play className="w-6 h-6 fill-white" />
              PLAY
            </motion.button>
          </Link>
        </motion.div>

        {/* Secondary Buttons */}
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.18, duration: 0.2 }}
          className="grid grid-cols-2 gap-2 w-full mb-3"
        >
          <Link to={createPageUrl("DailyQuests")}>
            <motion.button
              whileTap={{ scale: 0.95 }}
              className="w-full py-4 rounded-xl bg-violet-500/10 border border-violet-500/30 text-violet-300 hover:bg-violet-500/20 transition-all flex flex-col items-center gap-1.5"
            >
              <ScrollText className="w-5 h-5" />
              <span className="text-xs font-bold">QUESTS</span>
            </motion.button>
          </Link>
          <Link to={createPageUrl("Achievements")}>
            <motion.button
              whileTap={{ scale: 0.95 }}
              className="w-full py-4 rounded-xl bg-amber-500/10 border border-amber-500/30 text-amber-300 hover:bg-amber-500/20 transition-all flex flex-col items-center gap-1.5"
            >
              <Award className="w-5 h-5" />
              <span className="text-xs font-bold">ACHIEVE</span>
            </motion.button>
          </Link>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.2 }}
          className="grid grid-cols-2 gap-2 w-full"
        >
          <Link to={createPageUrl("SeasonPass")}>
            <motion.button
              whileTap={{ scale: 0.95 }}
              className="w-full py-4 rounded-xl bg-amber-500/10 border border-amber-500/30 text-amber-300 hover:bg-amber-500/20 transition-all flex flex-col items-center gap-1.5"
            >
              <Crown className="w-5 h-5" />
              <span className="text-[10px] font-bold">SEASON</span>
            </motion.button>
          </Link>
          <Link to={createPageUrl("GameSettings")}>
            <motion.button
              whileTap={{ scale: 0.95 }}
              className="w-full py-4 rounded-xl bg-white/5 border border-white/10 text-white/70 hover:text-white hover:bg-white/10 transition-all flex flex-col items-center gap-1.5"
            >
              <Settings className="w-5 h-5" />
              <span className="text-[10px] font-bold">SETTINGS</span>
            </motion.button>
          </Link>
        </motion.div>

        {/* Tagline */}
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.25, duration: 0.2 }}
          className="text-white/30 text-xs mt-8 tracking-widest uppercase"
        >
          Test your precision
        </motion.p>
      </div>

      {/* Tutorial for first-time players */}
      <AnimatePresence>
        {showTutorial && (
          <TutorialOverlay onComplete={() => {
            setShowTutorial(false);
            localStorage.setItem("perfecttap_tutorial_done", "1");
          }} />
        )}
      </AnimatePresence>
    </div>
  );
}