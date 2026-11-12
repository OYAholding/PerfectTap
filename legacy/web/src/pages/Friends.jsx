import React, { useState, useEffect, useCallback } from "react";
import { createPageUrl } from "@/utils";
import { Link, useNavigate } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Copy, Check, UserPlus, Trash2, Swords, Users, Share2, Loader2, Trophy, Gamepad2 } from "lucide-react";
import { getMyFriendCode, findPlayerByCode, addFriendById, removeFriend, loadFriendProfiles, getFriendIds } from "@/components/game/friendsSystem";
import { getProfileId } from "@/components/game/playerService";
import usePullToRefresh from "@/components/game/usePullToRefresh";

export default function Friends() {
  const navigate = useNavigate();
  const [myCode, setMyCode] = useState("");
  const [friends, setFriends] = useState([]);
  const [loading, setLoading] = useState(true);
  const [copied, setCopied] = useState(false);
  const [showAdd, setShowAdd] = useState(false);
  const [friendCode, setFriendCode] = useState("");
  const [error, setError] = useState("");
  const [adding, setAdding] = useState(false);

  useEffect(() => {
    setMyCode(getMyFriendCode());
    loadFriends();
  }, []);

  const loadFriends = useCallback(async () => {
    setLoading(true);
    const profiles = await loadFriendProfiles();
    setFriends(profiles);
    setLoading(false);
  }, []);

  const { pullProps, indicatorEl } = usePullToRefresh(loadFriends);

  const handleCopy = () => {
    navigator.clipboard.writeText(myCode);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleAdd = async () => {
    const code = friendCode.trim().toUpperCase();
    if (!code) { setError("Enter a friend code!"); return; }
    if (code === myCode) { setError("That's your own code!"); return; }

    setAdding(true);
    setError("");

    const player = await findPlayerByCode(code);
    if (!player) {
      setError("No player found with that code.");
      setAdding(false);
      return;
    }

    const myId = getProfileId();
    if (player.id === myId) {
      setError("That's your own code!");
      setAdding(false);
      return;
    }

    const ids = getFriendIds();
    if (ids.includes(player.id)) {
      setError("Already friends!");
      setAdding(false);
      return;
    }

    await addFriendById(player.id);
    await loadFriends();
    setShowAdd(false);
    setFriendCode("");
    setAdding(false);
  };

  const handleRemove = async (profileId) => {
    removeFriend(profileId);
    setFriends(prev => prev.filter(f => f.id !== profileId));
  };

  const getLevel = (stats) => Math.floor((stats?.totalGames || 0) / 10) + 1;

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col px-6 py-10 overflow-y-auto" {...pullProps}>
      <div className="max-w-sm mx-auto w-full">
        {indicatorEl}
        <div className="flex items-center gap-4 mb-6">
          <Link to={createPageUrl("Home")}>
            <motion.button whileTap={{ scale: 0.9 }} className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/60">
              <ArrowLeft className="w-5 h-5" />
            </motion.button>
          </Link>
          <div className="flex-1">
            <h1 className="text-2xl font-black text-white">FRIENDS</h1>
            <p className="text-white/30 text-xs tracking-widest">{friends.length} friend{friends.length !== 1 ? "s" : ""}</p>
          </div>
          <motion.button
            whileTap={{ scale: 0.9 }}
            onClick={() => { setShowAdd(!showAdd); setError(""); }}
            className="w-10 h-10 rounded-xl bg-violet-500/20 border border-violet-500/30 flex items-center justify-center text-violet-300"
          >
            <UserPlus className="w-5 h-5" />
          </motion.button>
        </div>

        <motion.div
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-white/5 border border-white/10 rounded-2xl p-5 mb-6 text-center"
        >
          <p className="text-white/30 text-[10px] tracking-widest uppercase mb-2">YOUR FRIEND CODE</p>
          <p className="text-white font-black text-2xl tracking-[0.2em] mb-3">{myCode}</p>
          <div className="flex gap-2 justify-center">
            <motion.button
              whileTap={{ scale: 0.95 }}
              onClick={handleCopy}
              className="flex items-center gap-2 px-4 py-2 rounded-xl bg-violet-500/20 border border-violet-500/30 text-violet-300 text-xs font-bold"
            >
              {copied ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
              {copied ? "Copied!" : "Copy"}
            </motion.button>
            <motion.button
              whileTap={{ scale: 0.95 }}
              onClick={() => {
                if (navigator.share) {
                  navigator.share({ text: `Add me on Perfect Tap! My friend code: ${myCode}` });
                } else { handleCopy(); }
              }}
              className="flex items-center gap-2 px-4 py-2 rounded-xl bg-cyan-500/20 border border-cyan-500/30 text-cyan-300 text-xs font-bold"
            >
              <Share2 className="w-3.5 h-3.5" />
              Share
            </motion.button>
          </div>
        </motion.div>

        <AnimatePresence>
          {showAdd && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              className="overflow-hidden mb-6"
            >
              <div className="bg-violet-500/5 border border-violet-500/20 rounded-2xl p-4 space-y-3">
                <p className="text-violet-300 text-xs font-bold tracking-widest uppercase">ADD BY FRIEND CODE</p>
                <input
                  type="text"
                  value={friendCode}
                  onChange={e => setFriendCode(e.target.value.toUpperCase())}
                  maxLength={8}
                  placeholder="Enter friend code..."
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white text-sm text-center font-bold tracking-widest placeholder:text-white/20 placeholder:font-normal placeholder:tracking-normal focus:outline-none focus:border-violet-500/50"
                />
                {error && <p className="text-red-400 text-xs text-center">{error}</p>}
                <motion.button
                  whileTap={{ scale: 0.97 }}
                  onClick={handleAdd}
                  disabled={adding}
                  className="w-full py-3 rounded-xl bg-gradient-to-r from-violet-500 to-cyan-500 text-white font-bold text-sm flex items-center justify-center gap-2 disabled:opacity-50"
                >
                  {adding ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
                  {adding ? "LOOKING UP..." : "ADD FRIEND"}
                </motion.button>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {loading ? (
          <div className="flex justify-center py-12">
            <Loader2 className="w-8 h-8 text-white/20 animate-spin" />
          </div>
        ) : friends.length === 0 ? (
          <div className="text-center py-12">
            <Users className="w-10 h-10 text-white/10 mx-auto mb-3" />
            <p className="text-white/30 text-sm">No friends yet</p>
            <p className="text-white/15 text-xs mt-1">Share your code to add friends!</p>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {friends.map((friend, i) => (
              <motion.div
                key={friend.id}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: i * 0.05 }}
                className="flex items-center gap-3 bg-white/5 border border-white/10 rounded-2xl p-4"
              >
                <div className="w-10 h-10 rounded-full bg-gradient-to-br from-violet-500 to-cyan-400 flex items-center justify-center text-lg">
                  {friend.avatar || "😊"}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-white font-bold text-sm truncate">{friend.username}</p>
                  <div className="flex items-center gap-2 text-white/30 text-[10px]">
                    <span>Lv {getLevel(friend.stats)}</span>
                    <span>•</span>
                    <Trophy className="w-2.5 h-2.5" />
                    <span>{friend.best_classic || 0}</span>
                    <span>•</span>
                    <Gamepad2 className="w-2.5 h-2.5" />
                    <span>{friend.stats?.totalGames || 0}</span>
                  </div>
                </div>
                <div className="flex gap-1.5">
                  <motion.button
                    whileTap={{ scale: 0.9 }}
                    onClick={() => navigate(createPageUrl("DuelLobby"))}
                    className="w-8 h-8 rounded-lg bg-rose-500/20 border border-rose-500/30 flex items-center justify-center text-rose-400"
                  >
                    <Swords className="w-3.5 h-3.5" />
                  </motion.button>
                  <motion.button
                    whileTap={{ scale: 0.9 }}
                    onClick={() => handleRemove(friend.id)}
                    className="w-8 h-8 rounded-lg bg-white/5 border border-white/10 flex items-center justify-center text-white/30"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </motion.button>
                </div>
              </motion.div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}