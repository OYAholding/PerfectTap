import React, { useEffect, useState } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { Trophy, Home, Star } from "lucide-react";
import ShareButtons from "@/components/game/ShareButtons";
import { CHALLENGES } from "./Challenges";

export default function ChallengeComplete() {
  const [challenge, setChallenge] = useState(null);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const id = params.get("id");
    const found = CHALLENGES.find(c => c.id === id);
    setChallenge(found || null);
  }, []);

  if (!challenge) return null;

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col items-center justify-center px-6 relative overflow-hidden">
      <div className="absolute inset-0 pointer-events-none">
        <div className="absolute top-1/3 left-1/2 -translate-x-1/2 w-96 h-96 bg-yellow-500/10 rounded-full blur-3xl" />
      </div>

      <div className="relative z-10 flex flex-col items-center w-full max-w-sm text-center">
        <motion.div initial={{ scale: 0, rotate: -20 }} animate={{ scale: 1, rotate: 0 }} transition={{ type: "spring", stiffness: 300, damping: 20 }}>
          <div className="text-8xl mb-4">{challenge.icon}</div>
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3 }}>
          <p className="text-yellow-400 text-sm tracking-widest uppercase font-bold mb-1">Challenge Complete!</p>
          <h1 className="text-4xl font-black text-white mb-2">{challenge.title}</h1>
          <p className="text-white/40 text-sm mb-8">{challenge.description}</p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.5 }}
          className="w-full bg-yellow-400/10 border border-yellow-400/30 rounded-3xl p-6 mb-8"
        >
          <div className="flex items-center gap-3 justify-center">
            <Trophy className="w-6 h-6 text-yellow-400" />
            <div>
              <p className="text-white/40 text-xs tracking-widest uppercase mb-0.5">Reward Unlocked</p>
              <p className="text-white font-black text-xl">{challenge.reward.label}</p>
            </div>
          </div>
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.65 }} className="w-full mb-2">
          <ShareButtons text={`🏆 I just completed the "${challenge.title}" challenge on Perfect Tap and unlocked: ${challenge.reward.label}! 🎯`} />
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.7 }} className="w-full flex flex-col gap-3">
          <Link to={createPageUrl("Challenges")}>
            <motion.button whileTap={{ scale: 0.97 }} className="w-full py-5 rounded-2xl bg-gradient-to-r from-yellow-500 to-orange-400 text-white text-lg font-black tracking-wide shadow-xl shadow-yellow-500/30 flex items-center justify-center gap-2">
              <Star className="w-5 h-5" />
              MORE CHALLENGES
            </motion.button>
          </Link>
          <Link to={createPageUrl("Home")}>
            <motion.button whileTap={{ scale: 0.97 }} className="w-full py-4 rounded-2xl bg-white/5 border border-white/10 text-white/70 text-lg font-semibold flex items-center justify-center gap-2">
              <Home className="w-5 h-5" />
              HOME
            </motion.button>
          </Link>
        </motion.div>
      </div>
    </div>
  );
}