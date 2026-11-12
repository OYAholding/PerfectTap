import React, { useState, useEffect, useRef } from "react";
import { createPageUrl } from "@/utils";
import { useNavigate, Link } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Loader2, Swords, Zap, Users } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { getStats } from "@/components/game/statsSystem";
import { getUsername, getProfileId } from "@/components/game/playerService";
import { createDuelViaBackend } from "@/components/game/duelService";

function getTier(totalScore, totalGames) {
  if (totalGames === 0) return "bronze";
  const avg = totalScore / totalGames;
  if (avg >= 1500) return "diamond";
  if (avg >= 1000) return "gold";
  if (avg >= 500) return "silver";
  return "bronze";
}

const TIER_INFO = {
  bronze: { label: "Bronze", color: "text-orange-400", gradient: "from-orange-600 to-amber-500" },
  silver: { label: "Silver", color: "text-gray-300", gradient: "from-gray-400 to-slate-300" },
  gold: { label: "Gold", color: "text-yellow-400", gradient: "from-yellow-400 to-amber-300" },
  diamond: { label: "Diamond", color: "text-cyan-300", gradient: "from-cyan-400 to-blue-300" },
};

export default function Matchmaking() {
  const navigate = useNavigate();
  const [phase, setPhase] = useState("searching"); // searching | found | error
  const [myTier, setMyTier] = useState("bronze");
  const [searchTime, setSearchTime] = useState(0);
  const [duel, setDuel] = useState(null);
  const pollRef = useRef(null);
  const timerRef = useRef(null);
  const createdDuelRef = useRef(null);

  useEffect(() => {
    const stats = getStats();
    const tier = getTier(stats.totalScore, stats.totalGames);
    setMyTier(tier);

    const playerName = getUsername() || "Player";
    const myProfileId = getProfileId();

    // Try to find an existing "waiting" duel first
    const startMatchmaking = async () => {
      // Look for open duels (not created by me)
      const waiting = await base44.entities.duel.filter({ status: "waiting" });
      const other = waiting.find(d => d.host_id !== myProfileId);
      
      if (other) {
        // Re-check the duel hasn't been claimed by someone else
        const freshCheck = await base44.entities.duel.filter({ id: other.id });
        const target = freshCheck[0];
        if (!target || target.guest_joined) {
          // Already taken — fall through to create our own
        } else {
          await base44.entities.duel.update(target.id, {
            guest_id: myProfileId,
            guest_name: playerName,
            guest_joined: true,
            status: "in_progress",
          });
          setDuel(target);
          setPhase("found");

          // Start game after short delay
          setTimeout(() => {
            localStorage.setItem("perfecttap_duel_id", target.id);
            localStorage.setItem("perfecttap_duel_role", "guest");
            navigate(createPageUrl("Game") + "?mode=duel");
          }, 2000);
          return;
        }
      }

      // No open duels — create one and wait
      const result = await createDuelViaBackend(playerName);
      if (result.error) return;
      createdDuelRef.current = result.id;

      // Poll for guest
      pollRef.current = setInterval(async () => {
        const duels = await base44.entities.duel.filter({ id: result.id });
        if (duels.length > 0 && duels[0].guest_joined) {
          clearInterval(pollRef.current);
          setDuel(duels[0]);
          setPhase("found");
          setTimeout(() => {
            localStorage.setItem("perfecttap_duel_id", result.id);
            localStorage.setItem("perfecttap_duel_role", "host");
            navigate(createPageUrl("Game") + "?mode=duel");
          }, 2000);
        }
      }, 2000);
    };

    startMatchmaking();

    // Search timer
    timerRef.current = setInterval(() => {
      setSearchTime(t => t + 1);
    }, 1000);

    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [navigate]);

  const handleCancel = async () => {
    if (pollRef.current) clearInterval(pollRef.current);
    if (timerRef.current) clearInterval(timerRef.current);
    // Clean up created duel
    if (createdDuelRef.current) {
      await base44.entities.duel.delete(createdDuelRef.current);
    }
    navigate(createPageUrl("DuelLobby"));
  };

  const tierInfo = TIER_INFO[myTier];

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col px-6 py-10">
      <div className="max-w-sm mx-auto w-full flex flex-col items-center">
        {/* Header */}
        <div className="flex items-center gap-4 mb-10 w-full">
          <motion.button whileTap={{ scale: 0.9 }} onClick={handleCancel} className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/60">
            <ArrowLeft className="w-5 h-5" />
          </motion.button>
          <div>
            <h1 className="text-2xl font-black text-white">MATCHMAKING</h1>
            <p className="text-white/30 text-xs tracking-widest">Finding an opponent...</p>
          </div>
        </div>

        {/* Tier badge */}
        <motion.div
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          className={`mb-8 px-5 py-2 rounded-full bg-gradient-to-r ${tierInfo.gradient} bg-opacity-20`}
        >
          <p className={`${tierInfo.color} font-black text-sm tracking-widest`}>
            {tierInfo.label.toUpperCase()} TIER
          </p>
        </motion.div>

        {phase === "searching" && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="flex flex-col items-center gap-6"
          >
            {/* Animated search ring */}
            <div className="relative w-32 h-32">
              <motion.div
                animate={{ rotate: 360 }}
                transition={{ duration: 3, repeat: Infinity, ease: "linear" }}
                className="absolute inset-0 border-2 border-t-rose-500 border-r-orange-400 border-b-transparent border-l-transparent rounded-full"
              />
              <motion.div
                animate={{ rotate: -360 }}
                transition={{ duration: 5, repeat: Infinity, ease: "linear" }}
                className="absolute inset-3 border-2 border-t-transparent border-r-transparent border-b-violet-500 border-l-cyan-400 rounded-full"
              />
              <div className="absolute inset-0 flex items-center justify-center">
                <Swords className="w-10 h-10 text-white/40" />
              </div>
            </div>

            <div className="text-center">
              <p className="text-white font-bold text-lg mb-1">Searching for opponent...</p>
              <p className="text-white/30 text-sm tabular-nums">{Math.floor(searchTime / 60)}:{(searchTime % 60).toString().padStart(2, "0")}</p>
            </div>

            <motion.button
              whileTap={{ scale: 0.97 }}
              onClick={handleCancel}
              className="px-6 py-3 rounded-xl bg-white/5 border border-white/10 text-white/40 text-sm font-bold"
            >
              CANCEL
            </motion.button>
          </motion.div>
        )}

        {phase === "found" && (
          <motion.div
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            className="flex flex-col items-center gap-6"
          >
            <motion.div
              animate={{ scale: [1, 1.1, 1] }}
              transition={{ duration: 0.5, repeat: 2 }}
              className="w-24 h-24 rounded-full bg-gradient-to-br from-rose-500 to-orange-400 flex items-center justify-center shadow-2xl shadow-rose-500/40"
            >
              <Users className="w-12 h-12 text-white" />
            </motion.div>
            <div className="text-center">
              <p className="text-rose-400 font-black text-2xl mb-1">OPPONENT FOUND!</p>
              <p className="text-white/30 text-sm">{duel?.guest_name || duel?.host_name}</p>
              <p className="text-white/20 text-xs mt-2">Starting duel...</p>
            </div>
            <Loader2 className="w-6 h-6 text-rose-400 animate-spin" />
          </motion.div>
        )}
      </div>
    </div>
  );
}