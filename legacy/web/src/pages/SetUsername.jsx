import React, { useState, useEffect } from "react";
import { createPageUrl } from "@/utils";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { User, Check, ArrowLeft, Loader2 } from "lucide-react";
import { loadProfile, isUsernameAvailable, createProfile, saveProfile } from "@/components/game/playerService";

export default function SetUsername() {
  const navigate = useNavigate();
  const [name, setName] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [initialLoading, setInitialLoading] = useState(true);
  const [isEdit, setIsEdit] = useState(false);
  const [profileReady, setProfileReady] = useState(false);

  const urlParams = new URLSearchParams(window.location.search);
  const redirectTo = urlParams.get("redirect") || "Home";

  useEffect(() => {
    (async () => {
      // Force a fresh load from server to ensure ID is correct
      const profile = await loadProfile();
      if (profile?.username) {
        setName(profile.username);
        setIsEdit(true);
        setProfileReady(true);
      } else {
        // No profile exists — this is a new user creation flow
        setIsEdit(false);
        setProfileReady(false);
      }
      setInitialLoading(false);
    })();
  }, []);

  const handleSave = async () => {
    const trimmed = name.trim();
    if (trimmed.length < 2) {
      setError("Name must be at least 2 characters");
      return;
    }
    if (trimmed.length > 20) {
      setError("Name must be 20 characters or less");
      return;
    }
    if (!/^[\p{L}\p{N}_\- ]+$/u.test(trimmed)) {
      setError("Only letters, numbers, spaces, _ and - are allowed");
      return;
    }

    setLoading(true);
    setError("");

    try {
      const available = await isUsernameAvailable(trimmed);
      if (!available) {
        setError("This username is already taken");
        setLoading(false);
        return;
      }

      if (profileReady) {
        await saveProfile({ username: trimmed });
      } else {
        await createProfile(trimmed);
      }

      // Reload profile to refresh cache with new data
      await loadProfile();
      setLoading(false);
      navigate(createPageUrl(redirectTo));
    } catch (err) {
      console.error("Save username error:", err);
      setError("Something went wrong. Please try again.");
      setLoading(false);
    }
  };

  if (initialLoading) {
    return (
      <div className="min-h-screen bg-[#0a0a0f] flex items-center justify-center">
        <Loader2 className="w-8 h-8 text-violet-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col items-center justify-center px-6">
      <div className="w-full max-w-sm">
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-center mb-8"
        >
          <div className="w-20 h-20 rounded-2xl bg-gradient-to-br from-violet-500 to-cyan-400 flex items-center justify-center shadow-lg shadow-violet-500/30 mb-4 mx-auto">
            <User className="w-10 h-10 text-white" />
          </div>
          <h1 className="text-3xl font-black text-white mb-2">Choose a Username</h1>
          <p className="text-white/40 text-sm">This name will appear on your profile and leaderboard</p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
          className="space-y-4"
        >
          <div>
            <input
              type="text"
              value={name}
              onChange={(e) => { setName(e.target.value); setError(""); }}
              placeholder="Enter username..."
              maxLength={20}
              className="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-4 text-white text-lg font-bold placeholder:text-white/20 focus:outline-none focus:border-violet-500/50 focus:ring-2 focus:ring-violet-500/20 transition-all text-center"
              autoFocus
              disabled={loading}
            />
            {error && (
              <p className="text-red-400 text-xs text-center mt-2">{error}</p>
            )}
            <p className="text-white/20 text-xs text-center mt-2">{name.trim().length}/20</p>
          </div>

          <motion.button
            whileTap={{ scale: 0.97 }}
            onClick={handleSave}
            disabled={loading}
            className="w-full py-5 rounded-2xl bg-gradient-to-r from-violet-600 to-cyan-500 text-white text-xl font-black tracking-wide shadow-xl shadow-violet-500/30 flex items-center justify-center gap-3 disabled:opacity-50"
          >
            {loading ? (
              <Loader2 className="w-6 h-6 animate-spin" />
            ) : (
              <>
                <Check className="w-6 h-6" />
                SAVE
              </>
            )}
          </motion.button>

          {isEdit && (
            <motion.button
              whileTap={{ scale: 0.97 }}
              onClick={() => navigate(createPageUrl(redirectTo))}
              className="w-full py-4 rounded-2xl bg-white/5 border border-white/10 text-white/40 font-semibold flex items-center justify-center gap-2"
            >
              <ArrowLeft className="w-4 h-4" />
              BACK
            </motion.button>
          )}
        </motion.div>
      </div>
    </div>
  );
}