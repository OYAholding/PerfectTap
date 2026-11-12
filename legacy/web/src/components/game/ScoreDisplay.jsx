import React, { memo } from "react";
import { motion } from "framer-motion";

const ScoreDisplay = memo(function ScoreDisplay({ score }) {
  return (
    <div>
      <p className="text-white/30 text-xs tracking-widest uppercase mb-0.5">Score</p>
      <motion.p
        key={score}
        initial={{ y: -8, opacity: 0.5 }}
        animate={{ y: 0, opacity: 1 }}
        className="text-4xl font-black text-white"
      >
        {score}
      </motion.p>
    </div>
  );
});

export default ScoreDisplay;