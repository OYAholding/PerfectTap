import React, { useState, useEffect, useCallback } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { ArrowLeft, Trophy, Users, Loader2, Crown, Gamepad2 } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { getCachedProfile, getProfileId } from "@/components/game/playerService";
import { loadFriendProfiles, getFriendIds } from "@/components/game/friendsSystem";
import usePullToRefresh from "@/components/game/usePullToRefresh";

const TABS = [
  { id: "global", label: "Global", icon: Trophy },
  { id: "friends", label: "Friends", icon: Users },
];

export default function Leaderboard() {
  const [activeTab, setActiveTab] = useState("global");
  const [globalPlayers, setGlobalPlayers] = useState([]);
  const [friendPlayers, setFriendPlayers] = useState([]);
  const [loading, setLoading] = useState(true);
  const myId = getProfileId();

  useEffect(() => {
    loadLeaderboard();
  }, []);

  const loadLeaderboard = useCallback(async () => {
    setLoading(true);
    const allProfiles = await base44.entities.PlayerProfile.list("-best_classic", 50);
    setGlobalPlayers(allProfiles.filter(p => p.username && p.best_classic > 0));

    const friendIds = getFriendIds();
    if (friendIds.length > 0) {
      const friendProfiles = await loadFriendProfiles();
      const me = getCachedProfile();
      const combined = [...friendProfiles];
      if (me) combined.push(me);
      combined.sort((a, b) => (b.best_classic || 0) - (a.best_classic || 0));
      setFriendPlayers(combined);
    } else {
      const me = getCachedProfile();
      setFriendPlayers(me ? [me] : []);
    }
    setLoading(false);
  }, []);

  const { pullProps, indicatorEl } = usePullToRefresh(loadLeaderboard);

  const players = activeTab === "global" ? globalPlayers : friendPlayers;

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col px-6 py-10 overflow-y-auto" {...pullProps}>
      <div className="max-w-sm mx-auto w-full">
        {indicatorEl}
        <div className="flex items-center gap-4 mb-8">
          <Link to={createPageUrl("Home")}>
            <motion.button whileTap={{ scale: 0.9 }} className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/60">
              <ArrowLeft className="w-5 h-5" />
            </motion.button>
          </Link>
          <div>
            <h1 className="text-2xl font-black text-white">LEADERBOARD</h1>
            <p className="text-white/30 text-xs tracking-widest">Top players</p>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-1.5 mb-6 bg-white/5 rounded-2xl p-1">
          {TABS.map(tab => {
            const Icon = tab.icon;
            const active = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`py-3 rounded-xl text-sm font-bold transition-all flex items-center justify-center gap-2 ${
                  active ? "bg-gradient-to-br from-violet-600 to-cyan-500 text-white shadow-lg" : "text-white/30 hover:text-white/60"
                }`}
              >
                <Icon className="w-4 h-4" />
                {tab.label}
              </button>
            );
          })}
        </div>

        {loading ? (
          <div className="flex justify-center py-20">
            <Loader2 className="w-8 h-8 text-white/20 animate-spin" />
          </div>
        ) : players.length === 0 ? (
          <div className="text-center py-16">
            <Trophy className="w-12 h-12 text-white/10 mx-auto mb-3" />
            <p className="text-white/30 text-sm">
              {activeTab === "friends" ? "Add friends to compare scores!" : "No scores yet. Play to get on the board!"}
            </p>
          </div>
        ) : (
          <>
            {players.length >= 1 && (
              <div className="flex items-end justify-center gap-3 mb-8">
                {players[1] && <PodiumCard player={players[1]} rank={2} isMe={players[1].id === myId} />}
                <PodiumCard player={players[0]} rank={1} isMe={players[0].id === myId} />
                {players[2] && <PodiumCard player={players[2]} rank={3} isMe={players[2].id === myId} />}
              </div>
            )}

            <div className="flex flex-col gap-2">
              {players.slice(3).map((player, i) => (
                <motion.div
                  key={player.id}
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: i * 0.03 }}
                  className={`flex items-center gap-3 border rounded-2xl px-4 py-3 ${
                    player.id === myId ? "bg-violet-500/10 border-violet-500/30" : "bg-white/5 border-white/10"
                  }`}
                >
                  <div className="w-8 h-8 rounded-full bg-white/5 flex items-center justify-center text-sm font-black text-white/30">
                    {i + 4}
                  </div>
                  <div className="w-8 h-8 rounded-full bg-gradient-to-br from-violet-500/30 to-cyan-400/30 flex items-center justify-center text-sm">
                    {player.avatar || "😊"}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className={`font-bold text-sm truncate ${player.id === myId ? "text-violet-300" : "text-white"}`}>
                      {player.username}{player.id === myId ? " (you)" : ""}
                    </p>
                    <div className="flex items-center gap-2 text-white/30 text-[10px]">
                      <Gamepad2 className="w-2.5 h-2.5" />
                      <span>{player.stats?.totalGames || 0} games</span>
                    </div>
                  </div>
                  <p className="text-white font-black text-lg">{player.best_classic || 0}</p>
                </motion.div>
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function PodiumCard({ player, rank, isMe }) {
  const colors = {
    1: { bg: "from-yellow-400/20 to-amber-500/20", border: "border-yellow-400/40", text: "text-yellow-400", h: "h-28" },
    2: { bg: "from-gray-300/10 to-slate-400/10", border: "border-gray-400/30", text: "text-gray-300", h: "h-20" },
    3: { bg: "from-orange-400/10 to-amber-600/10", border: "border-orange-400/20", text: "text-orange-400", h: "h-16" },
  };
  const c = colors[rank];

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: rank === 1 ? 0 : 0.15 }}
      className={`flex flex-col items-center ${rank === 1 ? "order-2" : rank === 2 ? "order-1" : "order-3"}`}
    >
      <div className="relative mb-2">
        <div className={`w-14 h-14 rounded-full bg-gradient-to-br ${c.bg} border-2 ${c.border} flex items-center justify-center text-xl ${isMe ? "ring-2 ring-violet-500" : ""}`}>
          {player.avatar || "😊"}
        </div>
        {rank === 1 && <Crown className="w-5 h-5 text-yellow-400 absolute -top-2 left-1/2 -translate-x-1/2" />}
      </div>
      <p className={`text-xs font-bold truncate max-w-[80px] ${isMe ? "text-violet-300" : "text-white"}`}>
        {player.username}
      </p>
      <p className={`text-lg font-black ${c.text}`}>{player.best_classic || 0}</p>
      <div className={`w-full rounded-t-xl bg-gradient-to-b ${c.bg} border ${c.border} border-b-0 flex items-center justify-center ${c.h} mt-1`}>
        <span className={`text-2xl font-black ${c.text}`}>#{rank}</span>
      </div>
    </motion.div>
  );
}