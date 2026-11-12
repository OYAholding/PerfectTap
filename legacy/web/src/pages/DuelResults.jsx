import React, { useState, useEffect, useRef } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { Trophy, Home, RotateCcw, Crown, Loader2, Zap, Users } from "lucide-react";
import { base44 } from "@/api/base44Client";
import ShareButtons from "@/components/game/ShareButtons";
import { recordDuel } from "@/components/game/statsSystem";
import { updateQuestProgress } from "@/components/game/questSystem";
import { getProfileId } from "@/components/game/playerService";
import { createDuelViaBackend } from "@/components/game/duelService";

export default function DuelResults() {
  const [duel, setDuel] = useState(null);
  const [loading, setLoading] = useState(true);
  const [role, setRole] = useState("host");
  const pollRef = useRef(null);

  useEffect(() => {
    const duelId = localStorage.getItem("perfecttap_duel_id");
    const duelRole = localStorage.getItem("perfecttap_duel_role") || "host";
    setRole(duelRole);

    if (!duelId) { setLoading(false); return; }

    const load = async () => {
      const duels = await base44.entities.duel.filter({ id: duelId });
      if (duels.length > 0) {
        setDuel(duels[0]);
        if (duels[0].host_score >= 0 && duels[0].guest_score >= 0) {
          setLoading(false);
          return true;
        }
      }
      return false;
    };

    load().then(done => {
      if (!done) {
        pollRef.current = setInterval(async () => {
          const complete = await load();
          if (complete) {
            clearInterval(pollRef.current);
            setLoading(false);
          }
        }, 2000);
      }
    });

    return () => { if (pollRef.current) clearInterval(pollRef.current); };
  }, []);

  if (!duel) {
    return (
      <div className="min-h-screen bg-[#0a0a0f] flex items-center justify-center">
        <p className="text-white/40">No duel data found.</p>
      </div>
    );
  }

  const bothDone = duel.host_score >= 0 && duel.guest_score >= 0;
  const hostWins = duel.host_score > duel.guest_score;
  const tie = duel.host_score === duel.guest_score;
  const iWon = (role === "host" && hostWins) || (role === "guest" && !hostWins && !tie);

  const myScore = role === "host" ? duel.host_score : duel.guest_score;
  const opponentScore = role === "host" ? duel.guest_score : duel.host_score;
  const myName = role === "host" ? duel.host_name : duel.guest_name;
  const opponentName = role === "host" ? duel.guest_name : duel.host_name;
  const myCombo = role === "host" ? duel.host_combo : duel.guest_combo;
  const opponentCombo = role === "host" ? duel.guest_combo : duel.host_combo;

  // Track duel result once
  const [tracked, setTracked] = React.useState(false);
  React.useEffect(() => {
    if (bothDone && !tracked) {
      setTracked(true);
      const result = tie ? "tie" : iWon ? "win" : "loss";
      recordDuel(result, opponentName, myScore, opponentScore);
      updateQuestProgress({ duels: 1 });
    }
  }, [bothDone, tracked]);

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col items-center justify-center px-6 relative overflow-hidden">
      <div className="absolute inset-0 pointer-events-none">
        <div className={`absolute top-1/3 left-1/2 -translate-x-1/2 w-96 h-96 rounded-full blur-3xl ${
          bothDone && iWon ? "bg-yellow-500/10" : bothDone ? "bg-rose-500/10" : "bg-violet-500/10"
        }`} />
      </div>

      <div className="relative z-10 flex flex-col items-center w-full max-w-sm">
        {!bothDone ? (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="flex flex-col items-center gap-6 py-20"
          >
            <Loader2 className="w-10 h-10 text-violet-400 animate-spin" />
            <div className="text-center">
              <p className="text-white font-bold text-xl mb-1">Waiting for opponent...</p>
              <p className="text-white/30 text-sm">Your score: {myScore}</p>
            </div>
          </motion.div>
        ) : (
          <>
            {/* Result header */}
            <motion.div initial={{ opacity: 0, y: -20 }} animate={{ opacity: 1, y: 0 }} className="mb-6 text-center">
              {tie ? (
                <p className="text-3xl font-black text-white">IT'S A TIE!</p>
              ) : iWon ? (
                <div className="flex flex-col items-center gap-2">
                  <Crown className="w-10 h-10 text-yellow-400" />
                  <p className="text-3xl font-black text-yellow-400">YOU WIN!</p>
                </div>
              ) : (
                <p className="text-3xl font-black text-rose-400">YOU LOSE</p>
              )}
            </motion.div>

            {/* Score comparison */}
            <motion.div
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 0.15 }}
              className="w-full bg-white/5 border border-white/10 rounded-3xl p-6 mb-6"
            >
              <div className="flex items-center justify-between mb-4">
                <p className="text-white/30 text-xs tracking-widest uppercase">Duel Results</p>
                <Users className="w-4 h-4 text-white/20" />
              </div>

              {/* Player rows */}
              <div className="space-y-3">
                <PlayerRow
                  name={myName || "You"}
                  score={myScore}
                  combo={myCombo}
                  isWinner={iWon && !tie}
                  isYou={true}
                />
                <div className="border-t border-white/5" />
                <PlayerRow
                  name={opponentName || "Opponent"}
                  score={opponentScore}
                  combo={opponentCombo}
                  isWinner={!iWon && !tie}
                  isYou={false}
                />
              </div>
            </motion.div>

            {/* Share */}
            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3 }} className="w-full mb-2">
              <ShareButtons text={
                tie
                  ? `🤝 I tied ${myScore}-${opponentScore} in a Perfect Tap duel! 🎯`
                  : iWon
                  ? `🏆 I beat ${opponentName} ${myScore}-${opponentScore} in a Perfect Tap duel! 🎯`
                  : `🎯 I scored ${myScore} in a Perfect Tap duel vs ${opponentName} (${opponentScore})! Rematch?`
              } />
            </motion.div>

            {/* Buttons */}
            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.4 }} className="w-full flex flex-col gap-3">
              <motion.button
                whileTap={{ scale: 0.97 }}
                onClick={async () => {
                  const playerName = myName || "Player";
                  const result = await createDuelViaBackend(playerName);
                  if (result.error) return;
                  const rematchMsg = `Rematch! Join my Perfect Tap duel with code: ${result.code}`;
                  if (navigator.share) {
                    navigator.share({ text: rematchMsg }).catch(() => {});
                  } else {
                    navigator.clipboard.writeText(result.code);
                  }
                  window.location.href = createPageUrl("DuelLobby") + `?id=${result.id}&role=host`;
                }}
                className="w-full py-5 rounded-2xl bg-gradient-to-r from-violet-500 to-cyan-400 text-white text-lg font-black tracking-wide shadow-xl shadow-violet-500/30 flex items-center justify-center gap-2"
              >
                <RotateCcw className="w-5 h-5" />
                REMATCH
              </motion.button>
              <Link to={createPageUrl("DuelLobby")}>
                <motion.button whileTap={{ scale: 0.97 }} className="w-full py-4 rounded-2xl bg-rose-500/10 border border-rose-500/30 text-rose-300 text-lg font-bold flex items-center justify-center gap-2">
                  <Users className="w-5 h-5" />
                  NEW DUEL
                </motion.button>
              </Link>
              <Link to={createPageUrl("Home")}>
                <motion.button whileTap={{ scale: 0.97 }} className="w-full py-4 rounded-2xl bg-white/5 border border-white/10 text-white/70 text-lg font-semibold flex items-center justify-center gap-2">
                  <Home className="w-5 h-5" />
                  HOME
                </motion.button>
              </Link>
            </motion.div>
          </>
        )}
      </div>
    </div>
  );
}

function PlayerRow({ name, score, combo, isWinner, isYou }) {
  return (
    <div className={`flex items-center gap-3 rounded-2xl p-3 ${isWinner ? "bg-yellow-400/5 border border-yellow-400/20" : ""}`}>
      <div className={`w-10 h-10 rounded-full flex items-center justify-center text-sm font-black ${
        isWinner ? "bg-yellow-400/20 text-yellow-400" : isYou ? "bg-violet-500/20 text-violet-400" : "bg-white/10 text-white/50"
      }`}>
        {isWinner ? <Crown className="w-4 h-4" /> : name.charAt(0).toUpperCase()}
      </div>
      <div className="flex-1">
        <div className="flex items-center gap-2">
          <p className={`font-bold ${isWinner ? "text-yellow-300" : "text-white"}`}>{name}</p>
          {isYou && <span className="text-white/20 text-xs">(you)</span>}
        </div>
        <div className="flex items-center gap-2 text-white/30 text-xs">
          <Zap className="w-3 h-3" /> {combo}x combo
        </div>
      </div>
      <p className={`text-3xl font-black ${isWinner ? "text-yellow-400" : "text-white/60"}`}>{score}</p>
    </div>
  );
}