import React, { memo } from "react";
import { motion } from "framer-motion";

const LivesDisplay = memo(function LivesDisplay({ lives }) {
  return (
    <div className="flex flex-col items-end">
      <p className="text-white/30 text-xs tracking-widest uppercase mb-1">Lives</p>
      <div className="flex gap-1.5">
        {[0, 1, 2].map((i) => (
          <motion.div
            key={i}
            animate={{
              scale: i < lives ? 1 : 0.7,
              opacity: i < lives ? 1 : 0.2,
            }}
            transition={{ type: "spring", stiffness: 400 }}
            className={`w-6 h-6 rounded-full flex items-center justify-center text-sm ${
              i < lives ? "bg-red-500/20" : "bg-white/5"
            }`}
          >
            {i < lives ? "❤️" : "🖤"}
          </motion.div>
        ))}
      </div>
    </div>
  );
});

export default LivesDisplay;