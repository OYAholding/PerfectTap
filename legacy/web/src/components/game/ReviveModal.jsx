import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Heart, X, Loader2, Play } from "lucide-react";
import { isAdsRemoved } from "@/components/game/coinSystem";
import { requestRewardedAd } from "@/components/game/nativeAdBridge";

export default function ReviveModal({ visible, onRevive, onDecline, mode }) {
  const [loading, setLoading] = useState(false);

  const handleWatchAd = async () => {
    if (isAdsRemoved()) {
      // No ad needed — instant revive
      onRevive();
      return;
    }
    setLoading(true);
    const result = await requestRewardedAd();
    setLoading(false);
    if (result.success) {
      onRevive();
    } else {
      onDecline();
    }
  };

  return (
    <AnimatePresence>
      {visible && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="absolute inset-0 bg-black/85 backdrop-blur-sm flex items-center justify-center z-50 px-6"
          onPointerDown={(e) => e.stopPropagation()}
        >
          <motion.div
            initial={{ scale: 0.8, opacity: 0, y: 30 }}
            animate={{ scale: 1, opacity: 1, y: 0 }}
            exit={{ scale: 0.8, opacity: 0, y: 30 }}
            transition={{ type: "spring", stiffness: 400, damping: 30 }}
            className="w-full max-w-xs"
          >
            {/* Pulsing heart icon */}
            <div className="flex justify-center mb-5">
              <motion.div
                animate={{ scale: [1, 1.15, 1] }}
                transition={{ duration: 1.2, repeat: Infinity, ease: "easeInOut" }}
                className="w-20 h-20 rounded-full bg-red-500/20 border-2 border-red-500/40 flex items-center justify-center"
              >
                <Heart className="w-10 h-10 text-red-400 fill-red-400" />
              </motion.div>
            </div>

            {/* Text */}
            <div className="text-center mb-6">
              <h2 className="text-white text-2xl font-black mb-1">DON'T GIVE UP!</h2>
              <p className="text-white/40 text-sm">
                {mode === "sudden_death" ? "Watch a short ad to get one more chance!" :
                 "Watch a short ad to revive and keep playing with full lives."}
              </p>
            </div>

            {/* Revive button */}
            <motion.button
              whileTap={!loading ? { scale: 0.97 } : {}}
              onClick={handleWatchAd}
              disabled={loading}
              className="w-full py-4 rounded-2xl bg-gradient-to-r from-red-500 to-pink-500 text-white text-lg font-black tracking-wide shadow-xl shadow-red-500/30 flex items-center justify-center gap-2.5 mb-3 disabled:opacity-70"
            >
              {loading ? (
                <>
                  <Loader2 className="w-5 h-5 animate-spin" />
                  Loading Ad...
                </>
              ) : isAdsRemoved() ? (
                <>
                  <Heart className="w-5 h-5 fill-white" />
                  Continue (No Ads)
                </>
              ) : (
                <>
                  <Play className="w-5 h-5 fill-white" />
                  Watch Ad to Continue
                </>
              )}
            </motion.button>

            {/* Reward info */}
            <div className="flex items-center justify-center gap-2 mb-4">
              {mode === "sudden_death" ? (
                <>
                  <Heart className="w-3.5 h-3.5 text-red-400 fill-red-400" />
                  <span className="text-white/30 text-xs">+1 Life Restored</span>
                </>
              ) : (
                <>
                  <div className="flex gap-0.5">
                    {[1, 2, 3].map(i => (
                      <Heart key={i} className="w-3.5 h-3.5 text-red-400 fill-red-400" />
                    ))}
                  </div>
                  <span className="text-white/30 text-xs">+3 Lives Restored</span>
                </>
              )}
            </div>

            {/* Decline button */}
            <motion.button
              whileTap={{ scale: 0.97 }}
              onClick={onDecline}
              disabled={loading}
              className="w-full py-3.5 rounded-2xl bg-white/5 border border-white/10 text-white/40 text-base font-semibold flex items-center justify-center gap-2 disabled:opacity-50"
            >
              <X className="w-4 h-4" />
              No Thanks
            </motion.button>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}