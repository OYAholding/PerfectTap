import React, { useState, useEffect } from "react";
import { createPageUrl } from "@/utils";
import { Link, useNavigate } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Trophy, Lock, CheckCircle, Play, Star, Zap, Clock, Target, Filter } from "lucide-react";
import { getCachedProfile, quickSave } from "@/components/game/playerService";

const CATEGORIES = [
  { id: "all", label: "ALL", icon: "🏠" },
  { id: "beginner", label: "BEGINNER", icon: "🌱" },
  { id: "expert", label: "EXPERT", icon: "🔥" },
  { id: "special", label: "SPECIAL", icon: "✨" },
];

export const CHALLENGES = [
  // --- BEGINNER ---
  {
    id: "survivor",
    title: "Survivor",
    description: "Survive for 60 seconds without losing a life",
    icon: "🛡️",
    category: "beginner",
    difficulty: "EASY",
    difficultyColor: "text-green-400",
    reward: { type: "boost", label: "1.5× Multiplier (3 games)", value: 1.5, games: 3 },
    condition: { type: "time", seconds: 60 },
  },
  {
    id: "quick_starter",
    title: "Quick Starter",
    description: "Score 200 points within 15 seconds",
    icon: "⏱️",
    category: "beginner",
    difficulty: "EASY",
    difficultyColor: "text-green-400",
    reward: { type: "boost", label: "1.3× Multiplier (2 games)", value: 1.3, games: 2 },
    condition: { type: "score_in_time", score: 200, seconds: 15 },
  },
  {
    id: "triple_threat",
    title: "Triple Threat",
    description: "Get 3 PERFECT taps in your first 5 taps",
    icon: "🎪",
    category: "beginner",
    difficulty: "EASY",
    difficultyColor: "text-green-400",
    reward: { type: "boost", label: "1.5× Multiplier (2 games)", value: 1.5, games: 2 },
    condition: { type: "perfect_in_first_n", perfectCount: 3, taps: 5 },
  },
  {
    id: "combo_master",
    title: "Combo Master",
    description: "Achieve a 10× combo streak",
    icon: "⚡",
    category: "beginner",
    difficulty: "MEDIUM",
    difficultyColor: "text-yellow-400",
    reward: { type: "theme", label: "Neon Theme", themeId: "neon" },
    condition: { type: "combo", target: 10 },
  },
  {
    id: "perfectionist",
    title: "Perfectionist",
    description: "Get 10 PERFECT taps in a row",
    icon: "🎯",
    category: "beginner",
    difficulty: "MEDIUM",
    difficultyColor: "text-yellow-400",
    reward: { type: "boost", label: "2× Multiplier (5 games)", value: 2.0, games: 5 },
    condition: { type: "perfect_streak", target: 10 },
  },
  {
    id: "speed_racer",
    title: "Speed Racer",
    description: "Score 300 points at level 8 or above",
    icon: "🏎️",
    category: "beginner",
    difficulty: "MEDIUM",
    difficultyColor: "text-yellow-400",
    reward: { type: "boost", label: "1.8× Multiplier (3 games)", value: 1.8, games: 3 },
    condition: { type: "score_at_speed", score: 300, minLevel: 8 },
  },
  // --- EXPERT ---
  {
    id: "speed_demon",
    title: "Speed Demon",
    description: "Score 500 points at max speed (level 10+)",
    icon: "🔥",
    category: "expert",
    difficulty: "HARD",
    difficultyColor: "text-orange-400",
    reward: { type: "theme", label: "Fire Theme", themeId: "fire" },
    condition: { type: "score_at_speed", score: 500, minLevel: 10 },
  },
  {
    id: "ice_cold",
    title: "Ice Cold",
    description: "Complete 50 taps with no misses",
    icon: "❄️",
    category: "expert",
    difficulty: "HARD",
    difficultyColor: "text-orange-400",
    reward: { type: "theme", label: "Arctic Theme", themeId: "ice" },
    condition: { type: "no_miss", taps: 50 },
  },
  {
    id: "combo_king",
    title: "Combo King",
    description: "Reach a 20× combo streak",
    icon: "🔗",
    category: "expert",
    difficulty: "HARD",
    difficultyColor: "text-orange-400",
    reward: { type: "boost", label: "2.5× Multiplier (3 games)", value: 2.5, games: 3 },
    condition: { type: "combo", target: 20 },
  },
  {
    id: "endurance",
    title: "Endurance",
    description: "Survive for 120 seconds",
    icon: "🏃",
    category: "expert",
    difficulty: "HARD",
    difficultyColor: "text-orange-400",
    reward: { type: "boost", label: "2× Multiplier (5 games)", value: 2.0, games: 5 },
    condition: { type: "time", seconds: 120 },
  },
  {
    id: "no_great_allowed",
    title: "Perfection Only",
    description: "Hit 15 PERFECT taps in a row (no GREAT allowed)",
    icon: "💎",
    category: "expert",
    difficulty: "HARD",
    difficultyColor: "text-orange-400",
    reward: { type: "boost", label: "3× Multiplier (2 games)", value: 3.0, games: 2 },
    condition: { type: "perfect_streak", target: 15 },
  },
  {
    id: "half_century",
    title: "Half Century",
    description: "Reach a score of 500 with only PERFECT or GREAT hits",
    icon: "🌟",
    category: "expert",
    difficulty: "HARD",
    difficultyColor: "text-orange-400",
    reward: { type: "boost", label: "2× Multiplier (4 games)", value: 2.0, games: 4 },
    condition: { type: "score_no_miss", score: 500 },
  },
  // --- SPECIAL (Legendary) ---
  {
    id: "legend",
    title: "Legend",
    description: "Score 1000 points in a single game",
    icon: "👑",
    category: "special",
    difficulty: "LEGENDARY",
    difficultyColor: "text-violet-400",
    reward: { type: "theme", label: "Gold Rush Theme", themeId: "gold" },
    condition: { type: "score", target: 1000 },
  },
  {
    id: "iron_wall",
    title: "Iron Wall",
    description: "Complete 100 taps without a single miss",
    icon: "🧱",
    category: "special",
    difficulty: "LEGENDARY",
    difficultyColor: "text-violet-400",
    reward: { type: "boost", label: "3× Multiplier (5 games)", value: 3.0, games: 5 },
    condition: { type: "no_miss", taps: 100 },
  },
  {
    id: "speed_legend",
    title: "Speed Legend",
    description: "Score 1000 points at level 12 or above",
    icon: "💥",
    category: "special",
    difficulty: "LEGENDARY",
    difficultyColor: "text-violet-400",
    reward: { type: "boost", label: "3× Multiplier (3 games)", value: 3.0, games: 3 },
    condition: { type: "score_at_speed", score: 1000, minLevel: 12 },
  },
  {
    id: "ultimate",
    title: "Ultimate",
    description: "Score 2000 points in a single game",
    icon: "🏆",
    category: "special",
    difficulty: "LEGENDARY",
    difficultyColor: "text-violet-400",
    reward: { type: "boost", label: "5× Multiplier (1 game)", value: 5.0, games: 1 },
    condition: { type: "score", target: 2000 },
  },
];

export default function Challenges() {
  const [completedChallenges, setCompletedChallenges] = useState([]);
  const [activeChallenge, setActiveChallenge] = useState(null);
  const [selectedCategory, setSelectedCategory] = useState("all");
  const navigate = useNavigate();

  useEffect(() => {
    const p = getCachedProfile();
    setCompletedChallenges(p?.challenges_done || []);
    setActiveChallenge(p?.active_challenge || null);
  }, []);

  const selectChallenge = (challenge) => {
    if (completedChallenges.includes(challenge.id)) return;
    quickSave({ active_challenge: challenge.id });
    setActiveChallenge(challenge.id);
    navigate(createPageUrl("Game") + "?mode=classic");
  };

  const clearChallenge = () => {
    quickSave({ active_challenge: "" });
    setActiveChallenge(null);
  };

  const filteredChallenges = selectedCategory === "all"
    ? CHALLENGES
    : CHALLENGES.filter(c => c.category === selectedCategory);

  const completed = completedChallenges.length;
  const total = CHALLENGES.length;

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
          <div>
            <h1 className="text-2xl font-black text-white">CHALLENGES</h1>
            <p className="text-white/30 text-xs tracking-widest">Complete for rewards</p>
          </div>
          <div className="ml-auto bg-violet-500/10 border border-violet-500/20 rounded-full px-3 py-1">
            <span className="text-violet-300 text-xs font-bold">{completed}/{total}</span>
          </div>
        </div>

        {/* Progress Bar */}
        <div className="bg-white/5 rounded-full h-2 mb-5 overflow-hidden">
          <motion.div
            initial={{ width: 0 }}
            animate={{ width: `${(completed / total) * 100}%` }}
            transition={{ duration: 0.8, ease: "easeOut" }}
            className="h-full bg-gradient-to-r from-violet-500 to-cyan-400 rounded-full"
          />
        </div>

        {/* Category Tabs */}
        <div className="flex gap-2 mb-5 overflow-x-auto pb-1 -mx-1 px-1">
          {CATEGORIES.map(cat => (
            <motion.button
              key={cat.id}
              whileTap={{ scale: 0.95 }}
              onClick={() => setSelectedCategory(cat.id)}
              className={`flex-shrink-0 px-3.5 py-2 rounded-xl text-xs font-bold tracking-wide transition-all flex items-center gap-1.5 ${
                selectedCategory === cat.id
                  ? "bg-violet-500/20 border border-violet-500/40 text-violet-300"
                  : "bg-white/5 border border-white/10 text-white/40"
              }`}
            >
              <span>{cat.icon}</span>
              {cat.label}
            </motion.button>
          ))}
        </div>

        {/* Active Challenge Banner */}
        {activeChallenge && (
          <motion.div
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            className="bg-cyan-500/10 border border-cyan-500/30 rounded-2xl p-4 mb-5 flex items-center gap-3"
          >
            <Zap className="w-5 h-5 text-cyan-400 flex-shrink-0" />
            <div className="flex-1">
              <p className="text-cyan-300 text-sm font-bold">Active Challenge</p>
              <p className="text-white/50 text-xs">{CHALLENGES.find(c => c.id === activeChallenge)?.title}</p>
            </div>
            <button onClick={clearChallenge} className="text-white/30 text-xs underline">cancel</button>
          </motion.div>
        )}

        {/* Challenge List */}
        <div className="flex flex-col gap-3">
          <AnimatePresence mode="popLayout">
            {filteredChallenges.map((challenge, i) => {
              const isDone = completedChallenges.includes(challenge.id);
              const isActive = activeChallenge === challenge.id;

              return (
                <motion.div
                  key={challenge.id}
                  layout
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, scale: 0.95 }}
                  transition={{ delay: i * 0.04 }}
                  className={`rounded-2xl border p-4 transition-colors ${
                    isDone
                      ? "bg-green-500/5 border-green-500/20 opacity-70"
                      : isActive
                      ? "bg-cyan-500/10 border-cyan-500/40"
                      : "bg-white/5 border-white/10"
                  }`}
                >
                  <div className="flex items-start gap-3">
                    <div className={`w-12 h-12 rounded-xl flex items-center justify-center text-2xl flex-shrink-0 ${
                      isDone ? "bg-green-500/20" : "bg-white/5"
                    }`}>
                      {challenge.icon}
                    </div>

                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-0.5">
                        <p className={`font-black text-base ${isDone ? "text-green-300" : "text-white"}`}>
                          {challenge.title}
                        </p>
                        <span className={`text-xs font-bold ${challenge.difficultyColor}`}>
                          {challenge.difficulty}
                        </span>
                      </div>
                      <p className="text-white/40 text-xs leading-relaxed mb-2">{challenge.description}</p>
                      <div className="flex items-center gap-1.5">
                        <Trophy className="w-3 h-3 text-yellow-400" />
                        <span className="text-yellow-400/70 text-xs">{challenge.reward.label}</span>
                      </div>
                    </div>

                    <div className="flex-shrink-0">
                      {isDone ? (
                        <div className="w-9 h-9 rounded-full bg-green-500/20 flex items-center justify-center">
                          <CheckCircle className="w-5 h-5 text-green-400" />
                        </div>
                      ) : (
                        <motion.button
                          whileTap={{ scale: 0.9 }}
                          onClick={() => selectChallenge(challenge)}
                          className={`w-9 h-9 rounded-full flex items-center justify-center ${
                            isActive
                              ? "bg-cyan-500 shadow-lg shadow-cyan-500/40"
                              : "bg-violet-500/80 hover:bg-violet-500"
                          }`}
                        >
                          <Play className="w-4 h-4 text-white fill-white" />
                        </motion.button>
                      )}
                    </div>
                  </div>
                </motion.div>
              );
            })}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}