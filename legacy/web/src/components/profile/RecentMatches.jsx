import React from "react";
import { motion } from "framer-motion";
import { Trophy, Swords, Gamepad2, Clock } from "lucide-react";
import { format } from "date-fns";

const MODE_LABELS = {
  classic: "Classic",
  endless: "Endless",
  timed: "Timed",
  sudden_death: "Sudden Death",
  combo_frenzy: "Combo Frenzy",
  duel: "Duel",
};

const MODE_COLORS = {
  classic: "text-violet-400 bg-violet-500/10 border-violet-500/20",
  endless: "text-orange-400 bg-orange-500/10 border-orange-500/20",
  timed: "text-amber-400 bg-amber-500/10 border-amber-500/20",
  sudden_death: "text-red-400 bg-red-500/10 border-red-500/20",
  combo_frenzy: "text-fuchsia-400 bg-fuchsia-500/10 border-fuchsia-500/20",
  duel: "text-rose-400 bg-rose-500/10 border-rose-500/20",
};

export default function RecentMatches({ matches }) {
  if (!matches || matches.length === 0) {
    return (
      <div className="text-center py-12">
        <Gamepad2 className="w-10 h-10 text-white/10 mx-auto mb-3" />
        <p className="text-white/30 text-sm">No matches yet</p>
        <p className="text-white/15 text-xs mt-1">Play a game to see your history!</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      {matches.slice(0, 20).map((match, i) => {
        const mode = match.mode || "classic";
        const colorClass = MODE_COLORS[mode] || MODE_COLORS.classic;
        const isDuel = mode === "duel";

        return (
          <motion.div
            key={i}
            initial={{ opacity: 0, x: -10 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: i * 0.03 }}
            className="flex items-center gap-3 bg-white/5 border border-white/10 rounded-xl px-4 py-3"
          >
            <div className={`px-2 py-1 rounded-lg border text-[10px] font-bold tracking-wider ${colorClass}`}>
              {MODE_LABELS[mode] || mode}
            </div>
            <div className="flex-1">
              <p className="text-white font-bold text-sm">{match.score || 0}</p>
              {isDuel && match.result && (
                <p className={`text-xs font-bold ${
                  match.result === "win" ? "text-green-400" :
                  match.result === "loss" ? "text-red-400" : "text-white/40"
                }`}>
                  {match.result === "win" ? "Won" : match.result === "loss" ? "Lost" : "Tie"}
                  {match.opponent ? ` vs ${match.opponent}` : ""}
                </p>
              )}
              {!isDuel && match.maxCombo > 0 && (
                <p className="text-white/30 text-xs">{match.maxCombo}x combo</p>
              )}
            </div>
            {match.date && (
              <div className="flex items-center gap-1 text-white/20 text-[10px]">
                <Clock className="w-2.5 h-2.5" />
                {format(new Date(match.date), "MMM d")}
              </div>
            )}
          </motion.div>
        );
      })}
    </div>
  );
}