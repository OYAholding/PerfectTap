import React, { useEffect } from "react";
import { motion } from "framer-motion";
import BottomNav from "@/components/game/BottomNav";

export default function Layout({ children, currentPageName }) {
  // Sync system dark mode → apply 'dark' class on <html>
  useEffect(() => {
    const apply = (dark) => {
      document.documentElement.classList.toggle("dark", dark);
    };
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    apply(mq.matches);
    mq.addEventListener("change", (e) => apply(e.matches));
    return () => mq.removeEventListener("change", (e) => apply(e.matches));
  }, []);

  return (
    <div className="min-h-screen bg-[#0a0a0f] overflow-x-hidden">
      <style>{`
        /* Tap highlight + eliminate 300ms tap delay on mobile */
        * { -webkit-tap-highlight-color: transparent; }
        html { touch-action: manipulation; }

        /* Body baseline */
        body {
          background: #0a0a0f;
          overscroll-behavior: none;
          -webkit-font-smoothing: antialiased;
        }

        /* GPU-accelerate animated elements */
        [style*="transform"], .blur-2xl, .blur-xl {
          will-change: transform;
          -webkit-transform: translateZ(0);
          transform: translateZ(0);
        }

        /* Safe-area padding — applied once on the inner wrapper, not on body */

        /* Disable text selection on buttons and interactive UI */
        button, [role="button"], label, a,
        .select-none, [data-radix-collection-item] {
          user-select: none;
          -webkit-user-select: none;
        }

        :root {
          --color-bg: #0a0a0f;
          --color-surface: rgba(255,255,255,0.05);
          --color-border: rgba(255,255,255,0.1);
        }
      `}</style>

      {/* Safe-area aware inner wrapper */}
      <div
        className="max-w-md mx-auto min-h-screen"
        style={{
          paddingTop: "env(safe-area-inset-top)",
          paddingBottom: "env(safe-area-inset-bottom)",
        }}
      >
        <motion.div
          key={currentPageName}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.15 }}
          style={{ minHeight: "100vh" }}
          className="pb-20"
        >
          {children}
        </motion.div>
      </div>

      <BottomNav />
    </div>
  );
}