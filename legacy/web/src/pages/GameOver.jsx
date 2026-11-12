import React, { useEffect, useState } from "react";
import { createPageUrl } from "@/utils";
import { Link, useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { RotateCcw, Home, Trophy, Zap, Coins } from "lucide-react";
import ShareButtons from "@/components/game/ShareButtons";
import { getCoins } from "@/components/game/coinSystem";
import { getCachedProfile } from "@/components/game/playerService";
import { getLevelProgress } from "@/components/game/xpSystem";
import { Star, Award } from "lucide-react";

export default function GameOver() {
  const [score, setScore] = useState(0);
  const [bestScore, setBestScore] = useState(0);
  const [combo, setCombo] = useState(0);
  const [isNewBest, setIsNewBest] = useState(false);
  const [coinsEarned, setCoinsEarned] = useState(0);
  const [xpEarned, setXpEarned] = useState(0);
  const [leveledUp, setLeveledUp] = useState(null);
  const [newAchievements, setNewAchievements] = useState([]);
  const [levelProgress, setLevelProgress] = useState({ level: 1, progress: 0 });
  const navigate = useNavigate();

  const urlParams = new URLSearchParams(window.location.search);
  const mode = urlParams.get("mode") || "classic";
  const isEndless = mode === "endless";
  const isTimed = mode === "timed";
  const isSuddenDeath = mode === "sudden_death";
  const isComboFrenzy = mode === "combo_frenzy";

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const s = parseInt(params.get("score") || "0");
    const c = parseInt(params.get("combo") || "0");
    setScore(s);
    setCombo(c);

    const p = getCachedProfile();
    const best = isSuddenDeath ? (p?.best_sudden || 0) : isComboFrenzy ? (p?.best_combofrenzy || 0) : isTimed ? (p?.best_timed || 0) : isEndless ? (p?.best_endless || 0) : (p?.best_classic || 0);
    setBestScore(best);
    if (s >= best && s > 0) setIsNewBest(true);

    const earned = parseInt(localStorage.getItem("perfecttap_last_coins_earned") || "0");
    setCoinsEarned(earned);
    localStorage.removeItem("perfecttap_last_coins_earned");

    const xp = parseInt(localStorage.getItem("perfecttap_last_xp_earned") || "0");
    setXpEarned(xp);
    localStorage.removeItem("perfecttap_last_xp_earned");

    const levelUp = localStorage.getItem("perfecttap_leveled_up");
    if (levelUp) {
      setLeveledUp(parseInt(levelUp));
      localStorage.removeItem("perfecttap_leveled_up");
    }

    const achStr = localStorage.getItem("perfecttap_new_achievements");
    if (achStr) {
      setNewAchievements(JSON.parse(achStr));
      localStorage.removeItem("perfecttap_new_achievements");
    }

    setLevelProgress(getLevelProgress());
  }, []);

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col items-center justify-center px-6 relative overflow-hidden">
      <div className="absolute inset-0 pointer-events-none">
        <div className="absolute top-1/3 left-1/2 -translate-x-1/2 w-72 h-72 bg-violet-600/10 rounded-full blur-3xl" />
      </div>

      <div className="relative z-10 flex flex-col items-center w-full max-w-sm">
        {/* Title */}
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          className="mb-8 text-center"
        >
          <p className="text-white/40 text-sm tracking-widest uppercase mb-1">
            {isSuddenDeath ? "Dead." : isComboFrenzy ? "Frenzy Over!" : isTimed ? "Time's Up!" : isEndless ? "Endless Run Over" : "Game Over"}
          </p>
          {isNewBest && (
            <motion.div
              initial={{ scale: 0 }}
              animate={{ scale: 1 }}
              transition={{ delay: 0.5, type: "spring" }}
              className="inline-flex items-center gap-1.5 bg-yellow-400/10 border border-yellow-400/30 text-yellow-400 text-xs font-bold px-3 py-1 rounded-full mt-1"
            >
              <Trophy className="w-3 h-3" /> NEW BEST!
            </motion.div>
          )}
        </motion.div>

        {/* Score Card */}
        <motion.div
          initial={{ opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.1 }}
          className="w-full bg-white/5 border border-white/10 rounded-3xl p-8 mb-6"
        >
          <div className="text-center mb-6">
            <p className="text-white/40 text-xs tracking-widest uppercase mb-1">Your Score</p>
            <motion.p
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.3 }}
              className="text-7xl font-black bg-gradient-to-r from-violet-400 to-cyan-400 bg-clip-text text-transparent"
            >
              {score}
            </motion.p>
          </div>

          <div className={`grid ${mode === "classic" ? "grid-cols-3" : "grid-cols-2"} gap-3`}>
            <div className="bg-white/5 rounded-2xl p-3 text-center">
              <Trophy className="w-4 h-4 text-yellow-400 mx-auto mb-1" />
              <p className="text-white/40 text-[10px] tracking-widest uppercase mb-0.5">Best</p>
              <p className="text-white font-bold text-lg">{bestScore}</p>
            </div>
            <div className="bg-white/5 rounded-2xl p-3 text-center">
              <Zap className="w-4 h-4 text-cyan-400 mx-auto mb-1" />
              <p className="text-white/40 text-[10px] tracking-widest uppercase mb-0.5">Combo</p>
              <p className="text-white font-bold text-lg">x{combo}</p>
            </div>
            {mode === "classic" && (
              <div className="bg-amber-400/5 rounded-2xl p-3 text-center border border-amber-400/10">
                <Coins className="w-4 h-4 text-amber-400 mx-auto mb-1" />
                <p className="text-amber-400/60 text-[10px] tracking-widest uppercase mb-0.5">Earned</p>
                <p className="text-amber-400 font-bold text-lg">+{coinsEarned}</p>
              </div>
            )}
          </div>
        </motion.div>

        {/* XP Bar */}
        {xpEarned > 0 && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 }}
            className="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mb-4"
          >
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <Star className="w-4 h-4 text-violet-400" />
                <span className="text-white/60 text-xs font-bold">Level {levelProgress.level}</span>
              </div>
              <span className="text-violet-400 text-xs font-bold">+{xpEarned} XP</span>
            </div>
            <div className="h-2 bg-white/5 rounded-full overflow-hidden">
              <motion.div
                initial={{ width: 0 }}
                animate={{ width: `${levelProgress.progress * 100}%` }}
                transition={{ duration: 0.8, delay: 0.4 }}
                className="h-full bg-gradient-to-r from-violet-500 to-cyan-400 rounded-full"
              />
            </div>
            {leveledUp && (
              <motion.div
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ delay: 0.6 }}
                className="mt-2 text-center"
              >
                <span className="text-yellow-400 font-black text-sm">🎉 LEVEL UP! Level {leveledUp}!</span>
              </motion.div>
            )}
          </motion.div>
        )}

        {/* New Achievements */}
        {newAchievements.length > 0 && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3 }}
            className="w-full bg-amber-400/5 border border-amber-400/20 rounded-2xl p-4 mb-4"
          >
            <div className="flex items-center gap-2 mb-2">
              <Award className="w-4 h-4 text-amber-400" />
              <span className="text-amber-400 text-xs font-bold tracking-widest">NEW ACHIEVEMENT{newAchievements.length > 1 ? "S" : ""}!</span>
            </div>
            {newAchievements.map((title, i) => (
              <p key={i} className="text-white/70 text-sm font-medium">🏆 {title}</p>
            ))}
          </motion.div>
        )}

        {/* Share */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.35 }}
          className="w-full mb-2"
        >
          <ShareButtons text={isNewBest
            ? `🏆 NEW BEST! I scored ${score} on Perfect Tap! Can you beat me? 🎯`
            : `🎯 I scored ${score} on Perfect Tap with a ${combo}x combo! Can you beat me?`}
          />
        </motion.div>

        {/* Buttons */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4 }}
          className="w-full flex flex-col gap-3"
        >
          <Link to={createPageUrl("Game") + `?mode=${mode}`}>
            <motion.button
              whileTap={{ scale: 0.97 }}
              className="w-full py-5 rounded-2xl bg-gradient-to-r from-violet-600 to-cyan-500 text-white text-lg font-black tracking-wide shadow-xl shadow-violet-500/30 flex items-center justify-center gap-2"
            >
              <RotateCcw className="w-5 h-5" />
              PLAY AGAIN
            </motion.button>
          </Link>
          <Link to={createPageUrl("Home")}>
            <motion.button
              whileTap={{ scale: 0.97 }}
              className="w-full py-4 rounded-2xl bg-white/5 border border-white/10 text-white/70 text-lg font-semibold flex items-center justify-center gap-2"
            >
              <Home className="w-5 h-5" />
              HOME
            </motion.button>
          </Link>
        </motion.div>
      </div>
    </div>
  );
}