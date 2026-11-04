import React, { useState, useEffect, useRef } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { ArrowLeft, Eye, Trophy, Zap, Loader2, Users, Crown } from "lucide-react";
import { base44 } from "@/api/base44Client";

export default function Spectate() {
  const [duels, setDuels] = useState([]);
  const [loading, setLoading] = useState(true);
  const [watching, setWatching] = useState(null);
  const pollRef = useRef(null);

  useEffect(() => {
    loadDuels();
    // Refresh every 5 seconds
    const interval = setInterval(loadDuels, 5000);
    return () => clearInterval(interval);
  }, []);

  const loadDuels = async () => {
    const all = await base44.entities.duel.filter({ status: "in_progress" });
    setDuels(all);
    setLoading(false);
  };

  const handleWatch = (duel) => {
    setWatching(duel);
    // Poll for updates
    pollRef.current = setInterval(async () => {
      const updated = await base44.entities.duel.filter({ id: duel.id });
      if (updated.length > 0) {
        setWatching(updated[0]);
        if (updated[0].status === "completed") {
          clearInterval(pollRef.current);
        }
      }
    }, 2000);
  };

  const handleBack = () => {
    if (pollRef.current) clearInterval(pollRef.current);
    setWatching(null);
  };

  useEffect(() => {
    return () => { if (pollRef.current) clearInterval(pollRef.current); };
  }, []);

  // Watching a duel
  if (watching) {
    const bothDone = watching.host_score >= 0 && watching.guest_score >= 0;
    const hostWins = watching.host_score > watching.guest_score;
    const tie = watching.host_score === watching.guest_score;

    return (
      <div className="min-h-screen bg-[#0a0a0f] flex flex-col px-6 py-10">
        <div className="max-w-sm mx-auto w-full">
          {/* Header */}
          <div className="flex items-center gap-4 mb-8">
            <motion.button whileTap={{ scale: 0.9 }} onClick={handleBack} className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/60">
              <ArrowLeft className="w-5 h-5" />
            </motion.button>
            <div className="flex-1">
              <h1 className="text-2xl font-black text-white">SPECTATING</h1>
              <div className="flex items-center gap-1.5 mt-0.5">
                <Eye className="w-3 h-3 text-green-400" />
                <span className="text-green-400/60 text-[10px] tracking-widest">LIVE</span>
              </div>
            </div>
          </div>

          {/* VS Display */}
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="bg-white/5 border border-white/10 rounded-3xl p-6 mb-6"
          >
            <div className="flex items-center justify-between mb-4">
              <p className="text-white/30 text-xs tracking-widest uppercase">
                {watching.status === "completed" ? "MATCH COMPLETE" : "IN PROGRESS"}
              </p>
              {watching.status !== "completed" && (
                <motion.div
                  animate={{ opacity: [0.3, 1, 0.3] }}
                  transition={{ duration: 1.5, repeat: Infinity }}
                  className="w-2 h-2 rounded-full bg-green-400"
                />
              )}
            </div>

            {/* Host */}
            <div className={`flex items-center gap-3 rounded-2xl p-3 mb-2 ${bothDone && hostWins && !tie ? "bg-yellow-400/5 border border-yellow-400/20" : ""}`}>
              <div className={`w-10 h-10 rounded-full flex items-center justify-center font-black text-sm ${
                bothDone && hostWins && !tie ? "bg-yellow-400/20 text-yellow-400" : "bg-violet-500/20 text-violet-400"
              }`}>
                {bothDone && hostWins && !tie ? <Crown className="w-4 h-4" /> : watching.host_name?.charAt(0)?.toUpperCase() || "H"}
              </div>
              <div className="flex-1">
                <p className="text-white font-bold text-sm">{watching.host_name || "Host"}</p>
                <div className="flex items-center gap-2 text-white/30 text-xs">
                  <Zap className="w-3 h-3" /> {watching.host_combo}x combo
                </div>
              </div>
              <p className={`text-3xl font-black ${
                watching.host_score < 0 ? "text-white/20" : bothDone && hostWins && !tie ? "text-yellow-400" : "text-white/60"
              }`}>
                {watching.host_score < 0 ? "..." : watching.host_score}
              </p>
            </div>

            <div className="text-center text-white/10 text-xs font-black tracking-widest my-1">VS</div>

            {/* Guest */}
            <div className={`flex items-center gap-3 rounded-2xl p-3 ${bothDone && !hostWins && !tie ? "bg-yellow-400/5 border border-yellow-400/20" : ""}`}>
              <div className={`w-10 h-10 rounded-full flex items-center justify-center font-black text-sm ${
                bothDone && !hostWins && !tie ? "bg-yellow-400/20 text-yellow-400" : "bg-rose-500/20 text-rose-400"
              }`}>
                {bothDone && !hostWins && !tie ? <Crown className="w-4 h-4" /> : watching.guest_name?.charAt(0)?.toUpperCase() || "G"}
              </div>
              <div className="flex-1">
                <p className="text-white font-bold text-sm">{watching.guest_name || "Guest"}</p>
                <div className="flex items-center gap-2 text-white/30 text-xs">
                  <Zap className="w-3 h-3" /> {watching.guest_combo}x combo
                </div>
              </div>
              <p className={`text-3xl font-black ${
                watching.guest_score < 0 ? "text-white/20" : bothDone && !hostWins && !tie ? "text-yellow-400" : "text-white/60"
              }`}>
                {watching.guest_score < 0 ? "..." : watching.guest_score}
              </p>
            </div>
          </motion.div>

          {bothDone && (
            <motion.div
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              className="text-center p-4"
            >
              <p className={`text-2xl font-black ${tie ? "text-white" : "text-yellow-400"}`}>
                {tie ? "IT'S A TIE!" : `${hostWins ? watching.host_name : watching.guest_name} WINS!`}
              </p>
            </motion.div>
          )}

          {!bothDone && (
            <div className="text-center">
              <motion.div
                animate={{ opacity: [0.3, 0.7, 0.3] }}
                transition={{ duration: 2, repeat: Infinity }}
                className="text-white/20 text-sm"
              >
                Waiting for scores...
              </motion.div>
            </div>
          )}
        </div>
      </div>
    );
  }

  // Duel list
  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col px-6 py-10">
      <div className="max-w-sm mx-auto w-full">
        {/* Header */}
        <div className="flex items-center gap-4 mb-6">
          <Link to={createPageUrl("DuelLobby")}>
            <motion.button whileTap={{ scale: 0.9 }} className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/60">
              <ArrowLeft className="w-5 h-5" />
            </motion.button>
          </Link>
          <div className="flex-1">
            <h1 className="text-2xl font-black text-white">SPECTATE</h1>
            <p className="text-white/30 text-xs tracking-widest">Watch live duels</p>
          </div>
          <div className="flex items-center gap-1.5 bg-green-400/10 border border-green-400/20 rounded-full px-3 py-1.5">
            <Eye className="w-3.5 h-3.5 text-green-400" />
            <span className="text-green-400 text-xs font-bold">{duels.length} LIVE</span>
          </div>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-20">
            <Loader2 className="w-8 h-8 text-white/20 animate-spin" />
          </div>
        ) : duels.length === 0 ? (
          <div className="text-center py-16">
            <Eye className="w-12 h-12 text-white/10 mx-auto mb-3" />
            <p className="text-white/30 text-sm">No live duels right now</p>
            <p className="text-white/15 text-xs mt-1">Check back later!</p>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {duels.map((d, i) => (
              <motion.button
                key={d.id}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: i * 0.05 }}
                whileTap={{ scale: 0.98 }}
                onClick={() => handleWatch(d)}
                className="w-full bg-white/5 border border-white/10 rounded-2xl p-4 text-left hover:bg-white/8 transition-all"
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full bg-green-400" />
                    <span className="text-green-400/60 text-[10px] tracking-widest">LIVE</span>
                  </div>
                  <Eye className="w-4 h-4 text-white/20" />
                </div>
                <div className="flex items-center gap-3">
                  <div className="flex-1">
                    <p className="text-white font-bold text-sm">{d.host_name || "Player 1"}</p>
                    <p className="text-white/30 text-xs">
                      {d.host_score >= 0 ? `Score: ${d.host_score}` : "Playing..."}
                    </p>
                  </div>
                  <span className="text-white/10 font-black text-xs">VS</span>
                  <div className="flex-1 text-right">
                    <p className="text-white font-bold text-sm">{d.guest_name || "Player 2"}</p>
                    <p className="text-white/30 text-xs">
                      {d.guest_score >= 0 ? `Score: ${d.guest_score}` : "Playing..."}
                    </p>
                  </div>
                </div>
              </motion.button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}