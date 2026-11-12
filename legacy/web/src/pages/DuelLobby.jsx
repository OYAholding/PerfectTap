import React, { useState, useEffect, useRef } from "react";
import { createPageUrl } from "@/utils";
import { useNavigate, Link } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Copy, Check, UserPlus, Loader2, Play, Users, Eye } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { loadProfile, getUsername } from "@/components/game/playerService";
import { createDuelViaBackend, joinDuelViaBackend } from "@/components/game/duelService";

export default function DuelLobby() {
  const navigate = useNavigate();
  const urlParams = new URLSearchParams(window.location.search);
  const duelId = urlParams.get("id");
  const role = urlParams.get("role"); // "host" or "guest"

  const [tab, setTab] = useState("create"); // create | join
  const [playerName, setPlayerName] = useState("");
  const [joinCode, setJoinCode] = useState("");
  const [duel, setDuel] = useState(null);
  const [loading, setLoading] = useState(false);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState("");
  const pollRef = useRef(null);

  useEffect(() => {
    (async () => {
      await loadProfile();
      setPlayerName(getUsername());
    })();
  }, []);

  // If we have a duelId, load it and poll for guest
  useEffect(() => {
    if (!duelId) return;

    const loadDuel = async () => {
      const duels = await base44.entities.duel.filter({ id: duelId });
      if (duels.length > 0) setDuel(duels[0]);
    };
    loadDuel();

    pollRef.current = setInterval(async () => {
      const duels = await base44.entities.duel.filter({ id: duelId });
      if (duels.length > 0) {
        setDuel(duels[0]);
        if (duels[0].guest_joined && role === "host") {
          clearInterval(pollRef.current);
        }
      }
    }, 2000);

    return () => clearInterval(pollRef.current);
  }, [duelId, role]);

  const handleCreate = async () => {
    if (!playerName.trim()) { setError("Enter your name!"); return; }
    setLoading(true);
    setError("");
    const result = await createDuelViaBackend(playerName.trim());
    setLoading(false);
    if (result.error) {
      setError(result.error);
      return;
    }
    navigate(createPageUrl("DuelLobby") + `?id=${result.id}&role=host`);
  };

  const handleJoin = async () => {
    if (!playerName.trim()) { setError("Enter your name!"); return; }
    if (!joinCode.trim()) { setError("Enter the invite code!"); return; }
    setLoading(true);
    setError("");

    const result = await joinDuelViaBackend(joinCode.trim().toUpperCase(), playerName.trim());
    setLoading(false);

    if (result.error) {
      setError(result.error);
      return;
    }

    localStorage.setItem("perfecttap_duel_id", result.duelId);
    localStorage.setItem("perfecttap_duel_role", "guest");
    navigate(createPageUrl("Game") + "?mode=duel");
  };

  const handleStartDuel = () => {
    localStorage.setItem("perfecttap_duel_id", duel.id);
    localStorage.setItem("perfecttap_duel_role", "host");
    navigate(createPageUrl("Game") + "?mode=duel");
  };

  const handleCopy = () => {
    if (duel) {
      navigator.clipboard.writeText(duel.code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  // Waiting for guest screen
  if (duelId && duel && role === "host") {
    return (
      <div className="min-h-screen bg-[#0a0a0f] flex flex-col px-6 py-10">
        <div className="max-w-sm mx-auto w-full">
          <div className="flex items-center gap-4 mb-8">
            <Link to={createPageUrl("Home")}>
              <motion.button whileTap={{ scale: 0.9 }} className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/60">
                <ArrowLeft className="w-5 h-5" />
              </motion.button>
            </Link>
            <h1 className="text-2xl font-black text-white">DUEL LOBBY</h1>
          </div>

          <div className="flex flex-col items-center gap-6 mt-10">
            <motion.div
              initial={{ scale: 0.9, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              className="w-full bg-white/5 border border-white/10 rounded-3xl p-8 text-center"
            >
              <p className="text-white/40 text-xs tracking-widest uppercase mb-3">INVITE CODE</p>
              <p className="text-5xl font-black text-white tracking-[0.3em] mb-4">{duel.code}</p>
              <motion.button
                whileTap={{ scale: 0.95 }}
                onClick={handleCopy}
                className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-violet-500/20 border border-violet-500/30 text-violet-300 text-sm font-bold"
              >
                {copied ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
                {copied ? "Copied!" : "Copy Code"}
              </motion.button>
            </motion.div>

            {!duel.guest_joined ? (
              <motion.div
                animate={{ opacity: [0.5, 1, 0.5] }}
                transition={{ duration: 2, repeat: Infinity }}
                className="flex flex-col items-center gap-3"
              >
                <Loader2 className="w-8 h-8 text-violet-400 animate-spin" />
                <p className="text-white/40 text-sm">Waiting for opponent to join...</p>
                <p className="text-white/20 text-xs">Share the code with a friend</p>
              </motion.div>
            ) : (
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                className="w-full flex flex-col items-center gap-4"
              >
                <div className="flex items-center gap-3 bg-green-500/10 border border-green-500/30 rounded-2xl px-5 py-3">
                  <Users className="w-5 h-5 text-green-400" />
                  <div>
                    <p className="text-green-300 font-bold">{duel.guest_name} joined!</p>
                    <p className="text-white/30 text-xs">Ready to duel</p>
                  </div>
                </div>

                <motion.button
                  whileTap={{ scale: 0.97 }}
                  onClick={handleStartDuel}
                  className="w-full py-5 rounded-2xl bg-gradient-to-r from-rose-500 to-orange-400 text-white text-xl font-black tracking-wide shadow-xl shadow-rose-500/30 flex items-center justify-center gap-3"
                >
                  <Play className="w-6 h-6 fill-white" />
                  START DUEL
                </motion.button>
              </motion.div>
            )}
          </div>
        </div>
      </div>
    );
  }

  // Create / Join tabs
  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col px-6 py-10">
      <div className="max-w-sm mx-auto w-full">
        <div className="flex items-center gap-4 mb-6">
          <Link to={createPageUrl("Home")}>
            <motion.button whileTap={{ scale: 0.9 }} className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/60">
              <ArrowLeft className="w-5 h-5" />
            </motion.button>
          </Link>
          <div>
            <h1 className="text-2xl font-black text-white">DUEL</h1>
            <p className="text-white/30 text-xs tracking-widest">Challenge a friend</p>
          </div>
        </div>

        {/* Quick Actions */}
        <div className="grid grid-cols-2 gap-3 mb-6">
          <Link to={createPageUrl("Matchmaking")}>
            <motion.button whileTap={{ scale: 0.95 }} className="w-full py-3 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-300 text-xs font-bold flex items-center justify-center gap-2">
              <Users className="w-4 h-4" />
              FIND MATCH
            </motion.button>
          </Link>
          <Link to={createPageUrl("Spectate")}>
            <motion.button whileTap={{ scale: 0.95 }} className="w-full py-3 rounded-xl bg-green-500/10 border border-green-500/30 text-green-300 text-xs font-bold flex items-center justify-center gap-2">
              <Eye className="w-4 h-4" />
              SPECTATE
            </motion.button>
          </Link>
        </div>

        {/* Tabs */}
        <div className="grid grid-cols-2 gap-1.5 mb-6 bg-white/5 rounded-2xl p-1">
          {["create", "join"].map(t => (
            <button
              key={t}
              onClick={() => { setTab(t); setError(""); }}
              className={`py-3 rounded-xl text-sm font-bold transition-all ${
                tab === t
                  ? "bg-gradient-to-br from-rose-500 to-orange-400 text-white shadow-lg"
                  : "text-white/30 hover:text-white/60"
              }`}
            >
              {t === "create" ? "CREATE DUEL" : "JOIN DUEL"}
            </button>
          ))}
        </div>

        {/* Name input */}
        <div className="mb-4">
          <label className="text-white/30 text-xs tracking-widest uppercase block mb-2">Your Name</label>
          <input
            type="text"
            value={playerName}
            onChange={e => setPlayerName(e.target.value)}
            maxLength={20}
            placeholder="Enter your name..."
            className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white text-sm placeholder:text-white/20 focus:outline-none focus:border-violet-500/50"
          />
        </div>

        <AnimatePresence mode="wait">
          {tab === "create" ? (
            <motion.div key="create" initial={{ opacity: 0, x: -20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: 20 }}>
              <p className="text-white/30 text-xs leading-relaxed mb-6">
                Create a duel and share the code with a friend. Both of you play Classic mode — highest score wins!
              </p>
              <motion.button
                whileTap={{ scale: 0.97 }}
                onClick={handleCreate}
                disabled={loading}
                className="w-full py-5 rounded-2xl bg-gradient-to-r from-rose-500 to-orange-400 text-white text-lg font-black tracking-wide shadow-xl shadow-rose-500/30 flex items-center justify-center gap-2 disabled:opacity-60"
              >
                {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <UserPlus className="w-5 h-5" />}
                {loading ? "Creating..." : "CREATE DUEL"}
              </motion.button>
            </motion.div>
          ) : (
            <motion.div key="join" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -20 }}>
              <label className="text-white/30 text-xs tracking-widest uppercase block mb-2">Invite Code</label>
              <input
                type="text"
                value={joinCode}
                onChange={e => setJoinCode(e.target.value.toUpperCase())}
                maxLength={6}
                placeholder="XXXXXX"
                className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white text-center text-2xl font-black tracking-[0.3em] placeholder:text-white/20 focus:outline-none focus:border-violet-500/50 mb-6"
              />
              <motion.button
                whileTap={{ scale: 0.97 }}
                onClick={handleJoin}
                disabled={loading}
                className="w-full py-5 rounded-2xl bg-gradient-to-r from-rose-500 to-orange-400 text-white text-lg font-black tracking-wide shadow-xl shadow-rose-500/30 flex items-center justify-center gap-2 disabled:opacity-60"
              >
                {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Play className="w-5 h-5 fill-white" />}
                {loading ? "Joining..." : "JOIN DUEL"}
              </motion.button>
            </motion.div>
          )}
        </AnimatePresence>

        {error && (
          <motion.p
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="text-red-400 text-sm text-center mt-4"
          >
            {error}
          </motion.p>
        )}
      </div>
    </div>
  );
}