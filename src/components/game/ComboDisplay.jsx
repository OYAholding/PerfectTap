import React, { memo } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Zap } from "lucide-react";

const ComboDisplay = memo(function ComboDisplay({ combo }) {
  if (combo < 2) return <div className="h-10" />;

  const isHot = combo >= 5;

  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={combo}
        initial={{ scale: 0.7, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        exit={{ scale: 1.2, opacity: 0 }}
        transition={{ type: "spring", stiffness: 500, damping: 20 }}
        className={`flex items-center gap-2 rounded-full px-4 py-2 ${
          isHot
            ? "bg-orange-500/20 border border-orange-400/40"
            : "bg-cyan-500/10 border border-cyan-500/20"
        }`}
        style={{
          boxShadow: isHot
            ? "0 0 20px rgba(251,146,60,0.4)"
            : "0 0 12px rgba(6,182,212,0.2)",
        }}
      >
        <Zap
          className={`w-4 h-4 ${isHot ? "text-orange-400" : "text-cyan-400"}`}
          fill={isHot ? "currentColor" : "none"}
        />
        <span
          className={`font-black text-lg tracking-widest ${
            isHot ? "text-orange-300" : "text-cyan-300"
          }`}
        >
          x{combo} COMBO
        </span>
        {isHot && (
          <motion.span
            animate={{ opacity: [1, 0.5, 1] }}
            transition={{ repeat: Infinity, duration: 0.6 }}
            className="text-orange-400 text-sm"
          >
            🔥
          </motion.span>
        )}
      </motion.div>
    </AnimatePresence>
  );
});

export default ComboDisplay;