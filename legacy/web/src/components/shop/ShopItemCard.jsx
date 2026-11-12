import React from "react";
import { motion } from "framer-motion";
import { Check, Lock, Coins } from "lucide-react";
import { RARITY } from "@/components/game/shopData";

export default function ShopItemCard({ item, category, isOwned, isEquipped, canAfford, onBuy, onEquip, index }) {
  const isFree = item.price === 0;
  const rarity = RARITY[item.rarity] || RARITY.common;

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: index * 0.05 }}
      onClick={() => {
        if (isOwned || isFree) onEquip(item.id);
        else if (canAfford) onBuy(item);
      }}
      className={`relative rounded-2xl border p-4 flex items-center gap-4 cursor-pointer transition-all ${
        isEquipped
          ? "border-violet-500/60 bg-violet-500/10"
          : isOwned || isFree
          ? "border-white/10 bg-white/5 hover:bg-white/8"
          : canAfford
          ? "border-amber-500/20 bg-amber-500/5 hover:bg-amber-500/10"
          : "border-white/5 bg-white/2 opacity-50"
      }`}
    >
      {/* Preview */}
      {category === "themes" ? (
        <div className={`w-14 h-14 rounded-xl bg-gradient-to-br ${item.preview} flex-shrink-0 shadow-lg`} />
      ) : (
        <div className="w-14 h-14 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-2xl flex-shrink-0">
          {item.icon}
        </div>
      )}

      {/* Info */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 mb-0.5">
          <p className={`font-bold ${isOwned || isFree ? "text-white" : canAfford ? "text-amber-200" : "text-white/40"}`}>
            {item.name}
          </p>
          {item.rarity && item.rarity !== "common" && (
            <span className={`text-[9px] font-bold px-1.5 py-0.5 rounded-full border ${rarity.border} ${rarity.bg} ${rarity.color}`}>
              {rarity.label.toUpperCase()}
            </span>
          )}
        </div>
        <p className="text-white/30 text-xs truncate">{item.description}</p>
      </div>

      {/* Price / Status */}
      <div className="flex-shrink-0">
        {isEquipped ? (
          <div className="w-8 h-8 rounded-full bg-violet-500 flex items-center justify-center">
            <Check className="w-4 h-4 text-white" />
          </div>
        ) : isOwned || isFree ? (
          <div className="w-8 h-8 rounded-full bg-white/10 border border-white/20 flex items-center justify-center">
            <span className="text-[10px] text-white/50 font-bold">USE</span>
          </div>
        ) : (
          <div className="flex items-center gap-1 bg-amber-400/10 border border-amber-400/20 rounded-full px-2.5 py-1">
            <Coins className="w-3 h-3 text-amber-400" />
            <span className="text-amber-400 text-xs font-bold">{item.price}</span>
          </div>
        )}
      </div>
    </motion.div>
  );
}