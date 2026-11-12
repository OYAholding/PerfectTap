import React from "react";
import { motion } from "framer-motion";
import { Trophy, Zap, Gamepad2, Target, Swords, Coins, TrendingUp } from "lucide-react";
import { getCachedProfile } from "@/components/game/playerService";

const MODE_LABELS = {
  classic: "Classic",
  endless: "Endless",
  timed: "Timed",
  sudden_death: "Sudden Death",
  combo_frenzy: "Combo Frenzy",
  zen: "Zen",
  duel: "Duel",
};

export default function ProfileStats({ stats = {} }) {
  const s = {
    totalGames: 0, totalScore: 0, highestCombo: 0,
    totalDuels: 0, duelWins: 0, duelLosses: 0, duelTies: 0,
    totalCoinsEarned: 0, perfectTaps: 0, totalTaps: 0,
    favoriteMode: "", modeCounts: {},
    ...stats,
  };

  const accuracy = s.totalTaps > 0
    ? Math.round((s.perfectTaps / s.totalTaps) * 100)
    : 0;

  const statCards = [
    { label: "Total Games", value: s.totalGames, icon: Gamepad2, color: "text-violet-400", bg: "bg-violet-500/10 border-violet-500/20" },
    { label: "Total Score", value: (s.totalScore || 0).toLocaleString(), icon: Trophy, color: "text-yellow-400", bg: "bg-yellow-500/10 border-yellow-500/20" },
    { label: "Best Combo", value: `${s.highestCombo || 0}x`, icon: Zap, color: "text-cyan-400", bg: "bg-cyan-500/10 border-cyan-500/20" },
    { label: "Perfect Rate", value: `${accuracy}%`, icon: Target, color: "text-emerald-400", bg: "bg-emerald-500/10 border-emerald-500/20" },
    { label: "Duel Record", value: `${s.duelWins || 0}W/${s.duelLosses || 0}L`, icon: Swords, color: "text-rose-400", bg: "bg-rose-500/10 border-rose-500/20" },
    { label: "Coins Earned", value: (s.totalCoinsEarned || 0).toLocaleString(), icon: Coins, color: "text-amber-400", bg: "bg-amber-500/10 border-amber-500/20" },
  ];

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3">
        {statCards.map((card, i) => {
          const Icon = card.icon;
          return (
            <motion.div
              key={card.label}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: i * 0.05 }}
              className={`rounded-2xl border p-3 ${card.bg}`}
            >
              <Icon className={`w-4 h-4 ${card.color} mb-1.5`} />
              <p className="text-white/40 text-[10px] tracking-widest uppercase">{card.label}</p>
              <p className={`${card.color} font-black text-lg`}>{card.value}</p>
            </motion.div>
          );
        })}
      </div>

      {s.favoriteMode && s.totalGames > 0 && (
        <div className="bg-white/5 border border-white/10 rounded-2xl p-4 text-center">
          <p className="text-white/40 text-xs tracking-widest uppercase mb-1">Favorite Mode</p>
          <p className="text-white font-bold text-lg">{MODE_LABELS[s.favoriteMode] || s.favoriteMode}</p>
        </div>
      )}

      <ScoreChart />
    </div>
  );
}

function ScoreChart() {
  const p = getCachedProfile();
  const history = (p?.score_history || []).slice(0, 10).reverse();

  if (history.length < 2) return null;

  const scores = history.map(h => h.score || 0);
  const maxScore = Math.max(...scores, 1);

  return (
    <div className="bg-white/5 border border-white/10 rounded-2xl p-4">
      <div className="flex items-center gap-2 mb-3">
        <TrendingUp className="w-4 h-4 text-violet-400" />
        <p className="text-white/40 text-xs tracking-widest uppercase">Recent Scores</p>
      </div>
      <div className="flex items-end gap-1.5 h-24">
        {scores.map((score, i) => {
          const height = Math.max(8, (score / maxScore) * 100);
          return (
            <motion.div
              key={i}
              initial={{ height: 0 }}
              animate={{ height: `${height}%` }}
              transition={{ delay: i * 0.05, duration: 0.3 }}
              className="flex-1 bg-gradient-to-t from-violet-500 to-cyan-400 rounded-t-md relative group"
            >
              <div className="absolute -top-5 left-1/2 -translate-x-1/2 text-[9px] text-white/40 font-bold opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap">
                {score}
              </div>
            </motion.div>
          );
        })}
      </div>
    </div>
  );
}