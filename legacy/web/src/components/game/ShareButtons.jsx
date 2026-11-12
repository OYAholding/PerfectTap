import React, { useState } from "react";
import { motion } from "framer-motion";
import { Share2, Check } from "lucide-react";

const TWITTER_BLUE = "#1DA1F2";
const FB_BLUE = "#1877F2";

export default function ShareButtons({ text }) {
  const [copied, setCopied] = useState(false);

  const encoded = encodeURIComponent(text);
  const twitterUrl = `https://twitter.com/intent/tweet?text=${encoded}`;
  const facebookUrl = `https://www.facebook.com/sharer/sharer.php?quote=${encoded}&u=https://perfecttap.app`;

  const handleCopy = () => {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.6 }}
      className="w-full"
    >
      <p className="text-white/30 text-xs tracking-widest uppercase text-center mb-3 flex items-center justify-center gap-1.5">
        <Share2 className="w-3 h-3" /> Share
      </p>
      <div className="flex gap-2">
        {/* Twitter / X */}
        <a
          href={twitterUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="flex-1"
        >
          <motion.button
            whileTap={{ scale: 0.95 }}
            className="w-full py-3 rounded-xl text-white text-sm font-bold flex items-center justify-center gap-2"
            style={{ background: "rgba(29,161,242,0.15)", border: "1px solid rgba(29,161,242,0.3)" }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" style={{ color: TWITTER_BLUE }}>
              <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-4.714-6.231-5.401 6.231H2.748l7.73-8.835L1.254 2.25H8.08l4.253 5.622zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
            </svg>
            <span style={{ color: TWITTER_BLUE }}>Tweet</span>
          </motion.button>
        </a>

        {/* Facebook */}
        <a
          href={facebookUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="flex-1"
        >
          <motion.button
            whileTap={{ scale: 0.95 }}
            className="w-full py-3 rounded-xl text-white text-sm font-bold flex items-center justify-center gap-2"
            style={{ background: "rgba(24,119,242,0.15)", border: "1px solid rgba(24,119,242,0.3)" }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill={FB_BLUE}>
              <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
            </svg>
            <span style={{ color: FB_BLUE }}>Share</span>
          </motion.button>
        </a>

        {/* Copy */}
        <motion.button
          whileTap={{ scale: 0.95 }}
          onClick={handleCopy}
          className="flex-1 py-3 rounded-xl text-sm font-bold flex items-center justify-center gap-2"
          style={{ background: "rgba(255,255,255,0.05)", border: "1px solid rgba(255,255,255,0.1)", color: copied ? "#4ade80" : "rgba(255,255,255,0.5)" }}
        >
          {copied ? <Check className="w-4 h-4" /> : <Share2 className="w-4 h-4" />}
          {copied ? "Copied!" : "Copy"}
        </motion.button>
      </div>
    </motion.div>
  );
}