import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Coins, ShieldCheck, Sparkles } from "lucide-react";
import { addCoins, getCoins, COIN_PACKS, REMOVE_ADS_PRICE, isAdsRemoved, setAdsRemoved } from "@/components/game/coinSystem";

export default function CoinStore({ onCoinsChange }) {
  const [showConfirm, setShowConfirm] = useState(null);
  const [purchased, setPurchased] = useState(null);
  const adsRemoved = isAdsRemoved();

  const handleBuyCoins = (pack) => {
    // In production, this would trigger the App Store IAP flow
    // For now, simulate the purchase
    setShowConfirm(pack);
  };

  const confirmPurchase = (pack) => {
    // Mock IAP — in production, replace with real App Store purchase
    addCoins(pack.coins);
    onCoinsChange(getCoins());
    setPurchased(pack);
    setShowConfirm(null);
    setTimeout(() => setPurchased(null), 2000);
  };

  const handleRemoveAds = () => {
    // Mock IAP — in production, replace with real App Store purchase
    setAdsRemoved();
    setPurchased({ label: "Ads Removed", icon: "🚫", coins: 0 });
    setTimeout(() => setPurchased(null), 2000);
  };

  return (
    <div className="space-y-4">
      {/* Section Header */}
      <div className="flex items-center gap-2 mb-2">
        <Coins className="w-4 h-4 text-amber-400" />
        <p className="text-white/40 text-xs tracking-widest uppercase font-bold">Buy Coins</p>
      </div>

      {/* Coin Packs */}
      <div className="grid grid-cols-2 gap-3">
        {COIN_PACKS.map((pack, i) => (
          <motion.button
            key={pack.id}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: i * 0.05 }}
            whileTap={{ scale: 0.97 }}
            onClick={() => handleBuyCoins(pack)}
            className={`relative rounded-2xl border p-4 text-center transition-all ${
              pack.popular
                ? "border-amber-400/40 bg-amber-400/5"
                : "border-white/10 bg-white/5"
            }`}
          >
            {pack.popular && (
              <div className="absolute -top-2 left-1/2 -translate-x-1/2 bg-amber-400 text-black text-[9px] font-black px-2 py-0.5 rounded-full">
                POPULAR
              </div>
            )}
            <span className="text-3xl block mb-1">{pack.icon}</span>
            <p className="text-white font-bold text-sm">{pack.label}</p>
            <p className="text-amber-400 font-black text-lg">{pack.coins.toLocaleString()}</p>
            <p className="text-amber-400/60 text-[10px] tracking-widest">COINS</p>
            <div className="mt-2 py-1.5 rounded-xl bg-gradient-to-r from-amber-500 to-orange-500 text-white text-xs font-black">
              {pack.price}
            </div>
          </motion.button>
        ))}
      </div>

      {/* Remove Ads */}
      <div className="mt-4">
        <div className="flex items-center gap-2 mb-2">
          <ShieldCheck className="w-4 h-4 text-green-400" />
          <p className="text-white/40 text-xs tracking-widest uppercase font-bold">Premium</p>
        </div>

        <motion.button
          whileTap={{ scale: 0.97 }}
          onClick={handleRemoveAds}
          disabled={adsRemoved}
          className={`w-full rounded-2xl border p-4 flex items-center gap-4 transition-all ${
            adsRemoved
              ? "border-green-500/30 bg-green-500/10 opacity-60"
              : "border-green-500/20 bg-green-500/5 hover:bg-green-500/10"
          }`}
        >
          <div className="w-12 h-12 rounded-xl bg-green-500/20 flex items-center justify-center text-2xl">
            🚫
          </div>
          <div className="flex-1 text-left">
            <p className="text-white font-bold text-sm">
              {adsRemoved ? "Ads Removed ✓" : "Remove All Ads"}
            </p>
            <p className="text-white/30 text-xs">
              {adsRemoved ? "You have ad-free experience" : "No more ads when reviving"}
            </p>
          </div>
          {!adsRemoved && (
            <div className="py-1.5 px-3 rounded-xl bg-gradient-to-r from-green-500 to-emerald-500 text-white text-xs font-black">
              {REMOVE_ADS_PRICE}
            </div>
          )}
        </motion.button>
      </div>

      <p className="text-white/10 text-[10px] text-center mt-4">
        Purchases are simulated. Connect to App Store for real payments.
      </p>

      {/* Confirm Dialog */}
      <AnimatePresence>
        {showConfirm && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/80 flex items-center justify-center z-50 px-6"
          >
            <motion.div
              initial={{ scale: 0.8, y: 20 }}
              animate={{ scale: 1, y: 0 }}
              exit={{ scale: 0.8, opacity: 0 }}
              className="bg-[#12121a] border border-white/10 rounded-3xl p-6 max-w-xs w-full text-center"
            >
              <span className="text-4xl block mb-2">{showConfirm.icon}</span>
              <p className="text-white font-black text-lg mb-1">{showConfirm.label}</p>
              <p className="text-amber-400 font-bold mb-1">{showConfirm.coins.toLocaleString()} coins</p>
              <p className="text-white/30 text-xs mb-4">for {showConfirm.price}</p>
              <div className="flex gap-3">
                <motion.button
                  whileTap={{ scale: 0.97 }}
                  onClick={() => setShowConfirm(null)}
                  className="flex-1 py-3 rounded-xl bg-white/5 border border-white/10 text-white/40 font-bold text-sm"
                >
                  Cancel
                </motion.button>
                <motion.button
                  whileTap={{ scale: 0.97 }}
                  onClick={() => confirmPurchase(showConfirm)}
                  className="flex-1 py-3 rounded-xl bg-gradient-to-r from-amber-500 to-orange-500 text-white font-bold text-sm"
                >
                  Buy
                </motion.button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Purchase Success */}
      <AnimatePresence>
        {purchased && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 flex items-center justify-center z-50 pointer-events-none"
          >
            <motion.div
              initial={{ scale: 0.5, y: 40 }}
              animate={{ scale: 1, y: 0 }}
              exit={{ scale: 0.8, opacity: 0 }}
              className="bg-[#0a0a0f] border-2 border-amber-400/60 rounded-3xl px-10 py-8 text-center shadow-2xl"
            >
              <p className="text-5xl mb-3">{purchased.icon}</p>
              <p className="text-amber-400 font-black text-2xl">PURCHASED!</p>
              {purchased.coins > 0 && (
                <p className="text-white/60 text-sm mt-1">+{purchased.coins.toLocaleString()} coins</p>
              )}
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}