import React, { useState, useEffect } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { ArrowLeft, Coins, BarChart3, Award, Pencil, Copy, Check, Trophy, Gamepad2, Zap, Target, Swords } from "lucide-react";
import { getCoins } from "@/components/game/coinSystem";
import { getCachedProfile } from "@/components/game/playerService";
import { getFriendIds } from "@/components/game/friendsSystem";
import { getLevelProgress } from "@/components/game/xpSystem";
import { getAchievementProgress } from "@/components/game/achievementSystem";
import ProfileStats from "@/components/profile/ProfileStats";
import BadgeShowcase from "@/components/profile/BadgeShowcase";
import RecentMatches from "@/components/profile/RecentMatches";

export default function Profile() {
  const [profile, setProfile] = useState(null);
  const [stats, setStats] = useState(null);
  const [coins, setCoins] = useState(0);
  const [activeTab, setActiveTab] = useState("stats");
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    const p = getCachedProfile();
    setProfile(p);
    setStats(p?.stats || {});
    setCoins(getCoins());
  }, []);

  if (!profile || !stats) return null;

  const lp = getLevelProgress();
  const level = lp.level;
  const friendCount = getFriendIds().length;
  const accuracy = stats.totalTaps > 0 ? Math.round((stats.perfectTaps / stats.totalTaps) * 100) : 0;
  const achProgress = getAchievementProgress();

  const handleCopy = () => {
    navigator.clipboard.writeText(profile.friend_code || "");
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const tabs = [
    { id: "stats", label: "Stats", icon: BarChart3 },
    { id: "matches", label: "Matches", icon: Gamepad2 },
    { id: "badges", label: "Badges", icon: Award },
  ];

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col px-6 py-10">
      <div className="max-w-sm mx-auto w-full">
        <div className="flex items-center gap-4 mb-6">
          <Link to={createPageUrl("Home")}>
            <motion.button whileTap={{ scale: 0.9 }} className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/60">
              <ArrowLeft className="w-5 h-5" />
            </motion.button>
          </Link>
          <div className="flex-1">
            <h1 className="text-2xl font-black text-white">PROFILE</h1>
          </div>
          <div className="flex items-center gap-1.5 bg-amber-400/10 border border-amber-400/20 rounded-full px-3 py-1.5">
            <Coins className="w-4 h-4 text-amber-400" />
            <span className="text-amber-400 text-sm font-black">{coins}</span>
          </div>
        </div>

        <motion.div
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          className="w-full bg-white/5 border border-white/10 rounded-3xl p-6 mb-4"
        >
          <div className="flex items-center gap-4 mb-4">
            <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-violet-500 to-cyan-400 flex items-center justify-center shadow-lg text-3xl">
              {profile.avatar || "😊"}
            </div>
            <div className="flex-1">
              <div className="flex items-center gap-2">
                <p className="text-white font-black text-xl">{profile.username || "Player"}</p>
                <Link to={createPageUrl("SetUsername") + "?redirect=Profile"}>
                  <Pencil className="w-3.5 h-3.5 text-white/30 hover:text-white/60 transition-colors" />
                </Link>
              </div>
              <p className="text-white/30 text-xs">
                Level {level} • {friendCount} friend{friendCount !== 1 ? "s" : ""} • {achProgress.unlocked}/{achProgress.total} 🏆
              </p>
              <div className="mt-1.5 flex items-center gap-2 w-full">
                <div className="flex-1 h-1.5 bg-white/5 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-gradient-to-r from-violet-500 to-cyan-400 rounded-full transition-all"
                    style={{ width: `${lp.progress * 100}%` }}
                  />
                </div>
                <span className="text-white/20 text-[9px] font-bold">{lp.xp}/{lp.needed} XP</span>
              </div>
            </div>
          </div>

          <div className="flex items-center justify-between bg-white/5 rounded-xl px-4 py-2.5">
            <div>
              <p className="text-white/30 text-[10px] tracking-widest uppercase">FRIEND CODE</p>
              <p className="text-white font-bold tracking-[0.15em]">{profile.friend_code}</p>
            </div>
            <motion.button
              whileTap={{ scale: 0.9 }}
              onClick={handleCopy}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-violet-500/20 border border-violet-500/30 text-violet-300 text-xs font-bold"
            >
              {copied ? <Check className="w-3 h-3" /> : <Copy className="w-3 h-3" />}
              {copied ? "Copied" : "Copy"}
            </motion.button>
          </div>
        </motion.div>

        <div className="grid grid-cols-4 gap-2 mb-4">
          <QuickStat icon={Trophy} label="Best" value={profile.best_classic || 0} color="text-yellow-400" />
          <QuickStat icon={Gamepad2} label="Games" value={stats.totalGames || 0} color="text-violet-400" />
          <QuickStat icon={Zap} label="Combo" value={`${stats.highestCombo || 0}x`} color="text-cyan-400" />
          <QuickStat icon={Target} label="Perfect" value={`${accuracy}%`} color="text-emerald-400" />
        </div>

        <div className="bg-rose-500/5 border border-rose-500/20 rounded-2xl p-3 mb-6 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Swords className="w-4 h-4 text-rose-400" />
            <span className="text-rose-300 text-xs font-bold">DUEL RECORD</span>
          </div>
          <div className="flex items-center gap-3 text-sm font-black">
            <span className="text-green-400">{stats.duelWins || 0}W</span>
            <span className="text-white/20">/</span>
            <span className="text-red-400">{stats.duelLosses || 0}L</span>
            <span className="text-white/20">/</span>
            <span className="text-white/40">{stats.duelTies || 0}T</span>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-1.5 mb-6 bg-white/5 rounded-2xl p-1">
          {tabs.map(tab => {
            const Icon = tab.icon;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`py-3 rounded-xl text-sm font-bold transition-all flex items-center justify-center gap-2 ${
                  activeTab === tab.id ? "bg-gradient-to-br from-violet-600 to-cyan-500 text-white shadow-lg" : "text-white/30 hover:text-white/60"
                }`}
              >
                <Icon className="w-4 h-4" />
                {tab.label}
              </button>
            );
          })}
        </div>

        {activeTab === "stats" && <ProfileStats stats={stats} />}
        {activeTab === "matches" && <RecentMatches matches={profile.recent_matches || profile.score_history || []} />}
        {activeTab === "badges" && <BadgeShowcase />}
      </div>
    </div>
  );
}

function QuickStat({ icon: Icon, label, value, color }) {
  return (
    <div className="bg-white/5 border border-white/10 rounded-xl p-2.5 text-center">
      <Icon className={`w-3.5 h-3.5 ${color} mx-auto mb-1`} />
      <p className={`${color} font-black text-sm`}>{value}</p>
      <p className="text-white/30 text-[9px] tracking-widest uppercase">{label}</p>
    </div>
  );
}